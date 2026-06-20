defmodule ExUnitJSON.Trace.Recorder do
  @moduledoc """
  Per-test tracer process: the "flight recorder" half of message tracing.

  Created by `ExUnitJSON.Trace` when a test opts in via `@tag trace_messages`.
  The recorder owns an OTP-27 dynamic trace session (`:trace.session_create/3`)
  with itself as the tracer, so it survives the test process dying on failure
  (it is started *unlinked*). It records `:send`/`:receive` events of the traced
  process tree into a bounded ring buffer, and when the monitored test process
  exits it freezes the buffer, takes a best-effort mailbox snapshot of still-alive
  traced processes, and writes the result to `ExUnitJSON.Trace.Store`.

  Bounding is twofold: the ring keeps only the last `:cap` events, and a hard
  `:budget` on total events received stops tracing entirely (setting `overflow`)
  so a chatty process tree cannot flood the recorder's own mailbox.
  """

  use GenServer

  alias ExUnitJSON.Trace.Store

  @default_cap 50
  @default_budget 5_000

  @trace_flags [:send, :receive, :set_on_spawn, :strict_monotonic_timestamp]

  @typedoc "A recorded send/receive event with a relative microsecond timestamp"
  @type event :: map()

  @doc """
  Starts a recorder (unlinked, so it outlives the test process).

  Options: `:cap` (ring size, default #{@default_cap}), `:budget` (max events
  before tracing stops, default #{@default_budget}).
  """
  @spec start(term(), keyword()) :: {:ok, pid()}
  def start(key, opts \\ []) do
    GenServer.start(__MODULE__, {key, opts})
  end

  @doc """
  Begins tracing `trace_pids` and monitors `monitor_pid` (the test process).
  Returns once tracing is active, so the caller's subsequent work is captured.
  """
  @spec attach(pid(), [pid()], pid()) :: :ok
  def attach(recorder, trace_pids, monitor_pid) do
    GenServer.call(recorder, {:attach, trace_pids, monitor_pid})
  end

  @doc """
  Blocks until the recorder has written its buffer to the store, then stops it.

  Called from an `on_exit` callback so the store write happens-before the formatter
  reads it at `:test_finished`. The monitored process's `:DOWN` is already enqueued
  by the time `on_exit` runs, so it is processed before this call — the snapshot is
  taken while children are still alive. Tolerates an already-stopped recorder.
  """
  @spec await(pid()) :: :ok
  def await(recorder) do
    GenServer.call(recorder, :await)
  catch
    :exit, _ -> :ok
  end

  @impl GenServer
  def init({key, opts}) do
    cap = opts |> Keyword.get(:cap, @default_cap) |> normalize_pos(@default_cap)
    budget = opts |> Keyword.get(:budget, @default_budget) |> normalize_pos(@default_budget)
    name = :"ex_unit_json_trace_#{:erlang.unique_integer([:positive])}"
    session = :trace.session_create(name, self(), [])

    {:ok,
     %{
       key: key,
       session: session,
       cap: cap,
       budget: budget,
       ring: :queue.new(),
       size: 0,
       count: 0,
       overflow: false,
       finalized: false,
       first_ts: nil,
       seen: MapSet.new(),
       reason: nil,
       mailboxes: [],
       await_from: nil,
       flush_ref: nil
     }}
  end

  @impl GenServer
  def handle_call({:attach, trace_pids, monitor_pid}, _from, state) do
    Enum.each(trace_pids, fn pid -> safe(fn -> :trace.process(state.session, pid, true, @trace_flags) end) end)
    Process.monitor(monitor_pid)
    {:reply, :ok, %{state | seen: MapSet.put(state.seen, monitor_pid)}}
  end

  # Defer the reply: request a trace-delivery confirmation so any in-flight trace
  # events are processed before we freeze the buffer, then store and reply when the
  # confirmation arrives. This is what makes the captured set complete and the
  # whole handoff deterministic (no take-before-write, no missed tail events).
  def handle_call(:await, _from, %{finalized: true} = state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(:await, from, state) do
    ref = safe(fn -> :trace.delivered(state.session, :all) end)

    case ref do
      ref when is_reference(ref) -> {:noreply, %{state | await_from: from, flush_ref: ref}}
      # session already gone (e.g. overflow destroyed it) — nothing more to flush
      _error -> {:stop, :normal, :ok, build_and_store(state)}
    end
  end

  @impl GenServer
  def handle_info({:trace_ts, pid, :send, msg, to, ts}, state) do
    {:noreply, record(state, %{dir: :send, from: pid, to: to, msg: msg}, pid, to, ts)}
  end

  def handle_info({:trace_ts, pid, :receive, msg, ts}, state) do
    {:noreply, record(state, %{dir: :receive, pid: pid, msg: msg}, pid, nil, ts)}
  end

  # A traced process sent to a dead/unregistered pid — a classic cause of the
  # failure being recorded. Captured as a send so the message flow shows it.
  def handle_info({:trace_ts, pid, :send_to_non_existing_process, msg, to, ts}, state) do
    {:noreply, record(state, %{dir: :send, from: pid, to: to, msg: msg}, pid, to, ts)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    # The monitored test process died. Snapshot still-traced processes now. This is
    # best-effort: ExUnit stops `start_supervised` children between the test process
    # dying and on_exit, so this DOWN handler races that teardown. Deferred to await/1.
    mailboxes = if reason == :normal, do: [], else: snapshot_mailboxes(state)
    {:noreply, %{state | reason: reason, mailboxes: mailboxes}}
  end

  def handle_info({:trace_delivered, :all, ref}, %{flush_ref: ref} = state) do
    state = build_and_store(state)
    if state.await_from, do: GenServer.reply(state.await_from, :ok)
    {:stop, :normal, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    # Safety net: persist whatever we have if stopped without an await flush.
    build_and_store(state)
    :ok
  end

  # --- internal ---

  defp record(%{overflow: true} = state, _entry, _pid, _to, _ts), do: state

  defp record(state, entry, pid, to, ts) do
    if noise?(entry.msg) do
      state
    else
      mono = elem(ts, 0)
      first = state.first_ts || mono
      event = Map.put(entry, :t_us, div(mono - first, 1000))

      state =
        state
        |> Map.put(:first_ts, first)
        |> Map.update!(:count, &(&1 + 1))
        |> track_seen(pid, to)
        |> push(event)

      if state.count >= state.budget, do: stop_tracing(state), else: state
    end
  end

  defp push(state, event) do
    ring = :queue.in(event, state.ring)

    if state.size >= state.cap do
      {_dropped, ring} = :queue.out(ring)
      %{state | ring: ring}
    else
      %{state | ring: ring, size: state.size + 1}
    end
  end

  defp track_seen(state, pid, to) do
    seen = state.seen |> MapSet.put(pid) |> maybe_put(to)
    %{state | seen: seen}
  end

  defp maybe_put(set, nil), do: set
  defp maybe_put(set, pid) when is_pid(pid), do: MapSet.put(set, pid)
  defp maybe_put(set, _other), do: set

  # On budget overflow, destroying the session is the cheapest way to stop all
  # tracing at once (vs. disabling each pid). Further in-flight events are dropped
  # by the `overflow: true` guard in `record/5`.
  defp stop_tracing(state) do
    safe(fn -> :trace.session_destroy(state.session) end)
    %{state | overflow: true}
  end

  # Freezes the buffer and writes it to the store exactly once. Mailboxes were
  # snapshotted at DOWN (while children were alive); the message ring is now
  # complete because the delivery flush has run before this is called.
  defp build_and_store(%{finalized: true} = state), do: state

  defp build_and_store(state) do
    if !state.overflow, do: safe(fn -> :trace.session_destroy(state.session) end)

    data = %{
      messages: :queue.to_list(state.ring),
      mailboxes: state.mailboxes,
      overflow: state.overflow,
      dropped: max(state.count - state.size, 0)
    }

    Store.put(state.key, data)
    %{state | finalized: true}
  end

  # Best-effort: the test process itself is already dead here (its mailbox is gone).
  # Traced children may or may not still be alive — ExUnit stops `start_supervised`
  # children before on_exit, so this snapshot races that teardown and captures
  # whoever is still up. Snapshots are marked `approx: true` — a near-failure sample,
  # not an authoritative crash dump.
  defp snapshot_mailboxes(state) do
    state.seen
    |> Enum.filter(&Process.alive?/1)
    |> Enum.map(&mailbox_of(&1, state.cap))
    |> Enum.reject(&(&1 == nil or &1.messages == []))
  end

  defp mailbox_of(pid, cap) do
    case :erlang.process_info(pid, [:messages, :registered_name]) do
      [{:messages, msgs}, {:registered_name, reg}] ->
        %{pid: pid, registered: registered(reg), messages: Enum.take(msgs, cap), approx: true}

      _ ->
        nil
    end
  end

  defp registered([]), do: nil
  defp registered(name) when is_atom(name), do: name
  defp registered(_), do: nil

  # ExUnit's log capture turns into a constant stream of these on the test process;
  # they are pure infrastructure noise, never the message flow under test.
  defp noise?({:io_request, _, _, _}), do: true
  defp noise?({:io_reply, _, _}), do: true
  defp noise?(_), do: false

  defp normalize_pos(n, _default) when is_integer(n) and n > 0, do: n
  defp normalize_pos(_n, default), do: default

  defp safe(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end
end
