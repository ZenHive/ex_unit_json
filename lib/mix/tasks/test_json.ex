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
    * `--no-retry` - Disable automatic retry of failed tests (see "Automatic Retry")
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

  ## Automatic Retry (v0.5.0+)

  By **default**, when a run has failures, `mix test.json` automatically re-runs
  only the previously-failed tests (ExUnit's native `--failed`) in a subprocess,
  then merges the two runs to distinguish:

    * **confirmed** failures — failed both runs. Stay in `tests`, stay red.
    * **flaky** failures — failed run 1, passed run 2. Surfaced in a top-level
      `flaky` array (never hidden) but no longer block the run.

  When every first-run failure heals on retry, the suite reports
  `summary.result == "passed"` and exits 0, so an AI agent isn't blocked by a
  flake — while the flaky tests are still named in the output. A test that fails
  both runs stays a hard failure (exit non-zero).

  The merged output adds (only when a retry ran): a `flaky` array, a
  `summary.flaky` count, and a `retry` metadata block. The schema `version`
  stays `1` (additive).

  Auto-retry is **skipped** (run-1 output is reported unchanged) when it would be
  meaningless or unsupported: `--no-retry`, `config :ex_unit_json, retry: false`,
  `--failed` (already iterating), `--summary-only`, `--first-failure`,
  `--compact`, `--group-by-error`, `--filter-out`, a `file:line` target, or an
  umbrella project.

  Disable it entirely:

      mix test.json --no-retry

      # or in config/test.exs
      config :ex_unit_json, retry: false

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

    # Decide auto-retry up front (drives temp buffering). Capture the user's
    # passthrough args before coverage injects its own --exclude, so the retry
    # subprocess re-runs with the same selection the user asked for.
    retry_enabled? = retry_enabled?(opts, test_args)
    passthrough_args = test_args

    # Ensure project is compiled before coverage instrumentation.
    # On clean builds, compile_project_modules() would otherwise find no beam files
    # because Mix.Task.run("test", ...) triggers compilation AFTER coverage starts.
    if cover_enabled?, do: Mix.Task.run("compile", ["--no-warnings-as-errors"])

    test_args = maybe_start_coverage(test_args, cover_enabled?)

    # Buffer output to a temp file when we must post-process before final output:
    # coverage merge, --quiet stdout hygiene, or auto-retry overlay.
    {opts, temp_output_path} = maybe_use_temp_output(opts, cover_enabled?, retry_enabled?)

    # Check if user should use --failed (warn by default, block if configured).
    # Auto-retry supersedes the manual hint, so the TIP is suppressed when on.
    handle_failed_usage_check(opts, test_args, retry_enabled?)

    # Compute hint for JSON output (suggests --failed when appropriate).
    # Skipped when auto-retry is handling re-runs to avoid double-signalling.
    opts = if retry_enabled?, do: opts, else: maybe_add_hint_opt(opts, test_args)

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

    post_run(opts, cover_enabled?, retry_enabled?, temp_output_path, passthrough_args)
  end

  @doc false
  # Dispatches to the retry overlay flow or the plain coverage/buffer flow.
  @spec post_run(keyword(), boolean(), boolean(), String.t() | nil, [String.t()]) :: :ok
  defp post_run(opts, cover_enabled?, true = _retry_enabled?, temp_output_path, passthrough_args) do
    run_retry_flow(opts, cover_enabled?, temp_output_path, passthrough_args)
  end

  defp post_run(opts, cover_enabled?, false = _retry_enabled?, temp_output_path, _passthrough_args) do
    finalize_without_retry(opts, cover_enabled?, temp_output_path)
  end

  @doc false
  # The original (no-retry) coverage/buffer output handling.
  # Note: we don't call Coverage.stop() here because :cover.stop() can kill
  # processes that imported cover-compiled modules. The cover server is cleaned
  # up when the process exits.
  @spec finalize_without_retry(keyword(), boolean(), String.t() | nil) :: :ok
  defp finalize_without_retry(opts, cover_enabled?, temp_output_path) do
    cond do
      cover_enabled? and temp_output_path ->
        merge_coverage_into_output(temp_output_path, opts)

      cover_enabled? and Keyword.has_key?(opts, :output) ->
        merge_coverage_into_file(Keyword.get(opts, :output), opts)

      temp_output_path ->
        output_buffered_json(temp_output_path)

      true ->
        :ok
    end
  end

  @doc false
  # Clears the output file at the start of a run so the formatter can distinguish
  # "file from an earlier app in this umbrella run" from "stale file from a previous run".
  # Surfaces non-:enoent errors so a locked/unwritable path fails loudly instead of
  # being masked by the later merge path reading stale content.
  @spec maybe_clear_output_file(keyword()) :: :ok
  defp maybe_clear_output_file(opts) do
    case Keyword.get(opts, :output) do
      nil ->
        :ok

      path ->
        case File.rm(path) do
          :ok ->
            :ok

          {:error, :enoent} ->
            :ok

          {:error, reason} ->
            IO.puts(:stderr, "Warning: could not clear #{path}: #{:file.format_error(reason)}")
            :ok
        end
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

  defp extract_json_opts(["--no-retry" | rest], opts, remaining) do
    extract_json_opts(rest, [{:retry, false} | opts], remaining)
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
  # Checks failed usage and shows warning/error as appropriate.
  # The `{:warn, _}` TIP is suppressed when auto-retry is enabled (retry
  # supersedes the manual --failed suggestion); the enforce_failed block always
  # fires, since it is a deliberate stricter config independent of retry.
  @spec handle_failed_usage_check(keyword(), [String.t()], boolean()) :: :ok
  defp handle_failed_usage_check(opts, test_args, retry_enabled?) do
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

      {:warn, count} when not quiet? and not retry_enabled? ->
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
  # Buffer output to a temp file when we must post-process before final output.
  # Buffer when (and only when) no explicit --output was given AND any of:
  #   1. Coverage is enabled (need to merge coverage data)
  #   2. --quiet is used (avoid stdout pollution)
  #   3. Auto-retry is enabled (need to read run-1 before deciding to re-run)
  @spec maybe_use_temp_output(keyword(), boolean(), boolean()) :: {keyword(), String.t() | nil}
  defp maybe_use_temp_output(opts, cover_enabled?, retry_enabled?) do
    has_output? = Keyword.has_key?(opts, :output)
    quiet? = Keyword.get(opts, :quiet, false)
    needs_temp_buffer? = (cover_enabled? or quiet? or retry_enabled?) and not has_output?

    if needs_temp_buffer? do
      temp_path = Path.join(System.tmp_dir!(), "ex_unit_json_#{System.unique_integer([:positive])}.json")
      {Keyword.put(opts, :output, temp_path), temp_path}
    else
      {opts, nil}
    end
  end

  @doc false
  # Decides whether to auto-retry failed tests. Default ON (project config +
  # per-invocation opt both default true). Disabled when the manual `--failed`
  # workflow is in play (also prevents the retry subprocess recursing), for
  # output modes that strip the per-test data the merge needs (summary-only,
  # first-failure, compact, group-by-error), when --filter-out provides an
  # alternative flaky strategy, for a focused file:line target, or in umbrella
  # projects (per-app suites + --failed interaction untested).
  @spec retry_enabled?(keyword(), [String.t()]) :: boolean()
  defp retry_enabled?(opts, test_args) do
    ExUnitJSON.Config.retry?() and
      Keyword.get(opts, :retry, true) and
      not retry_disqualified_opts?(opts) and
      not retry_disqualified_args?(test_args) and
      not Mix.Project.umbrella?()
  end

  @doc false
  @spec retry_disqualified_opts?(keyword()) :: boolean()
  defp retry_disqualified_opts?(opts) do
    Keyword.get(opts, :summary_only, false) or
      Keyword.get(opts, :first_failure, false) or
      Keyword.get(opts, :compact, false) or
      Keyword.get(opts, :group_by_error, false) or
      Keyword.has_key?(opts, :filter_out)
  end

  @doc false
  @spec retry_disqualified_args?([String.t()]) :: boolean()
  defp retry_disqualified_args?(test_args) do
    "--failed" in test_args or Enum.any?(test_args, &String.contains?(&1, ".exs:"))
  end

  @doc false
  # Orchestrates the retry overlay: read run 1, and if it has failures, re-run
  # the failed subset in a subprocess and merge. Coverage (if enabled) is
  # collected from run 1 only and re-attached to the final document.
  @spec run_retry_flow(keyword(), boolean(), String.t() | nil, [String.t()]) :: :ok
  defp run_retry_flow(opts, cover_enabled?, temp_output_path, passthrough_args) do
    run1_path = temp_output_path || Keyword.get(opts, :output)
    coverage = if cover_enabled?, do: collect_coverage_with_threshold(opts)

    case read_document(run1_path) do
      {:ok, run1_doc} ->
        if document_has_failures?(run1_doc) do
          retry_and_finalize(run1_doc, opts, coverage, temp_output_path, passthrough_args)
        else
          # Green run: no second run, emit run 1 (with coverage) unchanged.
          finalize_document(run1_doc, opts, coverage, temp_output_path)
        end

      {:error, _} ->
        # Run 1 produced no parseable output (e.g. tests crashed early).
        # Fall back to the plain coverage/buffer path; never mask the failure.
        finalize_without_retry(opts, cover_enabled?, temp_output_path)
    end
  end

  @doc false
  @spec retry_and_finalize(map(), keyword(), term(), String.t() | nil, [String.t()]) :: :ok
  defp retry_and_finalize(run1_doc, opts, coverage, temp_output_path, passthrough_args) do
    case run_retry_subprocess(passthrough_args) do
      {:ok, run2_doc} ->
        merged = ExUnitJSON.Retry.merge(run1_doc, run2_doc)
        finalize_retry(merged, opts, coverage, temp_output_path)

      :error ->
        IO.puts(
          :stderr,
          "Warning: ex_unit_json retry pass produced no parseable output; reporting first-run results."
        )

        finalize_document(run1_doc, opts, coverage, temp_output_path)
    end
  end

  @doc false
  # Re-runs only the previously-failed tests in a fresh `mix test.json --failed`
  # subprocess. ExUnit cannot run twice in one VM, so a subprocess is required.
  # `--failed` keeps the retry from recursing (retry_enabled?/2 is false when
  # --failed is present). `--all` makes run 2 report every re-run test's state.
  @spec run_retry_subprocess([String.t()]) :: {:ok, map()} | :error
  defp run_retry_subprocess(passthrough_args) do
    tmp2 = Path.join(System.tmp_dir!(), "ex_unit_json_retry_#{System.unique_integer([:positive])}.json")
    args = ["test.json", "--failed", "--all", "--output", tmp2 | passthrough_args]

    {_output, _exit_code} =
      System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true, env: [{"MIX_ENV", "test"}])

    result = read_document(tmp2)
    File.rm(tmp2)

    case result do
      {:ok, doc} -> {:ok, doc}
      {:error, _} -> :error
    end
  end

  @doc false
  # Writes a single (non-merged) document — used for the green and fallback
  # paths. Attaches coverage when present and applies the cover threshold.
  @spec finalize_document(map(), keyword(), term(), String.t() | nil) :: :ok
  defp finalize_document(doc, opts, coverage, temp_output_path) do
    doc
    |> maybe_attach_coverage(coverage)
    |> write_final(opts, temp_output_path)

    cleanup_temp(temp_output_path)
    maybe_exit_for_coverage(coverage)
    :ok
  end

  @doc false
  # Writes the merged document, then decides the exit code. ExUnit's at_exit
  # already yields a non-zero status because run 1 failed; the only override is
  # heal-to-green (all failures flaky) with coverage passing, where we force
  # exit 0 via System.halt/1 (bypasses at_exit, flushes stdout).
  @spec finalize_retry(map(), keyword(), term(), String.t() | nil) :: :ok
  defp finalize_retry(merged, opts, coverage, temp_output_path) do
    merged
    |> maybe_attach_coverage(coverage)
    |> write_final(opts, temp_output_path)

    cleanup_temp(temp_output_path)
    maybe_halt_for_retry_result(merged, coverage)
    :ok
  end

  @doc false
  @spec maybe_attach_coverage(map(), term()) :: map()
  defp maybe_attach_coverage(doc, nil), do: doc
  defp maybe_attach_coverage(doc, {coverage, _threshold_met?}), do: Map.put(doc, "coverage", coverage)

  @doc false
  # Writes the final JSON to stdout (when buffered to temp) or to the user's
  # explicit --output file (when no temp buffer was needed).
  @spec write_final(map(), keyword(), String.t() | nil) :: :ok
  defp write_final(doc, opts, nil) do
    # sobelow_skip ["Traversal.FileModule"]
    File.write!(Keyword.get(opts, :output), :json.encode(doc))
  end

  defp write_final(doc, _opts, _temp_output_path) do
    IO.write(:json.encode(doc))
  end

  @doc false
  @spec cleanup_temp(String.t() | nil) :: :ok
  defp cleanup_temp(nil), do: :ok

  defp cleanup_temp(path) do
    File.rm(path)
    :ok
  end

  @doc false
  # For the green/fallback path: enforce the cover threshold if one was set.
  @spec maybe_exit_for_coverage(term()) :: :ok
  defp maybe_exit_for_coverage(nil), do: :ok
  defp maybe_exit_for_coverage({coverage, threshold_met?}), do: maybe_exit_on_cover_threshold(threshold_met?, coverage)

  @doc false
  # Heal-to-green override. Coverage-below-threshold wins (report it; ExUnit's
  # at_exit yields the non-zero status since run 1 failed). Otherwise, when the
  # merged result is green, halt(0) to clear ExUnit's pending failure status.
  @spec maybe_halt_for_retry_result(map(), term()) :: :ok
  defp maybe_halt_for_retry_result(merged, coverage) do
    if coverage_threshold_ok?(coverage) and get_in(merged, ["summary", "result"]) == "passed" do
      System.halt(0)
    end

    :ok
  end

  @doc false
  # Returns true when there is no threshold or it was met; emits the standard
  # coverage error to stderr and returns false when the threshold was missed.
  @spec coverage_threshold_ok?(term()) :: boolean()
  defp coverage_threshold_ok?(nil), do: true
  defp coverage_threshold_ok?({_coverage, nil}), do: true
  defp coverage_threshold_ok?({_coverage, true}), do: true

  defp coverage_threshold_ok?({coverage, false}) do
    total = coverage["total_percentage"]
    threshold = coverage["threshold"]
    IO.puts(:stderr, "ERROR: Coverage #{total}% is below threshold #{threshold}%")
    false
  end

  @doc false
  # Reads and decodes a buffered JSON document. Returns {:error, _} when the
  # file is missing, empty, or not valid JSON (so callers can fall back).
  @spec read_document(String.t() | nil) :: {:ok, map()} | {:error, atom()}
  defp read_document(nil), do: {:error, :no_path}

  defp read_document(path) do
    case File.read(path) do
      {:ok, content} when byte_size(content) > 0 ->
        try do
          {:ok, :json.decode(content)}
        rescue
          _ -> {:error, :invalid_json}
        end

      _ ->
        {:error, :no_output}
    end
  end

  @doc false
  # Detects failures from the summary (robust across --all / failures-only) plus
  # any setup_all module failures.
  @spec document_has_failures?(map()) :: boolean()
  defp document_has_failures?(doc) do
    summary = Map.get(doc, "summary", %{})

    Map.get(summary, "failed", 0) > 0 or
      Map.get(summary, "invalid", 0) > 0 or
      Map.get(doc, "module_failures", []) != []
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
