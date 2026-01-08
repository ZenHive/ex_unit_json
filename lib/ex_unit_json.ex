defmodule ExUnitJSON do
  @moduledoc """
  AI-friendly JSON test output for ExUnit.

  ExUnitJSON provides a JSON formatter for ExUnit that outputs structured
  test results, making them easy for AI editors like Claude Code to parse
  and reason about.

  ## Quick Start

  Run your tests with JSON output:

      mix test.json

  ## Output Format

  The JSON output includes:

    * `version` - Schema version for forward compatibility
    * `seed` - The random seed used for test ordering
    * `summary` - Aggregate statistics (total, passed, failed, etc.)
    * `tests` - Array of individual test results

  ## Options

  See `mix help test.json` for available options including:

    * `--summary-only` - Omit individual test results
    * `--failures-only` - Include only failed tests
    * `--output FILE` - Write to file instead of stdout

  ## Modules

    * `ExUnitJSON.Formatter` - The ExUnit formatter GenServer
    * `ExUnitJSON.JSONEncoder` - Converts ExUnit structs to JSON maps

  """
end
