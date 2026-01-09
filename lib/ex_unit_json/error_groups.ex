defmodule ExUnitJSON.ErrorGroups do
  @moduledoc """
  Groups failed tests by similar error messages.

  Provides functionality for the `--group-by-error` option, which helps
  identify patterns in test failures by grouping them by error message.
  """

  # Maximum length for error pattern display
  @pattern_max_length 200

  @typedoc "A JSON-encoded test result map"
  @type encoded_test :: map()

  @typedoc "An error group with pattern, count, and example test"
  @type error_group :: %{
          pattern: String.t(),
          count: non_neg_integer(),
          example: %{
            name: String.t(),
            module: String.t(),
            file: String.t(),
            line: non_neg_integer()
          }
        }

  @doc """
  Groups failed tests by similar error message (first line of first failure).

  Returns list of groups sorted by count descending.

  ## Examples

      failed_tests = [
        %{name: "t1", failures: [%{message: "timeout"}], ...},
        %{name: "t2", failures: [%{message: "timeout"}], ...},
        %{name: "t3", failures: [%{message: "connection refused"}], ...}
      ]
      build_error_groups(failed_tests)
      #=> [
      #=>   %{pattern: "timeout", count: 2, example: %{...}},
      #=>   %{pattern: "connection refused", count: 1, example: %{...}}
      #=> ]

  """
  @spec build_error_groups([encoded_test()]) :: [error_group()]
  def build_error_groups([]), do: []

  def build_error_groups(failed_tests) do
    failed_tests
    |> Enum.group_by(&extract_error_pattern/1)
    |> Enum.map(fn {pattern, tests} ->
      example = List.first(tests)

      %{
        pattern: pattern,
        count: length(tests),
        example: %{
          name: example.name,
          module: example.module,
          file: example.file,
          line: example.line
        }
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Extracts the grouping key from a failed test.

  Uses the first line of the first failure message as the pattern.
  Normalizes whitespace for better grouping of similar errors.

  ## Examples

      test = %{failures: [%{message: "timeout after 30s\\ndetails here"}]}
      extract_error_pattern(test)
      #=> "timeout after 30s"

      test_no_failures = %{failures: []}
      extract_error_pattern(test_no_failures)
      #=> "(unknown error)"

  """
  @spec extract_error_pattern(encoded_test()) :: String.t()
  def extract_error_pattern(%{failures: [%{message: message} | _]}) when is_binary(message) do
    message
    |> String.trim()
    |> String.split("\n", parts: 2)
    |> List.first()
    |> String.trim()
    |> truncate_pattern()
  end

  def extract_error_pattern(_), do: "(unknown error)"

  @doc """
  Truncates long patterns to a reasonable length for display.

  Adds "..." suffix when truncated.

  ## Examples

      truncate_pattern("short")
      #=> "short"

      truncate_pattern(String.duplicate("x", 300))
      #=> "xxx...xxx..."  # 200 chars + "..."

  """
  @spec truncate_pattern(String.t()) :: String.t()
  def truncate_pattern(pattern) when byte_size(pattern) > @pattern_max_length do
    String.slice(pattern, 0, @pattern_max_length) <> "..."
  end

  def truncate_pattern(pattern), do: pattern
end
