defmodule Mix.Tasks.Test.Json do
  @shortdoc "Run tests with JSON output"

  @moduledoc """
  Runs tests and outputs results as JSON.

  This task wraps `mix test` and configures ExUnit to use
  `ExUnitJSON.Formatter` for JSON output instead of the default
  CLI formatter.

  ## Usage

      mix test.json
      mix test.json test/my_test.exs
      mix test.json test/my_test.exs:42

  ## Options

  All standard `mix test` options are supported, plus:

    * `--summary-only` - Output only the summary, omit individual test results
    * `--failures-only` - Output only failed tests
    * `--output FILE` - Write JSON to file instead of stdout

  ## Examples

      # Run all tests with JSON output
      mix test.json

      # Run specific file
      mix test.json test/my_test.exs

      # Output only failures to a file
      mix test.json --failures-only --output failures.json

  """

  use Mix.Task

  @switches [
    summary_only: :boolean,
    failures_only: :boolean,
    output: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, test_args} = OptionParser.parse!(args, strict: @switches)

    # Options passed via Application env because ExUnit formatter API
    # doesn't support passing options directly to formatters.
    # This is acceptable as test runs are single-instance.
    Application.put_env(:ex_unit_json, :opts, opts)

    # Configure ExUnit to use our JSON formatter
    ExUnit.configure(formatters: [ExUnitJSON.Formatter])

    # Delegate to the standard test task
    Mix.Task.run("test", test_args)
  end
end
