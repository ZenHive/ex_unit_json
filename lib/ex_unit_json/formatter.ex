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
    output =
      if Config.compact?() do
        build_compact_output(state, times_us)
      else
        document = build_document(state, times_us)
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
  # Accepts any ExUnit times_us map format (old or new).
  @spec build_document(t(), map()) :: map()
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
        nil ->
          doc

        filtered ->
          patterns = Keyword.get(state.opts, :filter_out, [])
          marked = apply_filter_out(filtered, patterns)
          Map.put(doc, :tests, marked)
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

  @doc false
  # Filters tests based on configuration options.
  # Returns nil for summary_only (omit tests array), filtered list, or all tests.
  # Priority: summary_only > first_failure > failures_only > all
  @spec filter_tests([map()], keyword()) :: [map()] | nil
  defp filter_tests(tests, opts) do
    cond do
      Keyword.get(opts, :summary_only, false) ->
        nil

      Keyword.get(opts, :first_failure, false) ->
        tests
        |> Enum.filter(&(&1.state == "failed"))
        |> Enum.take(1)

      Keyword.get(opts, :failures_only, false) ->
        Enum.filter(tests, &(&1.state == "failed"))

      true ->
        tests
    end
  end

  @doc false
  # Marks failed tests as filtered if their failure message matches any pattern.
  # Returns tests unchanged if no patterns provided.
  @spec apply_filter_out([map()], [String.t()]) :: [map()]
  defp apply_filter_out(tests, []), do: tests

  defp apply_filter_out(tests, patterns) do
    Enum.map(tests, fn test ->
      if test.state == "failed" and failure_matches_pattern?(test, patterns) do
        Map.put(test, :filtered, true)
      else
        test
      end
    end)
  end

  @doc false
  # Checks if any failure message in the test matches any of the patterns.
  @spec failure_matches_pattern?(map(), [String.t()]) :: boolean()
  defp failure_matches_pattern?(%{failures: failures}, patterns) when is_list(failures) do
    Enum.any?(failures, fn failure ->
      message = Map.get(failure, :message, "")
      Enum.any?(patterns, fn pattern -> String.contains?(message, pattern) end)
    end)
  end

  defp failure_matches_pattern?(_, _), do: false

  @doc false
  # Builds compact JSONL output - one JSON object per line, minimal fields.
  # Format: {"f":"file:line","n":"name","s":"state","e":"error..."} per test
  # Last line is summary: {"summary":{...}}
  @spec build_compact_output(t(), map()) :: iodata()
  defp build_compact_output(state, times_us) do
    tests = state.tests |> Enum.reverse() |> sort_tests()
    filtered = filter_tests(tests, state.opts)
    patterns = Keyword.get(state.opts, :filter_out, [])

    test_lines =
      case filtered do
        nil ->
          []

        test_list ->
          test_list
          |> apply_filter_out(patterns)
          |> Enum.map(&compact_test_line/1)
      end

    summary = build_summary(tests, times_us)
    summary_line = :json.encode(%{summary: summary})

    # Join with newlines, add trailing newline
    Enum.join(test_lines ++ [summary_line], "\n") <> "\n"
  end

  @doc false
  # Encodes a single test as a compact JSON object.
  # Keys: f=file:line, n=name, s=state, e=error (first line, only if failed), x=filtered
  defp compact_test_line(test) do
    base = %{
      "f" => "#{test.file}:#{test.line}",
      "n" => test.name,
      "s" => test.state
    }

    # Add error message (first line only) for failed tests
    compact =
      if test.state == "failed" and test.failures != [] do
        error_msg =
          test.failures
          |> List.first()
          |> Map.get(:message, "")
          |> String.trim()
          |> String.split("\n", parts: 2)
          |> List.first()
          |> String.trim()

        Map.put(base, "e", error_msg)
      else
        base
      end

    # Add filtered flag if present
    compact =
      if Map.get(test, :filtered, false) do
        Map.put(compact, "x", true)
      else
        compact
      end

    :json.encode(compact)
  end
end
