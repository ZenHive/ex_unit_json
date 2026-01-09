defmodule ExUnitJSON.CompactOutput do
  @moduledoc """
  Compact JSONL output format for ExUnitJSON.

  Provides functionality for the `--compact` option, which outputs one JSON
  object per line with minimal fields for efficient streaming and parsing.

  ## Format

  Each test is output as a single line JSON object with compact keys:
  - `f` - File path with line number (e.g., "test/my_test.exs:42")
  - `n` - Test name
  - `s` - Test state (passed, failed, skipped, excluded, invalid)
  - `e` - Error message first line (only for failed tests)
  - `x` - Filtered flag (only when true)

  The last line is a summary object: `{"summary": {...}}`
  """

  alias ExUnitJSON.Filters

  @typedoc "A JSON-encoded test result map"
  @type encoded_test :: map()

  @typedoc "Summary statistics map"
  @type summary :: map()

  @doc """
  Builds compact JSONL output from tests and summary.

  Returns iodata with one JSON object per line, ending with summary.

  ## Examples

      tests = [%{name: "test", file: "test.exs", line: 1, state: "passed", ...}]
      summary = %{total: 1, passed: 1, ...}
      build_compact_output(tests, summary, [])
      #=> "{\\"f\\":\\"test.exs:1\\",\\"n\\":\\"test\\",\\"s\\":\\"passed\\"}\\n{\\"summary\\":{...}}\\n"

  """
  @spec build_compact_output([encoded_test()] | nil, summary(), keyword()) :: iodata()
  def build_compact_output(nil, summary, _opts) do
    # summary_only mode - just output summary
    summary_line = IO.iodata_to_binary(:json.encode(%{summary: summary}))
    summary_line <> "\n"
  end

  def build_compact_output(tests, summary, opts) do
    patterns = Keyword.get(opts, :filter_out, [])

    test_lines =
      tests
      |> Filters.apply_filter_out(patterns)
      |> Enum.map(&encode_compact_test/1)

    summary_line = IO.iodata_to_binary(:json.encode(%{summary: summary}))

    # Join with newlines, add trailing newline
    Enum.join(test_lines ++ [summary_line], "\n") <> "\n"
  end

  @doc """
  Encodes a single test as a compact JSON object.

  ## Keys

  - `f` - file:line
  - `n` - name
  - `s` - state
  - `e` - error (first line only, only if failed)
  - `x` - filtered (only if true)

  ## Examples

      test = %{file: "test.exs", line: 10, name: "passes", state: "passed", failures: []}
      encode_compact_test(test)
      #=> "{\\"f\\":\\"test.exs:10\\",\\"n\\":\\"passes\\",\\"s\\":\\"passed\\"}"

  """
  @spec encode_compact_test(encoded_test()) :: String.t()
  def encode_compact_test(test) do
    base = %{
      "f" => "#{test.file}:#{test.line}",
      "n" => test.name,
      "s" => test.state
    }

    # Add error message (first line only) for failed tests
    compact =
      if test.state == "failed" and test.failures != [] do
        error_msg = extract_first_error_line(test.failures)
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

    IO.iodata_to_binary(:json.encode(compact))
  end

  @doc false
  # Extracts the first line of the first failure's error message
  @spec extract_first_error_line([map()]) :: String.t()
  defp extract_first_error_line([first_failure | _]) do
    first_failure
    |> Map.get(:message, "")
    |> String.trim()
    |> String.split("\n", parts: 2)
    |> List.first()
    |> String.trim()
  end

  defp extract_first_error_line([]), do: ""
end
