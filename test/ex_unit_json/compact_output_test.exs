defmodule ExUnitJSON.CompactOutputTest do
  use ExUnit.Case, async: true

  alias ExUnitJSON.CompactOutput

  describe "build_compact_output/3" do
    test "returns only summary when tests is nil (summary_only mode)" do
      summary = %{total: 2, passed: 2, failed: 0}

      result = CompactOutput.build_compact_output(nil, summary, [])

      lines = String.split(result, "\n", trim: true)
      assert length(lines) == 1

      {:ok, decoded} = decode_json(hd(lines))
      assert Map.has_key?(decoded, "summary")
    end

    test "outputs one line per test plus summary" do
      tests = [
        %{file: "test.exs", line: 1, name: "t1", state: "passed", failures: []},
        %{file: "test.exs", line: 2, name: "t2", state: "passed", failures: []}
      ]

      summary = %{total: 2, passed: 2}

      result = CompactOutput.build_compact_output(tests, summary, [])

      lines = String.split(result, "\n", trim: true)
      assert length(lines) == 3
    end

    test "applies filter_out patterns" do
      tests = [
        %{file: "t.exs", line: 1, name: "t1", state: "failed", failures: [%{message: "timeout"}]},
        %{file: "t.exs", line: 2, name: "t2", state: "failed", failures: [%{message: "real bug"}]}
      ]

      summary = %{total: 2, failed: 2}

      result = CompactOutput.build_compact_output(tests, summary, filter_out: ["timeout"])

      lines = String.split(result, "\n", trim: true)
      {:ok, timeout_test} = decode_json(hd(lines))

      assert timeout_test["x"] == true
    end

    test "ends with trailing newline" do
      result = CompactOutput.build_compact_output(nil, %{}, [])

      assert String.ends_with?(result, "\n")
    end
  end

  describe "encode_compact_test/1" do
    test "encodes basic test with compact keys" do
      test = %{file: "test/example.exs", line: 42, name: "test passes", state: "passed", failures: []}

      result = CompactOutput.encode_compact_test(test)
      {:ok, decoded} = decode_json(result)

      assert decoded["f"] == "test/example.exs:42"
      assert decoded["n"] == "test passes"
      assert decoded["s"] == "passed"
    end

    test "includes error message for failed tests" do
      test = %{
        file: "test.exs",
        line: 1,
        name: "fails",
        state: "failed",
        failures: [%{message: "first line\nsecond line"}]
      }

      result = CompactOutput.encode_compact_test(test)
      {:ok, decoded} = decode_json(result)

      assert decoded["e"] == "first line"
    end

    test "does not include error for passed tests" do
      test = %{file: "test.exs", line: 1, name: "passes", state: "passed", failures: []}

      result = CompactOutput.encode_compact_test(test)
      {:ok, decoded} = decode_json(result)

      refute Map.has_key?(decoded, "e")
    end

    test "does not include error for failed tests with empty failures" do
      test = %{file: "test.exs", line: 1, name: "fails", state: "failed", failures: []}

      result = CompactOutput.encode_compact_test(test)
      {:ok, decoded} = decode_json(result)

      refute Map.has_key?(decoded, "e")
    end

    test "includes filtered flag when present" do
      test = %{file: "test.exs", line: 1, name: "t", state: "failed", failures: [], filtered: true}

      result = CompactOutput.encode_compact_test(test)
      {:ok, decoded} = decode_json(result)

      assert decoded["x"] == true
    end

    test "does not include filtered flag when false" do
      test = %{file: "test.exs", line: 1, name: "t", state: "passed", failures: [], filtered: false}

      result = CompactOutput.encode_compact_test(test)
      {:ok, decoded} = decode_json(result)

      refute Map.has_key?(decoded, "x")
    end

    test "does not include filtered flag when not present" do
      test = %{file: "test.exs", line: 1, name: "t", state: "passed", failures: []}

      result = CompactOutput.encode_compact_test(test)
      {:ok, decoded} = decode_json(result)

      refute Map.has_key?(decoded, "x")
    end
  end

  # Helper to decode JSON
  defp decode_json(string) do
    {:ok, :json.decode(string)}
  rescue
    e in [ArgumentError, ErlangError] -> {:error, Exception.message(e)}
  end
end
