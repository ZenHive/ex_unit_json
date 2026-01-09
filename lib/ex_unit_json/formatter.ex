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
    * `{:suite_finished, times_us}` - Outputs final JSON

  """

  use GenServer

  alias ExUnitJSON.CompactOutput
  alias ExUnitJSON.Config
  alias ExUnitJSON.ErrorGroups
  alias ExUnitJSON.Filters
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
    tests = state.tests |> Enum.reverse() |> sort_tests()
    summary = build_summary(tests, times_us)

    output =
      if Config.compact?() do
        filtered_tests = Filters.filter_tests(tests, state.opts)
        CompactOutput.build_compact_output(filtered_tests, summary, state.opts)
      else
        document = build_document(state, tests, summary)
        :json.encode(document)
      end

    write_output(output, Config.output_path())

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
  # OTP callback for process termination. Currently a no-op since:
  # - File writes happen synchronously in suite_finished (already complete)
  # - No external resources (ports, sockets) need cleanup
  # Kept for OTP compliance and future extensibility (e.g., flushing buffers).
  @impl GenServer
  def terminate(_reason, _state) do
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
  # Writes output to stdout or file. Handles file write errors gracefully
  # with a clear error message rather than crashing the GenServer.
  @spec write_output(iodata(), String.t() | nil) :: :ok
  defp write_output(output, nil) do
    IO.write(output)
  end

  defp write_output(output, path) when is_binary(path) do
    case File.write(path, output) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, """
        Error: Failed to write JSON output to #{path}
        Reason: #{:file.format_error(reason)}
        """)

        :ok
    end
  end

  @doc false
  # Builds the complete JSON document from accumulated state.
  @spec build_document(t(), [map()], map()) :: map()
  defp build_document(state, tests, summary) do
    # Call filter_tests once and pass result to both maybe_add_* functions
    filtered_tests = Filters.filter_tests(tests, state.opts)

    %{
      version: 1,
      seed: state.seed,
      summary: summary
    }
    |> maybe_add_tests(filtered_tests, state.opts)
    |> maybe_add_error_groups(tests, filtered_tests, state.opts)
    |> maybe_add_module_failures(state.modules)
  end

  @doc false
  # Adds filtered tests array to document unless summary_only mode is enabled.
  # Accepts pre-filtered tests (nil means summary_only mode).
  @spec maybe_add_tests(map(), [map()] | nil, keyword()) :: map()
  defp maybe_add_tests(doc, nil, _opts), do: doc

  defp maybe_add_tests(doc, filtered_tests, opts) do
    patterns = Keyword.get(opts, :filter_out, [])
    marked = Filters.apply_filter_out(filtered_tests, patterns)
    Map.put(doc, :tests, marked)
  end

  @doc false
  # Adds error_groups to document when group_by_error is enabled and failures exist.
  # Uses pre-filtered tests to avoid calling filter_tests twice.
  @spec maybe_add_error_groups(map(), [map()], [map()] | nil, keyword()) :: map()
  defp maybe_add_error_groups(doc, all_tests, filtered_tests, opts) do
    if Keyword.get(opts, :group_by_error, false) do
      # Use filtered tests if available, otherwise all tests (for summary_only mode)
      tests_for_grouping = filtered_tests || all_tests

      failed_tests = Enum.filter(tests_for_grouping, &(&1.state == "failed"))
      groups = ErrorGroups.build_error_groups(failed_tests)

      if groups == [], do: doc, else: Map.put(doc, :error_groups, groups)
    else
      doc
    end
  end

  @doc false
  # Adds module_failures to document when setup_all failures occurred.
  @spec maybe_add_module_failures(map(), [map()]) :: map()
  defp maybe_add_module_failures(doc, []), do: doc
  defp maybe_add_module_failures(doc, modules), do: Map.put(doc, :module_failures, Enum.reverse(modules))

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
  # Handles both old ExUnit format (%{async, sync}) and new format (%{async, run, load}).
  @spec build_summary([map()], map()) :: map()
  defp build_summary(tests, times_us) do
    counts =
      Enum.reduce(tests, %{passed: 0, failed: 0, skipped: 0, excluded: 0, invalid: 0}, fn test, acc ->
        increment_state_count(acc, test.state)
      end)

    duration_us = extract_duration(times_us)

    %{
      total: length(tests),
      passed: counts.passed,
      failed: counts.failed,
      skipped: counts.skipped,
      excluded: counts.excluded,
      invalid: counts.invalid,
      duration_us: duration_us,
      result: if(counts.failed > 0 or counts.invalid > 0, do: "failed", else: "passed")
    }
  end

  @doc false
  # Extracts total duration from ExUnit times_us map.
  # Handles both old format (%{async, sync}) and new format (%{async, run, load}).
  # Guards ensure we only perform arithmetic on integers, falling back to 0 otherwise.
  @spec extract_duration(map()) :: non_neg_integer()
  defp extract_duration(%{run: run}) when is_integer(run), do: run

  defp extract_duration(%{async: async, sync: sync}) when is_integer(async) and is_integer(sync), do: async + sync

  defp extract_duration(%{async: async}) when is_integer(async), do: async
  defp extract_duration(_), do: 0

  @doc false
  # Sorts tests deterministically by file, line, name
  @spec sort_tests([map()]) :: [map()]
  defp sort_tests(tests) do
    Enum.sort_by(tests, fn t -> {t.file, t.line, t.name} end)
  end
end
