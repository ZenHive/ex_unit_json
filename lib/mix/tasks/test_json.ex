defmodule Mix.Tasks.Test.Json do
  @shortdoc "Run tests with JSON output"

  @moduledoc """
  Runs tests and outputs results as JSON.

  This task wraps `mix test` and configures ExUnit to use
  `ExUnitJSON.Formatter` for JSON output instead of the default
  CLI formatter.

  ## Setup

  Add this to your project's `mix.exs` to ensure `test.json` runs in the test environment:

      def cli do
        [preferred_envs: ["test.json": :test]]
      end

  This is required because Mix doesn't inherit `preferred_envs` from dependencies.

  ## Usage

      mix test.json
      mix test.json test/my_test.exs
      mix test.json test/my_test.exs:42

  ## Options

  All standard `mix test` options are supported, plus:

    * `--summary-only` - Output only the summary, omit individual test results
    * `--all` - Output all tests (default shows only failures)
    * `--failures-only` - Output only failed tests (DEFAULT - AI-optimized)
    * `--first-failure` - Output only the first failed test (quick iteration)
    * `--filter-out PATTERN` - Mark failures matching pattern as filtered (can repeat)
    * `--output FILE` - Write JSON to file instead of stdout
    * `--compact` - JSONL output with minimal fields (one line per test)
    * `--group-by-error` - Group failures by similar error message
    * `--quiet` - Suppress Logger output and TIP warnings for clean JSON piping
    * `--no-warn` - Suppress the "use --failed" warning when previous failures exist
    * `--cover` - Enable code coverage (off by default for faster runs)
    * `--cover-threshold N` - Fail if overall coverage is below N (0-100). Requires `--cover`

  ## Coverage

  Coverage is disabled by default for faster test runs. Use `--cover` to enable:

      mix test.json --cover

  The JSON output includes a `coverage` key with:

      "coverage": {
        "total_percentage": 96.96,
        "total_lines": 330,
        "covered_lines": 320,
        "threshold": 80,
        "threshold_met": true,
        "modules": [
          {
            "module": "MyApp.Module",
            "file": "lib/my_app/module.ex",
            "percentage": 92.68,
            "covered_lines": 38,
            "uncovered_lines": [45, 67, 89]
          }
        ]
      }

  ## Default Behavior (v0.3.0+)

  By default, `mix test.json` outputs only failed tests (equivalent to `--failures-only`).
  This is optimized for AI agents where passing tests are noise.

  Use `--all` to include all tests in output when needed.

  ## Flag Precedence

  When multiple filtering flags are combined, they follow this priority:

    1. `--summary-only` - Highest priority, omits tests array entirely
    2. `--first-failure` - Returns only the first failed test
    3. `--failures-only` / `--all` - Filter to failures or show all tests

  For example, `--summary-only --all` will omit the tests array.

  ## Iteration Workflow

  When previous test failures exist, a tip is shown suggesting
  to use `--failed` for faster iteration:

      TIP: 3 previous failure(s) exist. Consider:
        mix test.json --failed

  This warning is skipped when:
    * `--failed` is already used
    * A specific file or directory is targeted
    * `--only` or `--exclude` tag filters are used
    * `--no-warn` flag is passed

  ## Strict Enforcement

  To block full test runs when failures exist (useful for AI-assisted workflows):

      # config/test.exs
      config :ex_unit_json, enforce_failed: true

  This will exit with an error instead of just warning.

  ## Examples

      # Run all tests with JSON output
      mix test.json

      # Run specific file
      mix test.json test/my_test.exs

      # Output only failures to a file
      mix test.json --failures-only --output failures.json

  """

  use Mix.Task

  require Logger

  @cover_threshold_min 0.0
  @cover_threshold_max 100.0
  @cover_threshold_exit_code 2

  @impl Mix.Task
  def run(args) do
    ensure_test_env!()

    # Extract only our options, pass everything else to mix test unchanged
    {opts, test_args} = extract_json_opts(args)
    opts = normalize_cover_threshold!(opts)

    # Setup quiet mode if requested
    maybe_enable_quiet_mode(opts)

    # Coverage is OFF by default, enable with --cover
    cover_enabled? = Keyword.get(opts, :cover, false)

    # Ensure project is compiled before coverage instrumentation.
    # On clean builds, compile_project_modules() would otherwise find no beam files
    # because Mix.Task.run("test", ...) triggers compilation AFTER coverage starts.
    if cover_enabled?, do: Mix.Task.run("compile", ["--no-warnings-as-errors"])

    test_args = maybe_start_coverage(test_args, cover_enabled?)

    # When coverage is enabled or --quiet is used, we need to buffer output to a temp file
    # so we can merge coverage data into the JSON before final output
    {opts, temp_output_path} = maybe_use_temp_output_for_coverage(opts, cover_enabled?)

    # Check if user should use --failed (warn by default, block if configured)
    handle_failed_usage_check(opts, test_args)

    # Compute hint for JSON output (suggests --failed when appropriate)
    opts = maybe_add_hint_opt(opts, test_args)

    # In umbrella projects, each app runs its own ExUnit suite, each triggering
    # suite_finished which writes to the output file. Clear the file at the start
    # so the formatter can detect and merge results from earlier apps in this run.
    maybe_clear_output_file(opts)

    # Options passed via Application env because ExUnit formatter API
    # doesn't support passing options directly to formatters.
    # This is acceptable as test runs are single-instance.
    Application.put_env(:ex_unit_json, :opts, opts)

    # Use --formatter flag instead of ExUnit.configure to avoid race conditions
    # with test_helper.exs and stale compilation issues. This is more robust
    # as it uses mix test's native formatter handling.
    Mix.Task.run("test", ["--formatter", "ExUnitJSON.Formatter" | test_args])

    # Handle coverage and output based on configuration
    cond do
      # Coverage enabled with temp buffer (stdout output)
      cover_enabled? and temp_output_path ->
        merge_coverage_into_output(temp_output_path, opts)

      # Note: We don't call Coverage.stop() here because :cover.stop()
      # can kill processes that imported cover-compiled modules.
      # The cover server will be cleaned up when the process exits.

      # Coverage enabled with explicit --output file
      cover_enabled? and Keyword.has_key?(opts, :output) ->
        output_path = Keyword.get(opts, :output)
        merge_coverage_into_file(output_path, opts)

      # Same as above - skip stop() to avoid killing the process

      # Temp buffer without coverage (just output it)
      temp_output_path ->
        output_buffered_json(temp_output_path)

      # No temp buffer, no coverage - formatter already wrote output
      true ->
        :ok
    end
  end

  @doc false
  # Clears the output file at the start of a run so the formatter can distinguish
  # "file from an earlier app in this umbrella run" from "stale file from a previous run".
  @spec maybe_clear_output_file(keyword()) :: :ok
  defp maybe_clear_output_file(opts) do
    case Keyword.get(opts, :output) do
      nil -> :ok
      path -> File.rm(path); :ok
    end
  end

  @doc false
  # Extracts ex_unit_json-specific options, passes everything else through unchanged.
  # Uses pattern matching to avoid OptionParser mangling unknown switches like --only.
  defp extract_json_opts(args), do: extract_json_opts(args, [], [])

  defp extract_json_opts([], opts, remaining) do
    {merge_list_opts(Enum.reverse(opts)), Enum.reverse(remaining)}
  end

  defp extract_json_opts(["--summary-only" | rest], opts, remaining) do
    extract_json_opts(rest, [{:summary_only, true} | opts], remaining)
  end

  defp extract_json_opts(["--failures-only" | rest], opts, remaining) do
    extract_json_opts(rest, [{:failures_only, true} | opts], remaining)
  end

  defp extract_json_opts(["--all" | rest], opts, remaining) do
    extract_json_opts(rest, [{:failures_only, false} | opts], remaining)
  end

  defp extract_json_opts(["--first-failure" | rest], opts, remaining) do
    extract_json_opts(rest, [{:first_failure, true} | opts], remaining)
  end

  defp extract_json_opts(["--output", value | rest], opts, remaining) do
    extract_json_opts(rest, [{:output, value} | opts], remaining)
  end

  defp extract_json_opts(["--compact" | rest], opts, remaining) do
    extract_json_opts(rest, [{:compact, true} | opts], remaining)
  end

  defp extract_json_opts(["--filter-out", value | rest], opts, remaining) do
    extract_json_opts(rest, [{:filter_out, value} | opts], remaining)
  end

  defp extract_json_opts(["--group-by-error" | rest], opts, remaining) do
    extract_json_opts(rest, [{:group_by_error, true} | opts], remaining)
  end

  defp extract_json_opts(["--quiet" | rest], opts, remaining) do
    extract_json_opts(rest, [{:quiet, true} | opts], remaining)
  end

  defp extract_json_opts(["--no-warn" | rest], opts, remaining) do
    extract_json_opts(rest, [{:no_warn, true} | opts], remaining)
  end

  defp extract_json_opts(["--cover" | rest], opts, remaining) do
    extract_json_opts(rest, [{:cover, true} | opts], remaining)
  end

  defp extract_json_opts(["--cover-threshold", value | rest], opts, remaining) do
    extract_json_opts(rest, [{:cover_threshold, value} | opts], remaining)
  end

  defp extract_json_opts([arg | rest], opts, remaining) do
    extract_json_opts(rest, opts, [arg | remaining])
  end

  @doc false
  # Merges repeated options (like --filter-out) into a single list value.
  # E.g., [{:filter_out, "a"}, {:filter_out, "b"}] -> [{:filter_out, ["a", "b"]}]
  defp merge_list_opts(opts) do
    filters = Keyword.get_values(opts, :filter_out)
    rest = Keyword.delete(opts, :filter_out)

    if filters == [] do
      rest
    else
      [{:filter_out, filters} | rest]
    end
  end

  @doc false
  # Enables quiet mode: suppresses Mix shell and Logger output for clean JSON
  @spec maybe_enable_quiet_mode(keyword()) :: :ok
  defp maybe_enable_quiet_mode(opts) do
    if Keyword.get(opts, :quiet, false) do
      Mix.shell(Mix.Shell.Quiet)
      :logger.remove_handler(:default)
      Application.put_env(:logger, :level, :error)
    end

    :ok
  end

  @doc false
  # Starts coverage instrumentation and excludes conflicting tests
  @spec maybe_start_coverage([String.t()], boolean()) :: [String.t()]
  defp maybe_start_coverage(test_args, true = _cover_enabled?) do
    ExUnitJSON.Coverage.start()
    ["--exclude", "coverage_unit" | test_args]
  end

  defp maybe_start_coverage(test_args, false = _cover_enabled?), do: test_args

  @doc false
  # Checks failed usage and shows warning/error as appropriate
  @spec handle_failed_usage_check(keyword(), [String.t()]) :: :ok
  defp handle_failed_usage_check(opts, test_args) do
    quiet? = Keyword.get(opts, :quiet, false)

    case check_failed_usage(opts, test_args) do
      {:error, :blocked, count} ->
        other_args = Enum.join(test_args, " ")

        IO.puts(:stderr, """
        ERROR: Previous test run had #{count} failure(s).

        Re-run only failed tests:
          mix test.json --failed #{other_args}

        Or scope to a directory/tag:
          mix test.json test/unit/ --failed
          mix test.json --only integration --failed

        Disable enforcement in config/test.exs:
          config :ex_unit_json, enforce_failed: false
        """)

        exit({:shutdown, 1})

      {:warn, count} when not quiet? ->
        other_args = Enum.join(test_args, " ")

        IO.puts(:stderr, """
        TIP: #{count} previous failure(s) exist. Consider:
          mix test.json --failed #{other_args}
          mix test.json test/unit/ --failed
          mix test.json --only integration --failed
        (Use --no-warn to suppress this message)
        """)

      _ ->
        :ok
    end
  end

  @doc false
  # Ensures we're running in :test environment. Library's preferred_envs config
  # doesn't propagate to consuming projects, so we detect and error early.
  defp ensure_test_env! do
    if Mix.env() != :test do
      Mix.raise("""
      "mix test.json" must run in the test environment.

      You're currently running in the "#{Mix.env()}" environment.

      Add this to your mix.exs:

          def cli do
            [preferred_envs: ["test.json": :test]]
          end

      Or run with: MIX_ENV=test mix test.json
      """)
    end
  end

  @doc false
  # Returns path to ExUnit's failures file, matching where mix test writes it.
  # Path format: _build/#{env}/lib/#{app}/.mix/.mix_test_failures
  @spec failures_file() :: String.t()
  defp failures_file do
    case Mix.Project.config()[:app] do
      nil -> ".mix_test_failures"
      app -> Path.join(["_build", to_string(Mix.env()), "lib", to_string(app), ".mix", ".mix_test_failures"])
    end
  end

  @doc false
  # Adds :hint to opts when --failed would speed up iteration.
  # Returns opts unchanged when: --failed already used, specific file targeted, or no previous failures.
  @spec maybe_add_hint_opt(keyword(), [String.t()]) :: keyword()
  defp maybe_add_hint_opt(opts, test_args) do
    failures_path = failures_file()
    has_failed_flag = "--failed" in test_args
    has_specific_target = Enum.any?(test_args, &test_path?/1)

    cond do
      has_failed_flag ->
        opts

      has_specific_target ->
        opts

      not File.exists?(failures_path) ->
        opts

      true ->
        count = count_previous_failures(failures_path)
        hint = "#{count} test(s) failed previously. Use --failed to re-run only those."
        Keyword.put(opts, :hint, hint)
    end
  end

  @doc false
  # Checks if arg looks like a test file path (e.g., "test/foo.exs" or "test/foo.exs:42")
  @spec test_path?(String.t()) :: boolean()
  defp test_path?(arg) do
    String.ends_with?(arg, ".exs") or String.contains?(arg, ".exs:")
  end

  @doc false
  # Counts number of test identifiers in .mix_test_failures file.
  # File is Erlang term format (list of test identifiers), not text.
  @spec count_previous_failures(String.t()) :: non_neg_integer()
  defp count_previous_failures(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} when byte_size(content) > 0 ->
          try do
            case :erlang.binary_to_term(content) do
              # New format (Elixir 1.17+): {version, %{test_id => state}}
              {_version, failures_map} when is_map(failures_map) ->
                map_size(failures_map)

              # Old format: list of test identifiers
              failures when is_list(failures) ->
                length(failures)

              _ ->
                0
            end
          rescue
            # Malformed file - silently return 0
            _ -> 0
          end

        _ ->
          0
      end
    else
      0
    end
  end

  @doc false
  # User is being intentional about scope - no need to warn
  @spec focused_run?([String.t()]) :: boolean()
  defp focused_run?(test_args) do
    Enum.any?(test_args, fn arg ->
      String.ends_with?(arg, ".exs") or
        String.contains?(arg, ".exs:") or
        File.dir?(arg) or
        String.starts_with?(arg, "--only") or
        String.starts_with?(arg, "--exclude")
    end)
  end

  @doc false
  # Checks if user should be warned/blocked about not using --failed.
  # Returns :ok, {:warn, count}, or {:error, :blocked, count}
  @spec check_failed_usage(keyword(), [String.t()]) :: :ok | {:warn, pos_integer()} | {:error, :blocked, pos_integer()}
  defp check_failed_usage(opts, test_args) do
    failures_path = failures_file()

    with true <- File.exists?(failures_path),
         count when count > 0 <- count_previous_failures(failures_path),
         false <- "--failed" in test_args,
         false <- focused_run?(test_args),
         false <- Keyword.get(opts, :no_warn, false) do
      if Application.get_env(:ex_unit_json, :enforce_failed, false) do
        {:error, :blocked, count}
      else
        {:warn, count}
      end
    else
      _ -> :ok
    end
  end

  @doc false
  # When coverage is enabled or --quiet is used, buffer output to temp file.
  # This allows merging coverage data into JSON before final output.
  @spec maybe_use_temp_output_for_coverage(keyword(), boolean()) :: {keyword(), String.t() | nil}
  defp maybe_use_temp_output_for_coverage(opts, cover_enabled?) do
    quiet? = Keyword.get(opts, :quiet, false)
    has_output? = Keyword.has_key?(opts, :output)

    # Buffer to temp file when:
    # 1. Coverage is enabled (need to merge coverage data)
    # 2. --quiet is used without explicit --output (avoid stdout pollution)
    needs_temp_buffer? = (cover_enabled? and not has_output?) or (quiet? and not has_output?)

    if needs_temp_buffer? do
      temp_path = Path.join(System.tmp_dir!(), "ex_unit_json_#{System.unique_integer([:positive])}.json")
      {Keyword.put(opts, :output, temp_path), temp_path}
    else
      {opts, nil}
    end
  end

  @doc false
  # Outputs buffered JSON from temp file and cleans up.
  @spec output_buffered_json(String.t()) :: :ok
  defp output_buffered_json(path) do
    case File.read(path) do
      {:ok, content} ->
        IO.write(content)
        File.rm(path)
        :ok

      {:error, _} ->
        # File might not exist if tests crashed early
        :ok
    end
  end

  @doc false
  # Merges coverage data into the JSON output and writes to final destination.
  @spec merge_coverage_into_output(String.t(), keyword()) :: :ok
  defp merge_coverage_into_output(temp_path, opts) do
    # Coverage cannot be merged into compact JSONL output.
    # Compact mode outputs one JSON object per line, but coverage needs to be
    # merged into the summary object which requires parsing the full document.
    if Keyword.get(opts, :compact, false) do
      IO.puts(:stderr, "Warning: --cover with --compact is not supported. Coverage data omitted.")
      output_buffered_json(temp_path)
      maybe_enforce_cover_threshold(opts)
      return_ok()
    else
      merge_coverage_into_json(temp_path, opts)
    end
  end

  @doc false
  # Helper to return :ok (extracted for coverage of compact mode branch)
  @spec return_ok() :: :ok
  defp return_ok, do: :ok

  @doc false
  # Actually merges coverage into JSON output (non-compact mode)
  @spec merge_coverage_into_json(String.t(), keyword()) :: :ok
  defp merge_coverage_into_json(temp_path, opts) do
    {coverage, threshold_met?} = collect_coverage_with_threshold(opts)

    case File.read(temp_path) do
      {:ok, content} ->
        document = :json.decode(content)
        merged = Map.put(document, "coverage", coverage)
        encoded = :json.encode(merged)

        case Keyword.get(opts, :output) do
          # Output was set to temp_path, write to stdout
          ^temp_path ->
            IO.write(encoded)

          # User specified explicit output path
          user_path when is_binary(user_path) ->
            File.write!(user_path, encoded)

          # No output specified (shouldn't happen with coverage, but handle it)
          nil ->
            IO.write(encoded)
        end

        File.rm(temp_path)
        maybe_exit_on_cover_threshold(threshold_met?, coverage)
        :ok

      {:error, _} ->
        # File might not exist if tests crashed early
        :ok
    end
  end

  @doc false
  # Merges coverage data into an existing output file.
  # Used when user specifies --output and coverage is enabled.
  @spec merge_coverage_into_file(String.t(), keyword()) :: :ok
  defp merge_coverage_into_file(path, opts) do
    # Coverage cannot be merged into compact JSONL output.
    if Keyword.get(opts, :compact, false) do
      IO.puts(:stderr, "Warning: --cover with --compact is not supported. Coverage data omitted.")
      maybe_enforce_cover_threshold(opts)
      return_ok()
    else
      merge_coverage_into_file_json(path, opts)
    end
  end

  @doc false
  # Actually merges coverage into file (non-compact mode)
  @spec merge_coverage_into_file_json(String.t(), keyword()) :: :ok
  defp merge_coverage_into_file_json(path, opts) do
    {coverage, threshold_met?} = collect_coverage_with_threshold(opts)

    case File.read(path) do
      {:ok, content} ->
        document = :json.decode(content)
        merged = Map.put(document, "coverage", coverage)
        encoded = :json.encode(merged)
        File.write!(path, encoded)
        maybe_exit_on_cover_threshold(threshold_met?, coverage)
        :ok

      {:error, _} ->
        # File might not exist if tests crashed early
        :ok
    end
  end

  @doc false
  # Gets list of modules to ignore from mix.exs test_coverage config.
  @spec get_coverage_ignore_modules() :: [module()]
  defp get_coverage_ignore_modules do
    case Mix.Project.config()[:test_coverage] do
      nil -> []
      config -> Keyword.get(config, :ignore_modules, [])
    end
  end

  @doc false
  @spec normalize_cover_threshold!(keyword()) :: keyword()
  defp normalize_cover_threshold!(opts) do
    case Keyword.fetch(opts, :cover_threshold) do
      :error ->
        opts

      {:ok, value} ->
        if !Keyword.get(opts, :cover, false) do
          Mix.raise("--cover-threshold requires --cover")
        end

        threshold = parse_cover_threshold!(value)
        Keyword.put(opts, :cover_threshold, threshold)
    end
  end

  @doc false
  @spec parse_cover_threshold!(String.t() | number()) :: number()
  defp parse_cover_threshold!(value) when is_number(value) do
    validate_cover_threshold!(value)
  end

  defp parse_cover_threshold!(value) when is_binary(value) do
    case Float.parse(value) do
      {threshold, ""} ->
        validate_cover_threshold!(threshold)

      _ ->
        Mix.raise("--cover-threshold must be a number between #{@cover_threshold_min} and #{@cover_threshold_max}")
    end
  end

  @doc false
  @spec validate_cover_threshold!(number()) :: number()
  defp validate_cover_threshold!(threshold) do
    if threshold < @cover_threshold_min or threshold > @cover_threshold_max do
      Mix.raise("--cover-threshold must be between #{@cover_threshold_min} and #{@cover_threshold_max}")
    end

    threshold
  end

  @doc false
  @spec collect_coverage_with_threshold(keyword()) :: {map(), boolean() | nil}
  defp collect_coverage_with_threshold(opts) do
    ignore_modules = get_coverage_ignore_modules()
    coverage = ExUnitJSON.Coverage.collect(ignore_modules)

    case Keyword.fetch(opts, :cover_threshold) do
      :error ->
        {coverage, nil}

      {:ok, threshold} ->
        threshold_met? = coverage["total_percentage"] >= threshold
        updated = Map.merge(coverage, %{"threshold" => threshold, "threshold_met" => threshold_met?})
        {updated, threshold_met?}
    end
  end

  @doc false
  @spec maybe_enforce_cover_threshold(keyword()) :: :ok
  defp maybe_enforce_cover_threshold(opts) do
    if Keyword.has_key?(opts, :cover_threshold) do
      {coverage, threshold_met?} = collect_coverage_with_threshold(opts)
      maybe_exit_on_cover_threshold(threshold_met?, coverage)
    end

    :ok
  end

  @doc false
  @spec maybe_exit_on_cover_threshold(boolean() | nil, map()) :: :ok
  defp maybe_exit_on_cover_threshold(nil, _coverage), do: :ok
  defp maybe_exit_on_cover_threshold(true, _coverage), do: :ok

  defp maybe_exit_on_cover_threshold(false, coverage) do
    total = coverage["total_percentage"]
    threshold = coverage["threshold"]

    IO.puts(:stderr, "ERROR: Coverage #{total}% is below threshold #{threshold}%")
    exit({:shutdown, @cover_threshold_exit_code})
  end
end
