defmodule ExUnitJSON.Filters do
  @moduledoc """
  Test filtering logic for ExUnitJSON.

  Provides functions to filter test results based on configuration options
  like `--failures-only`, `--first-failure`, and `--filter-out` patterns.
  """

  @typedoc "A JSON-encoded test result map"
  @type encoded_test :: map()

  @typedoc "Filter options keyword list"
  @type filter_opts :: [
          summary_only: boolean(),
          failures_only: boolean(),
          first_failure: boolean(),
          filter_out: [String.t()]
        ]

  @doc """
  Filters tests based on configuration options.

  Returns nil for summary_only (omit tests array), filtered list, or all tests.

  ## Priority

    1. `summary_only` - Highest priority, returns nil (omits tests array)
    2. `first_failure` - Returns only the first failed test
    3. `failures_only` - Returns all failed tests
    4. Default - Returns all tests

  ## Examples

      # summary_only returns nil
      filter_tests(tests, summary_only: true)
      #=> nil

      # failures_only returns only failed tests
      filter_tests([%{state: "passed"}, %{state: "failed"}], failures_only: true)
      #=> [%{state: "failed"}]

  """
  @spec filter_tests([encoded_test()], filter_opts()) :: [encoded_test()] | nil
  def filter_tests(tests, opts) do
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

  @doc """
  Marks failed tests as filtered if their failure message matches any pattern.

  Returns tests unchanged if no patterns provided.

  ## Examples

      # No patterns - tests unchanged
      apply_filter_out(tests, [])
      #=> tests

      # Matching pattern adds :filtered key
      tests = [%{state: "failed", failures: [%{message: "credentials missing"}]}]
      apply_filter_out(tests, ["credentials"])
      #=> [%{state: "failed", failures: [...], filtered: true}]

  """
  @spec apply_filter_out([encoded_test()], [String.t()]) :: [encoded_test()]
  def apply_filter_out(tests, []), do: tests

  def apply_filter_out(tests, patterns) do
    Enum.map(tests, fn test ->
      if test.state == "failed" and failure_matches_pattern?(test, patterns) do
        Map.put(test, :filtered, true)
      else
        test
      end
    end)
  end

  @doc """
  Checks if any failure message in the test matches any of the patterns.

  ## Examples

      test = %{failures: [%{message: "connection timeout"}]}
      failure_matches_pattern?(test, ["timeout"])
      #=> true

      failure_matches_pattern?(test, ["credentials"])
      #=> false

  """
  @spec failure_matches_pattern?(encoded_test(), [String.t()]) :: boolean()
  def failure_matches_pattern?(%{failures: failures}, patterns) when is_list(failures) do
    Enum.any?(failures, fn failure ->
      message = Map.get(failure, :message, "")
      Enum.any?(patterns, fn pattern -> String.contains?(message, pattern) end)
    end)
  end

  def failure_matches_pattern?(_, _), do: false

  @doc """
  Rejects (excludes) failed tests whose failure message matches any pattern.

  Unlike `apply_filter_out/2` which marks tests with `filtered: true`,
  this function removes matching tests entirely. Used for error_groups
  where filtered failures should not appear at all.

  ## Examples

      # No patterns - tests unchanged
      reject_filtered_failures(tests, [])
      #=> tests

      # Matching failures are removed entirely
      tests = [
        %{state: "failed", failures: [%{message: "credentials missing"}]},
        %{state: "failed", failures: [%{message: "timeout error"}]}
      ]
      reject_filtered_failures(tests, ["credentials"])
      #=> [%{state: "failed", failures: [%{message: "timeout error"}]}]

  """
  @spec reject_filtered_failures([encoded_test()], [String.t()]) :: [encoded_test()]
  def reject_filtered_failures(tests, []), do: tests

  def reject_filtered_failures(tests, patterns) do
    Enum.reject(tests, fn test ->
      test.state == "failed" and failure_matches_pattern?(test, patterns)
    end)
  end

  @doc """
  Counts failed tests that match any filter_out pattern.

  Returns 0 if no patterns provided or no matches found.

  ## Examples

      tests = [
        %{state: "failed", failures: [%{message: "credentials missing"}]},
        %{state: "failed", failures: [%{message: "timeout error"}]},
        %{state: "passed"}
      ]
      count_filtered_failures(tests, ["credentials"])
      #=> 1

      count_filtered_failures(tests, [])
      #=> 0

  """
  @spec count_filtered_failures([encoded_test()], [String.t()]) :: non_neg_integer()
  def count_filtered_failures(_tests, []), do: 0

  def count_filtered_failures(tests, patterns) do
    Enum.count(tests, fn test ->
      test.state == "failed" and failure_matches_pattern?(test, patterns)
    end)
  end
end
