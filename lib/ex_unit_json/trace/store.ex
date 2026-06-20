defmodule ExUnitJSON.Trace.Store do
  @moduledoc """
  Cross-process handoff store for trace data captured by `ExUnitJSON.Trace.Recorder`.

  Tracing happens inside the test process (and its tree); the JSON is emitted by
  `ExUnitJSON.Formatter`, which runs in a *separate* process and only learns of a
  test at `:test_finished` (when the test process is already dead). This module
  bridges the two: a tiny registered owner process holds a named public ETS table
  that recorders write to (keyed by the test's `{module, name}`) and the formatter
  reads from.

  A dedicated owner process (rather than letting the formatter own the table)
  avoids an init-ordering race: a test's `setup` may run before the formatter's
  `init/1`, and writing into a not-yet-created table would crash. `ensure_started/0`
  is idempotent and safe to call from both the formatter and every traced test.
  """

  use GenServer

  @table :ex_unit_json_trace_store

  @doc """
  Starts the store if it is not already running. Idempotent and concurrency-safe.
  """
  @spec ensure_started() :: :ok
  def ensure_started do
    case GenServer.whereis(__MODULE__) do
      nil ->
        case GenServer.start(__MODULE__, [], name: __MODULE__) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  @doc """
  Stores `value` under `key`. Called by a recorder from the test process tree.
  """
  @spec put(term(), term()) :: :ok
  def put(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  end

  @doc """
  Removes and returns the value stored under `key`, or `nil` if absent.
  """
  @spec take(term()) :: term() | nil
  def take(key) do
    case :ets.take(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Drops all stored entries. Called at suite finish to bound memory against any
  entries left by tests that were written but never read.
  """
  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _tid -> :ets.delete_all_objects(@table)
    end

    :ok
  end

  @impl GenServer
  def init([]) do
    table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, table}
  end
end
