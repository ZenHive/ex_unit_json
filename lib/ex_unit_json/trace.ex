defmodule ExUnitJSON.Trace do
  @moduledoc """
  Opt-in failure-only BEAM message tracing for `mix test.json`.

  Adds a "flight recorder" to a test: while the test runs, the inter-process
  `send`/`receive` messages of the test process tree are captured into a bounded
  ring buffer. If the test **fails**, the messages (and a best-effort mailbox
  snapshot of still-alive processes) are emitted into the JSON output under a
  `"trace"` key; if it **passes**, the buffer is discarded. This surfaces the
  message flow that led to a failure for AI consumers debugging GenServer / Port /
  LiveView interactions.

  ## Enabling

  Tracing must start *inside* the test process (the formatter runs separately and
  only sees a test once it is already finished), so it is wired via a `setup`
  callback you add once to your shared `ExUnit.Case` template:

      defmodule MyApp.Case do
        use ExUnit.CaseTemplate

        using do
          quote do
            setup {ExUnitJSON.Trace, :setup}
          end
        end
      end

  Then activate it per test or per module with a tag:

      @moduletag trace_messages: true          # whole module
      @tag trace_messages: true                # one test
      @tag trace_messages: 200                 # one test, ring size 200

  Without the tag the `setup` callback is a zero-cost no-op, so it is safe to wire
  globally.

  ## What it can and cannot capture

  The recorded message **flow** (the ring buffer, with relative timestamps) is the
  reliable signal. The mailbox snapshot is **best-effort and marked `approx`**:
  by the time a failing test's process dies, its own mailbox is gone, and only
  processes still alive near the failure can be sampled. There is no authoritative
  "what was unread when it crashed" on the BEAM — that is physically unrecoverable.

  Requires OTP 27+ (for `:trace` dynamic sessions), already implied by the library's
  use of the built-in `:json` module.
  """

  alias ExUnitJSON.Trace.Recorder
  alias ExUnitJSON.Trace.Store

  @doc """
  ExUnit `setup` callback. Use as `setup {ExUnitJSON.Trace, :setup}`.

  Reads `:trace_messages` from the test context. When falsy/absent it is a no-op.
  When truthy it starts a recorder tracing this test process and the ExUnit test
  supervisor (so `start_supervised/2` children are covered). An integer value sets
  the ring-buffer size.
  """
  @spec setup(map()) :: :ok
  def setup(context) do
    case Map.get(context, :trace_messages) do
      value when value in [nil, false] ->
        :ok

      value ->
        start_trace(context, value)
    end
  end

  defp start_trace(context, value) do
    Store.ensure_started()
    test_pid = self()
    opts = if is_integer(value), do: [cap: value], else: []
    {:ok, recorder} = Recorder.start(test_key(context), opts)
    Recorder.attach(recorder, [test_pid | supervisor_pids()], test_pid)
    # Flush synchronously after the test ends so the store write is ordered before
    # the formatter reads it at :test_finished (avoids a take-before-write race).
    ExUnit.Callbacks.on_exit(fn -> Recorder.await(recorder) end)
    :ok
  end

  defp test_key(context), do: {context.module, context.test}

  defp supervisor_pids do
    case ExUnit.fetch_test_supervisor() do
      {:ok, pid} -> [pid]
      _ -> []
    end
  end
end
