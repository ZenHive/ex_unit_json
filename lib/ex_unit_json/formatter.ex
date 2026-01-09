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

  def handle_cast({:suite_finished, times_us}, state) do
    document = build_document(state, times_us)
    json = :json.encode(document)

    case Config.output_path() do
      nil -> IO.write(json)
      path -> File.write!(path, json)
    end

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
  @spec encode_module_failure(ExUnit.TestModule.t()) :: map()
  defp encode_module_failure(%ExUnit.TestModule{} = module) do
    %{
      name: inspect(module.name),
      file: module.file,
      state: "failed",
      failures: JSONEncoder.encode_failure(module.state)
    }
  end

  @doc false
  # Builds the complete JSON document from accumulated state
  @spec build_document(t(), %{async: non_neg_integer(), sync: non_neg_integer()}) :: map()
  defp build_document(state, times_us) do
    tests = state.tests |> Enum.reverse() |> sort_tests()

    doc = %{
      version: 1,
      seed: state.seed,
      summary: build_summary(tests, times_us)
    }

    # Add tests unless summary_only
    doc =
      case filter_tests(tests, state.opts) do
        nil -> doc
        filtered -> Map.put(doc, :tests, filtered)
      end

    # Add module failures if any
    if state.modules == [] do
      doc
    else
      Map.put(doc, :module_failures, Enum.reverse(state.modules))
    end
  end

  @doc false
  # Increments the count for a test state using explicit pattern matching.
  # Safer than String.to_existing_atom/1 - won't crash on unexpected input.
  @spec increment_state_count(map(), String.t()) :: map()
  defp increment_state_count(acc, "passed"), do: Map.update!(acc, :passed, &(&1 + 1))
  defp increment_state_count(acc, "failed"), do: Map.update!(acc, :failed, &(&1 + 1))
  defp increment_state_count(acc, "skipped"), do: Map.update!(acc, :skipped, &(&1 + 1))
  defp increment_state_count(acc, "excluded"), do: Map.update!(acc, :excluded, &(&1 + 1))
  defp increment_state_count(acc, "invalid"), do: Map.update!(acc, :invalid, &(&1 + 1))

  @doc false
  # Builds summary statistics from all tests.
  @spec build_summary([map()], %{async: non_neg_integer(), sync: non_neg_integer()}) :: map()
  defp build_summary(tests, times_us) do
    counts =
      Enum.reduce(tests, %{passed: 0, failed: 0, skipped: 0, excluded: 0, invalid: 0}, fn test, acc ->
        increment_state_count(acc, test.state)
      end)

    %{
      total: length(tests),
      passed: counts.passed,
      failed: counts.failed,
      skipped: counts.skipped,
      excluded: counts.excluded,
      invalid: counts.invalid,
      duration_us: times_us.async + times_us.sync,
      result: if(counts.failed > 0 or counts.invalid > 0, do: "failed", else: "passed")
    }
  end

  @doc false
  # Sorts tests deterministically by file, line, name
  @spec sort_tests([map()]) :: [map()]
  defp sort_tests(tests) do
    Enum.sort_by(tests, fn t -> {t.file, t.line, t.name} end)
  end

  @doc false
  # Filters tests based on configuration options.
  # Returns nil for summary_only (omit tests array), filtered list, or all tests.
  @spec filter_tests([map()], keyword()) :: [map()] | nil
  defp filter_tests(tests, opts) do
    cond do
      Keyword.get(opts, :summary_only, false) -> nil
      Keyword.get(opts, :failures_only, false) -> Enum.filter(tests, &(&1.state == "failed"))
      true -> tests
    end
  end
end
