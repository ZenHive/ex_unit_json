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
  """

  use GenServer

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
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{opts: opts}}
  end

  @impl true
  def handle_cast({:suite_started, _opts}, state) do
    # TODO: Capture seed and start time
    {:noreply, state}
  end

  def handle_cast({:test_finished, _test}, state) do
    # TODO: Accumulate test results
    {:noreply, state}
  end

  def handle_cast({:suite_finished, _times_us}, state) do
    # TODO: Output JSON
    {:noreply, state}
  end

  # Silently ignore ExUnit events we don't need (e.g., :test_started, :case_started)
  def handle_cast(_event, state) do
    {:noreply, state}
  end
end
