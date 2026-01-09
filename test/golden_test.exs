defmodule ExUnitJSON.GoldenTest do
  @moduledoc """
  Golden tests for JSON schema validation.

  These tests verify that the JSON output conforms to the documented schema v1.
  They use real test files to ensure the complete pipeline produces correct output.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  describe "JSON Schema v1 conformance" do
    test "output contains all required root fields" do
      {test_file, cleanup} = create_golden_test_file(:passing)

      try do
        json = run_and_parse([test_file])

        # Required root fields
        assert Map.has_key?(json, "version")
        assert Map.has_key?(json, "seed")
        assert Map.has_key?(json, "summary")
        assert Map.has_key?(json, "tests")

        # Version is integer 1
        assert json["version"] == 1
        assert is_integer(json["seed"])
      after
        cleanup.()
      end
    end

    test "summary contains all required fields" do
      {test_file, cleanup} = create_golden_test_file(:mixed)

      try do
        json = run_and_parse([test_file])
        summary = json["summary"]

        # All required summary fields
        assert is_integer(summary["total"])
        assert is_integer(summary["passed"])
        assert is_integer(summary["failed"])
        assert is_integer(summary["skipped"])
        assert is_integer(summary["excluded"])
        assert is_integer(summary["duration_us"])
        assert summary["result"] in ["passed", "failed"]
      after
        cleanup.()
      end
    end

    test "test object contains all required fields" do
      {test_file, cleanup} = create_golden_test_file(:passing)

      try do
        json = run_and_parse([test_file])
        [test | _] = json["tests"]

        # Required test fields
        assert is_binary(test["name"])
        assert is_binary(test["module"])
        assert is_binary(test["file"])
        assert is_integer(test["line"])
        assert test["state"] in ["passed", "failed", "skipped", "excluded"]
        assert is_integer(test["duration_us"])
        assert is_map(test["tags"])
        assert is_list(test["failures"])
      after
        cleanup.()
      end
    end

    test "failure object contains required fields for assertion errors" do
      {test_file, cleanup} = create_golden_test_file(:failing)

      try do
        json = run_and_parse([test_file])
        [test | _] = Enum.filter(json["tests"], &(&1["state"] == "failed"))
        [failure | _] = test["failures"]

        # Required failure fields
        assert is_binary(failure["message"])
        assert is_list(failure["stacktrace"])
        assert failure["kind"] in ["assertion", "error", "exit", "throw"]

        # Assertion-specific fields
        if failure["kind"] == "assertion" do
          assert Map.has_key?(failure, "assertion")
          assertion = failure["assertion"]
          assert is_binary(assertion["expr"])
          assert is_binary(assertion["left"])
          assert is_binary(assertion["right"])
        end
      after
        cleanup.()
      end
    end

    test "stacktrace frames have correct structure" do
      {test_file, cleanup} = create_golden_test_file(:failing)

      try do
        json = run_and_parse([test_file])
        [test | _] = Enum.filter(json["tests"], &(&1["state"] == "failed"))
        [failure | _] = test["failures"]

        # Find a frame with file info
        frame_with_file = Enum.find(failure["stacktrace"], &Map.has_key?(&1, "file"))

        if frame_with_file do
          assert is_binary(frame_with_file["file"])
          assert is_integer(frame_with_file["line"])
        end
      after
        cleanup.()
      end
    end
  end

  describe "test states" do
    test "passed test has correct state" do
      {test_file, cleanup} = create_golden_test_file(:passing)

      try do
        json = run_and_parse([test_file])

        assert json["summary"]["passed"] == 1
        assert json["summary"]["result"] == "passed"

        [test] = json["tests"]
        assert test["state"] == "passed"
        assert test["failures"] == []
      after
        cleanup.()
      end
    end

    test "failed test has correct state and failures" do
      {test_file, cleanup} = create_golden_test_file(:failing)

      try do
        json = run_and_parse([test_file])

        assert json["summary"]["failed"] == 1
        assert json["summary"]["result"] == "failed"

        [test] = json["tests"]
        assert test["state"] == "failed"
        assert test["failures"] != []
      after
        cleanup.()
      end
    end

    test "skipped test has correct state" do
      {test_file, cleanup} = create_golden_test_file(:skipped)

      try do
        json = run_and_parse([test_file])

        assert json["summary"]["skipped"] == 1
        assert json["summary"]["result"] == "passed"

        [test] = json["tests"]
        assert test["state"] == "skipped"
      after
        cleanup.()
      end
    end

    # Note: Excluded state is tested in formatter_test.exs unit tests.
    # Integration testing with --exclude flag is complex due to option parsing,
    # but the state encoding is fully verified at the unit level.

    test "setup_all failure produces module_failures" do
      {test_file, cleanup} = create_golden_test_file(:setup_all_failure)

      try do
        json = run_and_parse([test_file])

        assert Map.has_key?(json, "module_failures")
        assert json["module_failures"] != []

        [module_failure | _] = json["module_failures"]
        assert is_binary(module_failure["name"])
        assert is_binary(module_failure["file"])
        assert module_failure["state"] == "failed"
        assert is_list(module_failure["failures"])
      after
        cleanup.()
      end
    end
  end

  describe "deterministic ordering" do
    test "tests are sorted by file, line, name" do
      {test_file, cleanup} = create_golden_test_file(:ordering)

      try do
        json = run_and_parse([test_file])
        names = Enum.map(json["tests"], & &1["name"])

        # Tests should be sorted by line number (order in file)
        # z_test is defined first, then m_test, then a_test
        assert names == ["test z_test", "test m_test", "test a_test"]
      after
        cleanup.()
      end
    end
  end

  describe "mixed test suite" do
    test "handles combination of pass, fail, skip" do
      {test_file, cleanup} = create_golden_test_file(:mixed)

      try do
        json = run_and_parse([test_file])

        assert json["summary"]["total"] == 3
        assert json["summary"]["passed"] == 1
        assert json["summary"]["failed"] == 1
        assert json["summary"]["skipped"] == 1
        assert json["summary"]["result"] == "failed"

        states = json["tests"] |> Enum.map(& &1["state"]) |> Enum.sort()
        assert states == ["failed", "passed", "skipped"]
      after
        cleanup.()
      end
    end
  end

  # Helper to create temporary test files for golden tests
  defp create_golden_test_file(:passing) do
    create_temp_test_file("""
    defmodule GoldenPassingTest do
      use ExUnit.Case
      test "passes" do
        assert 1 == 1
      end
    end
    """)
  end

  defp create_golden_test_file(:failing) do
    create_temp_test_file("""
    defmodule GoldenFailingTest do
      use ExUnit.Case
      test "fails" do
        assert 1 == 2
      end
    end
    """)
  end

  defp create_golden_test_file(:skipped) do
    create_temp_test_file("""
    defmodule GoldenSkippedTest do
      use ExUnit.Case
      @tag :skip
      test "skipped" do
        assert true
      end
    end
    """)
  end

  defp create_golden_test_file(:setup_all_failure) do
    create_temp_test_file("""
    defmodule GoldenSetupAllFailureTest do
      use ExUnit.Case

      setup_all do
        raise "setup_all intentionally failed"
      end

      test "never runs" do
        assert true
      end
    end
    """)
  end

  defp create_golden_test_file(:ordering) do
    create_temp_test_file("""
    defmodule GoldenOrderingTest do
      use ExUnit.Case
      test "z_test" do
        assert true
      end
      test "m_test" do
        assert true
      end
      test "a_test" do
        assert true
      end
    end
    """)
  end

  defp create_golden_test_file(:mixed) do
    create_temp_test_file("""
    defmodule GoldenMixedTest do
      use ExUnit.Case

      test "passes" do
        assert true
      end

      test "fails" do
        assert 1 == 2
      end

      @tag :skip
      test "skipped" do
        assert true
      end
    end
    """)
  end

  defp create_temp_test_file(content) do
    filename = "golden_test_#{System.unique_integer([:positive])}_test.exs"
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, content)
    cleanup = fn -> File.rm(path) end
    {path, cleanup}
  end

  defp run_and_parse(args) do
    project_dir = Path.expand("..", __DIR__)

    {output, _exit_code} =
      System.cmd("mix", ["test.json" | args],
        cd: project_dir,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    # Extract JSON from output (may have compilation messages)
    case Regex.scan(~r/\{.*"version".*\}/s, output) do
      [] -> raise "No JSON found in output: #{output}"
      matches -> matches |> List.last() |> List.first() |> :json.decode()
    end
  end
end
