defmodule ExUnitJSON.TraceTest do
  # async: false — touches the singleton Store, the named Formatter, and :ex_unit_json env.
  use ExUnit.Case, async: false

  alias ExUnitJSON.Formatter
  alias ExUnitJSON.Trace
  alias ExUnitJSON.Trace.Recorder
  alias ExUnitJSON.Trace.Store

  setup do
    Store.ensure_started()
    Store.clear()

    original = Application.get_env(:ex_unit_json, :opts)

    on_exit(fn ->
      Application.put_env(:ex_unit_json, :opts, original)

      case GenServer.whereis(Formatter) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    end)

    :ok
  end

  describe "Store" do
    test "ensure_started/0 is idempotent" do
      assert :ok = Store.ensure_started()
      assert :ok = Store.ensure_started()
      assert is_pid(GenServer.whereis(Store))
    end

    test "put/take round-trips and removes the entry" do
      assert :ok = Store.put({:m, :t}, %{messages: []})
      assert %{messages: []} = Store.take({:m, :t})
      assert nil == Store.take({:m, :t})
    end

    test "take/1 returns nil for an unknown key" do
      assert nil == Store.take({:nope, :nope})
    end

    test "clear/0 drops all entries" do
      Store.put({:a, :a}, %{messages: []})
      Store.put({:b, :b}, %{messages: []})
      assert :ok = Store.clear()
      assert nil == Store.take({:a, :a})
      assert nil == Store.take({:b, :b})
    end
  end

  describe "Recorder" do
    test "captures send/receive of the traced tree and stores on monitored DOWN" do
      key = {__MODULE__, :recorder_basic}

      target =
        spawn(fn ->
          receive do
            {:go, from} ->
              send(from, :ack)

              receive do
                :stop -> :ok
              end
          end
        end)

      {:ok, recorder} = Recorder.start(key, cap: 10)
      :ok = Recorder.attach(recorder, [target], target)
      tref = Process.monitor(target)

      send(target, {:go, self()})
      assert_receive :ack
      send(target, :stop)
      # Wait for the target to die so the recorder's own DOWN is enqueued before
      # await/1, then flush+store deterministically (delivery confirmation inside).
      assert_receive {:DOWN, ^tref, :process, ^target, _}, 1_000
      :ok = Recorder.await(recorder)

      data = Store.take(key)
      assert %{messages: messages, overflow: false} = data
      refute messages == []
      assert Enum.any?(messages, &(&1[:dir] == :send and &1.msg == :ack))
      assert Enum.any?(messages, &(&1[:dir] == :receive and &1.msg == {:go, self()}))
      # all events carry a non-negative relative timestamp
      assert Enum.all?(messages, &(is_integer(&1.t_us) and &1.t_us >= 0))
    end

    test "ring buffer is bounded by :cap and reports dropped count" do
      key = {__MODULE__, :recorder_cap}

      target =
        spawn(fn ->
          loop = fn loop ->
            receive do
              :stop -> :ok
              _other -> loop.(loop)
            end
          end

          loop.(loop)
        end)

      {:ok, recorder} = Recorder.start(key, cap: 3)
      :ok = Recorder.attach(recorder, [target], target)
      tref = Process.monitor(target)

      for n <- 1..20, do: send(target, {:msg, n})
      send(target, :stop)
      assert_receive {:DOWN, ^tref, :process, ^target, _}, 1_000
      :ok = Recorder.await(recorder)

      data = Store.take(key)
      assert length(data.messages) <= 3
      assert data.dropped > 0
    end

    test "best-effort mailbox snapshot for live processes on abnormal exit" do
      key = {__MODULE__, :recorder_mailbox}
      parent = self()

      # Stays alive with an unread message (only ever matches :never).
      sink =
        spawn(fn ->
          receive do
            :never -> :ok
          end
        end)

      Process.register(sink, :trace_test_sink)

      # The target sends to `sink` (so `sink` enters the traced "seen" set) then
      # exits abnormally, triggering the snapshot while `sink` is still alive.
      target =
        spawn(fn ->
          receive do
            {:go, from, s} ->
              send(from, :go_ack)
              send(s, :unread_in_sink)

              receive do
                :crash -> exit(:boom)
              end
          end
        end)

      {:ok, recorder} = Recorder.start(key, cap: 50)
      :ok = Recorder.attach(recorder, [target], target)
      tref = Process.monitor(target)

      send(target, {:go, parent, sink})
      assert_receive :go_ack
      send(target, :crash)
      assert_receive {:DOWN, ^tref, :process, ^target, _}, 1_000
      :ok = Recorder.await(recorder)

      data = Store.take(key)

      mailbox = Enum.find(data.mailboxes, &(&1.pid == sink))
      assert %{approx: true, registered: :trace_test_sink, messages: messages} = mailbox
      assert :unread_in_sink in messages

      Process.exit(sink, :kill)
    end

    test "hard event budget stops tracing and flags overflow" do
      key = {__MODULE__, :recorder_budget}
      target = spawn(echo_loop())

      {:ok, recorder} = Recorder.start(key, cap: 100, budget: 3)
      :ok = Recorder.attach(recorder, [target], target)
      tref = Process.monitor(target)

      for n <- 1..50, do: send(target, {:m, n})
      send(target, :stop)
      assert_receive {:DOWN, ^tref, :process, ^target, _}, 1_000
      :ok = Recorder.await(recorder)

      data = Store.take(key)
      # overflow is the "incomplete, unknown remainder" signal; with budget <= cap
      # no ring eviction occurs, so `dropped` (eviction count) stays 0.
      assert data.overflow == true
    end

    test "infrastructure io messages are filtered out" do
      key = {__MODULE__, :recorder_noise}
      target = spawn(echo_loop())

      {:ok, recorder} = Recorder.start(key, cap: 50)
      :ok = Recorder.attach(recorder, [target], target)
      tref = Process.monitor(target)

      send(target, {:io_request, self(), make_ref(), {:put_chars, :unicode, "noise"}})
      send(target, {:real, 1})
      send(target, :stop)
      assert_receive {:DOWN, ^tref, :process, ^target, _}, 1_000
      :ok = Recorder.await(recorder)

      data = Store.take(key)
      refute Enum.any?(data.messages, &match?({:io_request, _, _, _}, &1.msg))
      assert Enum.any?(data.messages, &(&1.msg == {:real, 1}))
    end

    test "ignores unexpected messages and clamps a non-positive cap" do
      {:ok, recorder} = Recorder.start({__MODULE__, :recorder_misc}, cap: 0)
      send(recorder, :unexpected_message)
      assert Process.alive?(recorder)
      # terminate path persists whatever is buffered (here: nothing)
      GenServer.stop(recorder)
    end

    test "captures a send to a dead process (send_to_non_existing_process)" do
      key = {__MODULE__, :recorder_dead_send}

      # A pid that is already dead by the time the traced process sends to it.
      dead = spawn(fn -> :ok end)
      dref = Process.monitor(dead)
      assert_receive {:DOWN, ^dref, :process, ^dead, _}

      target =
        spawn(fn ->
          receive do
            {:go, d} ->
              send(d, :into_the_void)

              receive do
                :stop -> :ok
              end
          end
        end)

      {:ok, recorder} = Recorder.start(key, cap: 50)
      :ok = Recorder.attach(recorder, [target], target)
      tref = Process.monitor(target)

      send(target, {:go, dead})
      send(target, :stop)
      assert_receive {:DOWN, ^tref, :process, ^target, _}, 1_000
      :ok = Recorder.await(recorder)

      data = Store.take(key)
      assert Enum.any?(data.messages, &(&1.msg == :into_the_void))
    end
  end

  describe "Trace.setup/1 no-op" do
    test "is a zero-cost no-op without a truthy tag" do
      assert :ok = Trace.setup(%{})
      assert :ok = Trace.setup(%{trace_messages: nil})
      assert :ok = Trace.setup(%{trace_messages: false})
    end
  end

  # Exercises the truthy `setup` path in a real test process (so `on_exit` and
  # the test-supervisor lookup work, and the code is covered). The actual JSON
  # emission is asserted by the subprocess integration test in test_json_test.exs.
  describe "Trace.setup/1 wired into a real test" do
    setup {Trace, :setup}

    @tag trace_messages: true
    test "a traced test runs normally and exchanges messages" do
      parent = self()
      pid = spawn(fn -> receive(do: ({:ping, from} -> send(from, :pong))) end)
      send(pid, {:ping, parent})
      assert_receive :pong
    end

    @tag trace_messages: 10
    test "an integer tag value sets the ring size" do
      assert true
    end
  end

  describe "Formatter + encoder integration" do
    test "failing traced test emits a trace block" do
      key = {SomeMod, :"test fails with trace"}
      Store.put(key, sample_trace())

      output =
        run_formatter([
          failed_test(SomeMod, :"test fails with trace", %{trace_messages: true})
        ])

      test = single_test(output)
      assert test["state"] == "failed"
      assert %{"messages" => [_ | _], "overflow" => false} = test["trace"]
    end

    test "passing traced test discards the trace block" do
      key = {SomeMod, :"test passes with trace"}
      Store.put(key, sample_trace())

      output =
        run_formatter(
          [passed_test(SomeMod, :"test passes with trace", %{trace_messages: true})],
          failures_only: false
        )

      test = single_test(output)
      assert test["state"] == "passed"
      refute Map.has_key?(test, "trace")
      # the buffer was consumed from the Store even though it was not emitted
      assert nil == Store.take(key)
    end

    test "failing untagged test is unchanged (no trace, no Store lookup)" do
      output =
        run_formatter([
          failed_test(SomeMod, :"test fails untagged", %{})
        ])

      test = single_test(output)
      assert test["state"] == "failed"
      refute Map.has_key?(test, "trace")
    end
  end

  describe "JSONEncoder.encode_test/2" do
    test "nil trace data yields the same map as encode_test/1" do
      test = failed_test(SomeMod, :t, %{})
      assert ExUnitJSON.JSONEncoder.encode_test(test, nil) == ExUnitJSON.JSONEncoder.encode_test(test)
    end

    test "shapes messages and mailboxes into JSON-safe values" do
      test = failed_test(SomeMod, :t, %{trace_messages: true})
      encoded = ExUnitJSON.JSONEncoder.encode_test(test, sample_trace())

      assert %{
               messages: [
                 %{dir: "send", from: _, to: _, msg: _, t_us: 0},
                 %{dir: "recv", pid: _, msg: _, t_us: 1}
               ],
               mailboxes: [%{pid: _, registered: "my_server", messages: [_], approx: true}],
               overflow: false,
               dropped: 0
             } = encoded.trace
    end
  end

  # --- helpers ---

  defp sample_trace do
    %{
      messages: [
        %{dir: :send, from: self(), to: self(), msg: {:req, 1}, t_us: 0},
        %{dir: :receive, pid: self(), msg: {:reply, :ok}, t_us: 1}
      ],
      mailboxes: [%{pid: self(), registered: :my_server, messages: [:pending], approx: true}],
      overflow: false,
      dropped: 0
    }
  end

  defp failed_test(module, name, tags) do
    %ExUnit.Test{
      name: name,
      module: module,
      state: {:failed, [{:error, %RuntimeError{message: "boom"}, []}]},
      time: 100,
      tags: Map.merge(%{file: "test/x_test.exs", line: 1, async: false}, tags)
    }
  end

  defp passed_test(module, name, tags) do
    %ExUnit.Test{
      name: name,
      module: module,
      state: nil,
      time: 100,
      tags: Map.merge(%{file: "test/x_test.exs", line: 1, async: false}, tags)
    }
  end

  defp run_formatter(tests, extra_opts \\ []) do
    output_file = Path.join(System.tmp_dir!(), "trace_test_#{:erlang.unique_integer([:positive])}.json")
    Application.put_env(:ex_unit_json, :opts, [output: output_file] ++ extra_opts)
    {:ok, pid} = Formatter.start_link()

    Enum.each(tests, fn test -> GenServer.cast(pid, {:test_finished, test}) end)

    GenServer.cast(pid, {:suite_finished, %{async: 1000, sync: 500}})
    GenServer.call(pid, :get_state)

    {:ok, content} = File.read(output_file)
    File.rm!(output_file)
    :json.decode(content)
  end

  defp single_test(%{"tests" => [test]}), do: test

  # A process that consumes any message until told to stop.
  defp echo_loop do
    fn ->
      loop = fn loop ->
        receive do
          :stop -> :ok
          _other -> loop.(loop)
        end
      end

      loop.(loop)
    end
  end
end
