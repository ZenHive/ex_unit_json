defmodule ExUnitJSON.Formatter do
  @moduledoc """
  ExUnit formatter that outputs test results as JSON.

  This GenServer receives events from ExUnit during test execution
  and accumulates results. When the test suite finishes, it outputs
  a JSON document with the accumulated test results and summary statistics
  (failures only by default; all tests with `--all`).

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

    # Apply --quiet Logger suppression here (after app config loads)
    # to ensure it takes effect after config/test.exs is evaluated.
    #
    # The Mix task sets Application.put_env(:logger, :level, :error) to suppress
    # Logger output from test_helper.exs. But that global level breaks capture_log
    # in tests. Now that test_helper.exs has run, we reset the global level to :debug
    # and set only the HANDLER level to :error. This way:
    # - Console output is suppressed (handler level :error)
    # - capture_log works (global level :debug allows messages to reach handlers)
    if Keyword.get(merged_opts, :quiet, false) do
      # Reset global level so capture_log works in tests
      Logger.configure(level: :debug)
      # Suppress console output via handler level
      :logger.set_handler_config(:default, :level, :error)
    end

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
    summary = build_summary(tests, times_us, state.opts)

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

  # sobelow_skip ["Traversal.FileModule"]
  # Safe: path comes from CLI --output flag, controlled by user running the command.
  # In umbrella projects, multiple apps write to the same file within one task run.
  # The task clears the file at the start, so any existing content is from an earlier
  # app in this run. Merge results instead of overwriting.
  defp write_output(output, path) when is_binary(path) do
    final_output =
      case File.read(path) do
        {:ok, existing} when byte_size(existing) > 0 ->
          merge_existing_output(existing, output)

        _ ->
          output
      end

    case File.write(path, final_output) do
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
  # Merges this app's output with an earlier umbrella app's output already in the
  # file. Compact (JSONL) output is line-oriented, so concatenation IS the merge;
  # decoding it as a single JSON document would crash.
  @spec merge_existing_output(binary(), iodata()) :: iodata()
  defp merge_existing_output(existing, output) do
    if Config.compact?() do
      [existing, output]
    else
      existing_doc = :json.decode(existing)
      new_doc = :json.decode(IO.iodata_to_binary(output))
      :json.encode(merge_documents(existing_doc, new_doc))
    end
  end

  @doc false
  # Merges two JSON result documents (from separate umbrella app runs).
  # Concatenates test arrays, sums summary counts, keeps latest seed and hint.
  @spec merge_documents(map(), map()) :: map()
  defp merge_documents(existing, new) do
    %{
      "version" => Map.get(new, "version", 1),
      "seed" => Map.get(new, "seed"),
      "summary" => merge_summaries(Map.get(existing, "summary", %{}), Map.get(new, "summary", %{}))
    }
    |> merge_tests(existing, new)
    |> merge_module_failures(existing, new)
    |> merge_error_groups(existing, new)
    |> merge_hint(existing, new)
  end

  @spec merge_tests(map(), map(), map()) :: map()
  defp merge_tests(doc, existing, new) do
    merged = Map.get(existing, "tests", []) ++ Map.get(new, "tests", [])

    # Each app's output is already filtered, so --first-failure would otherwise
    # yield one failure per app; the cap must hold across the merged document.
    merged = if Config.first_failure?(), do: Enum.take(merged, 1), else: merged

    case merged do
      [] -> doc
      tests -> Map.put(doc, "tests", tests)
    end
  end

  @spec merge_module_failures(map(), map(), map()) :: map()
  defp merge_module_failures(doc, existing, new) do
    case Map.get(existing, "module_failures", []) ++ Map.get(new, "module_failures", []) do
      [] -> doc
      mfs -> Map.put(doc, "module_failures", mfs)
    end
  end

  # Collapses groups with the same pattern: sums count, keeps first example.
  @spec merge_error_groups(map(), map(), map()) :: map()
  defp merge_error_groups(doc, existing, new) do
    case {Map.get(existing, "error_groups"), Map.get(new, "error_groups")} do
      {nil, nil} ->
        doc

      {existing_eg, new_eg} ->
        groups =
          (existing_eg || [])
          |> Kernel.++(new_eg || [])
          |> Enum.group_by(&Map.get(&1, "pattern"))
          |> Enum.map(fn {pattern, entries} ->
            %{
              "pattern" => pattern,
              "count" => entries |> Enum.map(&Map.get(&1, "count", 0)) |> Enum.sum(),
              "example" => entries |> hd() |> Map.get("example")
            }
          end)
          # Keep ErrorGroups.build_error_groups/1's documented count-desc ordering
          |> Enum.sort_by(&Map.get(&1, "count"), :desc)

        Map.put(doc, "error_groups", groups)
    end
  end

  @spec merge_hint(map(), map(), map()) :: map()
  defp merge_hint(doc, existing, new) do
    case Map.get(new, "hint") || Map.get(existing, "hint") do
      nil -> doc
      hint -> Map.put(doc, "hint", hint)
    end
  end

  @doc false
  # Sums numeric fields across two summary maps. Includes `filtered` when non-zero
  # to match the convention in `build_summary`.
  @spec merge_summaries(map(), map()) :: map()
  defp merge_summaries(a, b) do
    base = %{
      "total" => Map.get(a, "total", 0) + Map.get(b, "total", 0),
      "passed" => Map.get(a, "passed", 0) + Map.get(b, "passed", 0),
      "failed" => Map.get(a, "failed", 0) + Map.get(b, "failed", 0),
      "skipped" => Map.get(a, "skipped", 0) + Map.get(b, "skipped", 0),
      "excluded" => Map.get(a, "excluded", 0) + Map.get(b, "excluded", 0),
      "invalid" => Map.get(a, "invalid", 0) + Map.get(b, "invalid", 0),
      "duration_us" => Map.get(a, "duration_us", 0) + Map.get(b, "duration_us", 0),
      "result" => merge_result(Map.get(a, "result", "passed"), Map.get(b, "result", "passed"))
    }

    case Map.get(a, "filtered", 0) + Map.get(b, "filtered", 0) do
      0 -> base
      n -> Map.put(base, "filtered", n)
    end
  end

  @doc false
  # If either suite failed, the merged result is failed.
  @spec merge_result(String.t(), String.t()) :: String.t()
  defp merge_result("failed", _), do: "failed"
  defp merge_result(_, "failed"), do: "failed"
  defp merge_result(a, _), do: a

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
    |> maybe_add_hint(state.opts)
    |> maybe_add_tests(filtered_tests, state.opts)
    |> maybe_add_error_groups(tests, filtered_tests, state.opts)
    |> maybe_add_module_failures(state.modules)
  end

  @doc false
  # Adds hint field to document when present in opts (suggests --failed for faster iteration)
  @spec maybe_add_hint(map(), keyword()) :: map()
  defp maybe_add_hint(doc, opts) do
    case Keyword.get(opts, :hint) do
      nil -> doc
      hint -> Map.put(doc, :hint, hint)
    end
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
  # Excludes failures matching filter_out patterns from groups.
  @spec maybe_add_error_groups(map(), [map()], [map()] | nil, keyword()) :: map()
  defp maybe_add_error_groups(doc, all_tests, filtered_tests, opts) do
    if Keyword.get(opts, :group_by_error, false) do
      # Use filtered tests if available, otherwise all tests (for summary_only mode)
      tests_for_grouping = filtered_tests || all_tests

      # Exclude tests matching filter_out patterns from groups
      patterns = Keyword.get(opts, :filter_out, [])
      unfiltered_tests = Filters.reject_filtered_failures(tests_for_grouping, patterns)

      failed_tests = Enum.filter(unfiltered_tests, &(&1.state == "failed"))
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
  # Includes filtered count when filter_out patterns match failures.
  @spec build_summary([map()], map(), keyword()) :: map()
  defp build_summary(tests, times_us, opts) do
    counts =
      Enum.reduce(tests, %{passed: 0, failed: 0, skipped: 0, excluded: 0, invalid: 0}, fn test, acc ->
        increment_state_count(acc, test.state)
      end)

    duration_us = extract_duration(times_us)
    filter_patterns = Keyword.get(opts, :filter_out, [])
    filtered_count = Filters.count_filtered_failures(tests, filter_patterns)

    maybe_add_filtered_count(
      %{
        total: length(tests),
        passed: counts.passed,
        failed: counts.failed,
        skipped: counts.skipped,
        excluded: counts.excluded,
        invalid: counts.invalid,
        duration_us: duration_us,
        result: if(counts.failed > 0 or counts.invalid > 0, do: "failed", else: "passed")
      },
      filtered_count
    )
  end

  @doc false
  # Adds filtered count to summary only when non-zero (avoids noise in output).
  @spec maybe_add_filtered_count(map(), non_neg_integer()) :: map()
  defp maybe_add_filtered_count(summary, 0), do: summary
  defp maybe_add_filtered_count(summary, count), do: Map.put(summary, :filtered, count)

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
