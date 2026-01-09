defmodule ExUnitJSON.FiltersTest do
  use ExUnit.Case, async: true

  alias ExUnitJSON.Filters

  describe "filter_tests/2" do
    test "returns nil when summary_only is true" do
      tests = [%{state: "passed"}, %{state: "failed"}]

      assert Filters.filter_tests(tests, summary_only: true) == nil
    end

    test "returns first failure when first_failure is true" do
      tests = [
        %{state: "passed", name: "t1"},
        %{state: "failed", name: "t2"},
        %{state: "failed", name: "t3"}
      ]

      result = Filters.filter_tests(tests, first_failure: true)

      assert length(result) == 1
      assert hd(result).name == "t2"
    end

    test "returns empty list when first_failure is true and no failures" do
      tests = [%{state: "passed"}, %{state: "skipped"}]

      assert Filters.filter_tests(tests, first_failure: true) == []
    end

    test "returns only failed tests when failures_only is true" do
      tests = [
        %{state: "passed", name: "t1"},
        %{state: "failed", name: "t2"},
        %{state: "skipped", name: "t3"}
      ]

      result = Filters.filter_tests(tests, failures_only: true)

      assert length(result) == 1
      assert hd(result).name == "t2"
    end

    test "returns all tests when no filter options" do
      tests = [%{state: "passed"}, %{state: "failed"}]

      assert Filters.filter_tests(tests, []) == tests
    end

    test "summary_only takes precedence over first_failure" do
      tests = [%{state: "failed"}]

      assert Filters.filter_tests(tests, summary_only: true, first_failure: true) == nil
    end

    test "first_failure takes precedence over failures_only" do
      tests = [
        %{state: "failed", name: "t1"},
        %{state: "failed", name: "t2"}
      ]

      result = Filters.filter_tests(tests, first_failure: true, failures_only: true)

      assert length(result) == 1
    end
  end

  describe "apply_filter_out/2" do
    test "returns tests unchanged when no patterns" do
      tests = [%{state: "failed", failures: [%{message: "error"}]}]

      assert Filters.apply_filter_out(tests, []) == tests
    end

    test "marks matching failed tests as filtered" do
      tests = [
        %{state: "failed", failures: [%{message: "connection timeout"}]},
        %{state: "failed", failures: [%{message: "assertion error"}]}
      ]

      result = Filters.apply_filter_out(tests, ["timeout"])

      assert Enum.at(result, 0).filtered == true
      refute Map.has_key?(Enum.at(result, 1), :filtered)
    end

    test "does not mark passing tests as filtered" do
      tests = [%{state: "passed", failures: []}]

      result = Filters.apply_filter_out(tests, ["anything"])

      refute Map.has_key?(hd(result), :filtered)
    end

    test "matches multiple patterns" do
      tests = [
        %{state: "failed", failures: [%{message: "timeout error"}]},
        %{state: "failed", failures: [%{message: "rate limit exceeded"}]},
        %{state: "failed", failures: [%{message: "real bug"}]}
      ]

      result = Filters.apply_filter_out(tests, ["timeout", "rate limit"])

      assert Enum.at(result, 0).filtered == true
      assert Enum.at(result, 1).filtered == true
      refute Map.has_key?(Enum.at(result, 2), :filtered)
    end
  end

  describe "failure_matches_pattern?/2" do
    test "returns true when message contains pattern" do
      test = %{failures: [%{message: "connection timeout after 30s"}]}

      assert Filters.failure_matches_pattern?(test, ["timeout"])
    end

    test "returns false when message does not contain pattern" do
      test = %{failures: [%{message: "connection timeout"}]}

      refute Filters.failure_matches_pattern?(test, ["credentials"])
    end

    test "checks all failures in list" do
      test = %{
        failures: [
          %{message: "first error"},
          %{message: "timeout occurred"}
        ]
      }

      assert Filters.failure_matches_pattern?(test, ["timeout"])
    end

    test "returns false for empty failures list" do
      test = %{failures: []}

      refute Filters.failure_matches_pattern?(test, ["anything"])
    end

    test "returns false when failures is not a list" do
      test = %{failures: nil}

      refute Filters.failure_matches_pattern?(test, ["anything"])
    end

    test "returns false when no failures key" do
      test = %{state: "passed"}

      refute Filters.failure_matches_pattern?(test, ["anything"])
    end

    test "handles missing message key" do
      test = %{failures: [%{kind: "error"}]}

      refute Filters.failure_matches_pattern?(test, ["anything"])
    end
  end
end
