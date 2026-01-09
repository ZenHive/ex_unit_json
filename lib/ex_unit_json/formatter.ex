defmodule ExUnitJSON.Formatter do
  @moduledoc """
  ExUnit formatter that outputs test results as JSON.

  This GenServer receives events from ExUnit during test execution
  and accumulates results. When the test suite finishes, it outputs
  a complete JSON document with all test results and summary statistics.

  ## Usage

  Configure ExUnit to use this formatter:

      ExUnit.configure(formatters: [ExUnitJSON.Formatter])

  Or use the `mix test.json` task which configures this automatically.

  ## Events Handled

    * `{:suite_started, opts}` - Captures seed and start time
    * `{:test_finished, test}` - Accumulates individual test results
    * `{:module_finished, module}` - Tracks module-level failures (setup_all)
    * `{:suite_finished, times_us}` - Outputs final JSON (Task 5)

  """

  use GenServer

  alias ExUnitJSON.Config
  alias ExUnitJSON.JSONEncoder

  defstruct [:seed, :start_time, tests: [], modules: [], opts: []]

  @typedoc "Formatter state accumulating test results during a test run"
  @type t :: %__MODULE__{
          seed: non_neg_integer() | nil,
          start_time: integer() | nil,
          tests: [map()],
          modules: [map()],
          opts: keyword()
        }

  # Client API

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl GenServer
  def init(opts) do
    config_opts = Config.get_opts()
    merged_opts = Keyword.merge(config_opts, opts)
    {:ok, %__MODULE__{opts: merged_opts, start_time: System.monotonic_time(:microsecond)}}
  end

  @impl GenServer
  def handle_cast({:suite_started, opts}, state) do
    seed = Keyword.get(opts, :seed)
    {:noreply, %{state | seed: seed}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    encoded_test = JSONEncoder.encode_test(test)
    {:noreply, %{state | tests: [encoded_test | state.tests]}}
  end

  def handle_cast({:module_finished, %ExUnit.TestModule{} = module}, state) do
    # Only track modules that have setup_all failures (state is not nil)
    case module.state do
      {:failed, _failures} ->
        encoded_module = encode_module_failure(module)
        {:noreply, %{state | modules: [encoded_module | state.modules]}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:suite_finished, _times_us}, state) do
    # TODO: Task 5 - Output JSON document
    {:noreply, state}
  end

  # Silently ignore ExUnit events we don't need
  # (e.g., :test_started, :case_started, :case_finished, :sigquit)
  def handle_cast(_event, state) do
    {:noreply, state}
  end

  # For testing: allow synchronous state retrieval
  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @doc false
  # Cleanup callback for future file handle management (Task 8)
  @impl GenServer
  def terminate(_reason, _state) do
    # TODO: Close file handle if output is to file (Task 8)
    :ok
  end

  # Private helpers

  @doc false
  # Encodes a module failure (from setup_all) to a JSON-safe map
  defp encode_module_failure(%ExUnit.TestModule{} = module) do
    %{
      name: inspect(module.name),
      file: module.file,
      state: "failed",
      failures: JSONEncoder.encode_failure(module.state)
    }
  end
end
