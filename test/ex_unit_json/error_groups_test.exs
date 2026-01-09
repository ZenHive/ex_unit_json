defmodule ExUnitJSON.ErrorGroupsTest do
  use ExUnit.Case, async: true

  alias ExUnitJSON.ErrorGroups

  describe "build_error_groups/1" do
    test "returns empty list for empty input" do
      assert ErrorGroups.build_error_groups([]) == []
    end

    test "groups tests by error pattern" do
      tests = [
        %{name: "t1", module: "M", file: "f.ex", line: 1, failures: [%{message: "timeout"}]},
        %{name: "t2", module: "M", file: "f.ex", line: 2, failures: [%{message: "timeout"}]},
        %{name: "t3", module: "M", file: "f.ex", line: 3, failures: [%{message: "other error"}]}
      ]

      groups = ErrorGroups.build_error_groups(tests)

      assert length(groups) == 2

      timeout_group = Enum.find(groups, &(&1.pattern == "timeout"))
      assert timeout_group.count == 2

      other_group = Enum.find(groups, &(&1.pattern == "other error"))
      assert other_group.count == 1
    end

    test "sorts groups by count descending" do
      tests = [
        %{name: "t1", module: "M", file: "f.ex", line: 1, failures: [%{message: "rare error"}]},
        %{name: "t2", module: "M", file: "f.ex", line: 2, failures: [%{message: "common error"}]},
        %{name: "t3", module: "M", file: "f.ex", line: 3, failures: [%{message: "common error"}]},
        %{name: "t4", module: "M", file: "f.ex", line: 4, failures: [%{message: "common error"}]}
      ]

      groups = ErrorGroups.build_error_groups(tests)

      assert hd(groups).pattern == "common error"
      assert hd(groups).count == 3
    end

    test "includes example with test details" do
      tests = [
        %{name: "example_test", module: "MyModule", file: "test/example.exs", line: 42, failures: [%{message: "boom"}]}
      ]

      [group] = ErrorGroups.build_error_groups(tests)

      assert group.example.name == "example_test"
      assert group.example.module == "MyModule"
      assert group.example.file == "test/example.exs"
      assert group.example.line == 42
    end
  end

  describe "extract_error_pattern/1" do
    test "extracts first line of error message" do
      test = %{failures: [%{message: "first line\nsecond line\nthird line"}]}

      assert ErrorGroups.extract_error_pattern(test) == "first line"
    end

    test "trims whitespace" do
      test = %{failures: [%{message: "  error message  \n  details  "}]}

      assert ErrorGroups.extract_error_pattern(test) == "error message"
    end

    test "returns unknown error for empty failures" do
      test = %{failures: []}

      assert ErrorGroups.extract_error_pattern(test) == "(unknown error)"
    end

    test "returns unknown error when no message" do
      test = %{failures: [%{kind: "error"}]}

      assert ErrorGroups.extract_error_pattern(test) == "(unknown error)"
    end

    test "returns unknown error when no failures key" do
      test = %{state: "failed"}

      assert ErrorGroups.extract_error_pattern(test) == "(unknown error)"
    end

    test "returns unknown error when message is not binary" do
      test = %{failures: [%{message: :atom_message}]}

      assert ErrorGroups.extract_error_pattern(test) == "(unknown error)"
    end
  end

  describe "truncate_pattern/1" do
    test "returns short patterns unchanged" do
      pattern = "short error"

      assert ErrorGroups.truncate_pattern(pattern) == "short error"
    end

    test "truncates patterns longer than 200 chars" do
      long_pattern = String.duplicate("x", 250)

      result = ErrorGroups.truncate_pattern(long_pattern)

      assert String.length(result) == 203
      assert String.ends_with?(result, "...")
    end

    test "returns exactly 200 char pattern unchanged" do
      pattern = String.duplicate("x", 200)

      assert ErrorGroups.truncate_pattern(pattern) == pattern
    end
  end
end
