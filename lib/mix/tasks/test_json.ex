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
    * `--failures-only` - Output only failed tests
    * `--first-failure` - Output only the first failed test (quick iteration)
    * `--filter-out PATTERN` - Mark failures matching pattern as filtered (can repeat)
    * `--output FILE` - Write JSON to file instead of stdout
    * `--compact` - JSONL output with minimal fields (one line per test)
    * `--group-by-error` - Group failures by similar error message
    * `--quiet` - Suppress Logger output for cleaner JSON (sets Logger level to :error)
    * `--no-warn` - Suppress the "use --failed" warning when previous failures exist

  ## Flag Precedence

  When multiple filtering flags are combined, they follow this priority:

    1. `--summary-only` - Highest priority, omits tests array entirely
    2. `--first-failure` - Returns only the first failed test
    3. `--failures-only` - Returns all failed tests

  For example, `--summary-only --failures-only` will omit the tests array.

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

  @impl Mix.Task
  def run(args) do
    ensure_test_env!()

    # Extract only our options, pass everything else to mix test unchanged
    {opts, test_args} = extract_json_opts(args)

    # When --quiet is used, suppress output that would corrupt the JSON stream:
    # - Mix shell output (compile messages) - requires MIX_QUIET=1 env var set externally
    # - Logger output - redirect to stderr and filter to errors only
    # Note: Mix.shell(Mix.Shell.Quiet) only helps for output AFTER this point.
    # Compilation output happens before this code runs, so MIX_QUIET=1 must be
    # set externally when piping (or use --output FILE instead of piping).
    if Keyword.get(opts, :quiet, false) do
      Mix.shell(Mix.Shell.Quiet)
      :logger.set_handler_config(:default, :config, %{type: :standard_error})
      :logger.set_handler_config(:default, :level, :error)
    end

    # Check if user should use --failed (warn by default, block if configured)
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

      {:warn, count} ->
        other_args = Enum.join(test_args, " ")

        IO.puts(:stderr, """
        TIP: #{count} previous failure(s) exist. Consider:
          mix test.json --failed #{other_args}
          mix test.json test/unit/ --failed
          mix test.json --only integration --failed
        (Use --no-warn to suppress this message)
        """)

      :ok ->
        :ok
    end

    # Compute hint for JSON output (suggests --failed when appropriate)
    opts = maybe_add_hint_opt(opts, test_args)

    # Options passed via Application env because ExUnit formatter API
    # doesn't support passing options directly to formatters.
    # This is acceptable as test runs are single-instance.
    Application.put_env(:ex_unit_json, :opts, opts)

    # Use --formatter flag instead of ExUnit.configure to avoid race conditions
    # with test_helper.exs and stale compilation issues. This is more robust
    # as it uses mix test's native formatter handling.
    Mix.Task.run("test", ["--formatter", "ExUnitJSON.Formatter" | test_args])
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
end
