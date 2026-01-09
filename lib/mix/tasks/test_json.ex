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
    * `--output FILE` - Write JSON to file instead of stdout
    * `--compact` - JSONL output with minimal fields (one line per test)

  ## Examples

      # Run all tests with JSON output
      mix test.json

      # Run specific file
      mix test.json test/my_test.exs

      # Output only failures to a file
      mix test.json --failures-only --output failures.json

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    ensure_test_env!()

    # Extract only our options, pass everything else to mix test unchanged
    {opts, test_args} = extract_json_opts(args)

    # Options passed via Application env because ExUnit formatter API
    # doesn't support passing options directly to formatters.
    # This is acceptable as test runs are single-instance.
    Application.put_env(:ex_unit_json, :opts, opts)

    # Configure ExUnit to use our JSON formatter
    ExUnit.configure(formatters: [ExUnitJSON.Formatter])

    # Delegate to the standard test task
    Mix.Task.run("test", test_args)
  end

  @doc false
  # Extracts ex_unit_json-specific options, passes everything else through unchanged.
  # Uses pattern matching to avoid OptionParser mangling unknown switches like --only.
  defp extract_json_opts(args), do: extract_json_opts(args, [], [])

  defp extract_json_opts([], opts, remaining) do
    {Enum.reverse(opts), Enum.reverse(remaining)}
  end

  defp extract_json_opts(["--summary-only" | rest], opts, remaining) do
    extract_json_opts(rest, [{:summary_only, true} | opts], remaining)
  end

  defp extract_json_opts(["--failures-only" | rest], opts, remaining) do
    extract_json_opts(rest, [{:failures_only, true} | opts], remaining)
  end

  defp extract_json_opts(["--output", value | rest], opts, remaining) do
    extract_json_opts(rest, [{:output, value} | opts], remaining)
  end

  defp extract_json_opts(["--compact" | rest], opts, remaining) do
    extract_json_opts(rest, [{:compact, true} | opts], remaining)
  end

  defp extract_json_opts([arg | rest], opts, remaining) do
    extract_json_opts(rest, opts, [arg | remaining])
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
end
