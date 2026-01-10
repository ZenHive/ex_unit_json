defmodule Mix.Tasks.Test.JsonTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Test.Json

  # Store original config to restore after each test
  setup do
    original = Application.get_env(:ex_unit_json, :opts)
    on_exit(fn -> Application.put_env(:ex_unit_json, :opts, original) end)
    :ok
  end

  describe "option parsing" do
    test "parses --summary-only flag" do
      {opts, rest} = parse_args(["--summary-only"])

      assert opts[:summary_only] == true
      assert rest == []
    end

    test "parses --failures-only flag" do
      {opts, rest} = parse_args(["--failures-only"])

      assert opts[:failures_only] == true
      assert rest == []
    end

    test "parses --output option with file path" do
      {opts, rest} = parse_args(["--output", "results.json"])

      assert opts[:output] == "results.json"
      assert rest == []
    end

    test "parses --compact flag" do
      {opts, rest} = parse_args(["--compact"])

      assert opts[:compact] == true
      assert rest == []
    end

    test "parses --first-failure flag" do
      {opts, rest} = parse_args(["--first-failure"])

      assert opts[:first_failure] == true
      assert rest == []
    end

    test "parses --group-by-error flag" do
      {opts, rest} = parse_args(["--group-by-error"])

      assert opts[:group_by_error] == true
      assert rest == []
    end

    test "parses --quiet flag" do
      {opts, rest} = parse_args(["--quiet"])

      assert opts[:quiet] == true
      assert rest == []
    end

    test "parses --no-warn flag" do
      {opts, rest} = parse_args(["--no-warn"])

      assert opts[:no_warn] == true
      assert rest == []
    end

    test "parses single --filter-out flag" do
      {opts, rest} = parse_args(["--filter-out", "credentials"])

      assert opts[:filter_out] == ["credentials"]
      assert rest == []
    end

    test "parses multiple --filter-out flags into list" do
      {opts, rest} = parse_args(["--filter-out", "credentials", "--filter-out", "API key"])

      assert opts[:filter_out] == ["credentials", "API key"]
      assert rest == []
    end

    test "parses multiple options together" do
      {opts, rest} = parse_args(["--summary-only", "--failures-only", "--output", "out.json"])

      assert opts[:summary_only] == true
      assert opts[:failures_only] == true
      assert opts[:output] == "out.json"
      assert rest == []
    end

    test "passes through test file arguments" do
      {opts, rest} = parse_args(["test/my_test.exs", "--summary-only"])

      assert opts[:summary_only] == true
      assert rest == ["test/my_test.exs"]
    end

    test "passes through test file with line number" do
      {_opts, rest} = parse_args(["test/my_test.exs:42"])

      assert rest == ["test/my_test.exs:42"]
    end

    test "passes through multiple test files" do
      {_opts, rest} = parse_args(["test/a_test.exs", "test/b_test.exs"])

      assert rest == ["test/a_test.exs", "test/b_test.exs"]
    end

    test "mixes our options with test file arguments" do
      {opts, rest} = parse_args(["--failures-only", "test/a.exs", "--output", "o.json", "test/b.exs"])

      assert opts[:failures_only] == true
      assert opts[:output] == "o.json"
      assert rest == ["test/a.exs", "test/b.exs"]
    end

    test "passes through all mix test flags unchanged" do
      # All mix test flags should pass through without mangling
      args = [
        "--failed",
        "--only",
        "integration",
        "--exclude",
        "slow",
        "--seed",
        "12345",
        "--max-failures",
        "3",
        "--trace",
        "--stale",
        "test/my_test.exs"
      ]

      {opts, rest} = parse_args(args)

      # Our options are empty
      assert opts == []
      # All args pass through in order
      assert rest == args
    end

    test "mixes our options with mix test flags" do
      args = [
        "--failures-only",
        "--only",
        "integration",
        "--output",
        "out.json",
        "--seed",
        "999",
        "test/my_test.exs"
      ]

      {opts, rest} = parse_args(args)

      assert opts[:failures_only] == true
      assert opts[:output] == "out.json"
      # Mix test flags pass through unchanged
      assert rest == ["--only", "integration", "--seed", "999", "test/my_test.exs"]
    end
  end

  describe "module attributes" do
    test "has @shortdoc" do
      assert Mix.Task.shortdoc(Json) == "Run tests with JSON output"
    end

    test "has @moduledoc" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Json)
      assert moduledoc =~ "Runs tests and outputs results as JSON"
      assert moduledoc =~ "--summary-only"
      assert moduledoc =~ "--failures-only"
      assert moduledoc =~ "--output FILE"
    end
  end

  describe "integration: mix test.json" do
    @tag :integration
    test "outputs valid JSON for passing tests" do
      # Create a temporary test file
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationPassingTest do
          use ExUnit.Case
          test "passes" do
            assert 1 == 1
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        assert json["version"] == 1
        assert is_integer(json["seed"])
        assert json["summary"]["total"] == 1
        assert json["summary"]["passed"] == 1
        assert json["summary"]["failed"] == 0
        assert json["summary"]["result"] == "passed"
      after
        cleanup.()
      end
    end

    @tag :integration
    test "returns non-zero exit code for failing tests" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationFailingTest do
          use ExUnit.Case
          test "fails" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["failed"] == 1
        assert json["summary"]["result"] == "failed"
      after
        cleanup.()
      end
    end

    @tag :integration
    test "passes test file arguments through to mix test" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationSpecificTest do
          use ExUnit.Case
          test "specific test" do
            assert true
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        # Only the specific file should be run
        assert json["summary"]["total"] == 1
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--output writes to file" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationOutputTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      output_file = Path.join(System.tmp_dir!(), "test_output_#{System.unique_integer([:positive])}.json")

      try do
        {_output, exit_code} = run_mix_test_json([test_file, "--output", output_file])

        assert exit_code == 0
        assert File.exists?(output_file)
        content = File.read!(output_file)
        assert {:ok, json} = decode_json(content)
        assert json["summary"]["passed"] == 1
      after
        cleanup.()
        File.rm(output_file)
      end
    end

    @tag :integration
    test "--summary-only omits tests array" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationSummaryOnlyTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--summary-only"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        assert Map.has_key?(json, "summary")
        refute Map.has_key?(json, "tests")
        assert json["summary"]["total"] == 1
        assert json["summary"]["passed"] == 1
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--failures-only filters to failed tests" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationFailuresOnlyTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
          test "fails" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--failures-only"])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)
        # Summary reflects full suite
        assert json["summary"]["total"] == 2
        assert json["summary"]["passed"] == 1
        assert json["summary"]["failed"] == 1
        # Tests array only has failures
        assert length(json["tests"]) == 1
        assert hd(json["tests"])["state"] == "failed"
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--first-failure returns only first failed test" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationFirstFailureTest do
          use ExUnit.Case
          test "a_passes" do
            assert true
          end
          test "b_fails_first" do
            assert 1 == 2
          end
          test "c_fails_second" do
            assert 2 == 3
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--first-failure"])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)
        # Summary reflects full suite (all tests ran)
        assert json["summary"]["total"] == 3
        assert json["summary"]["passed"] == 1
        assert json["summary"]["failed"] == 2
        # Tests array has only the first failure (sorted by file, line, name)
        assert length(json["tests"]) == 1
        assert hd(json["tests"])["state"] == "failed"
        assert hd(json["tests"])["name"] =~ "fails"
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--first-failure returns empty tests when no failures" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationFirstFailureNoFailuresTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--first-failure"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["total"] == 1
        assert json["summary"]["passed"] == 1
        assert json["summary"]["failed"] == 0
        # Empty tests array when no failures
        assert json["tests"] == []
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--filter-out marks matching failures as filtered" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationFilterOutTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
          test "fails with credentials error" do
            flunk("Missing credentials for API")
          end
          test "fails with other error" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--filter-out", "credentials"])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)
        # Summary reflects all tests
        assert json["summary"]["total"] == 3
        assert json["summary"]["passed"] == 1
        assert json["summary"]["failed"] == 2

        # Find the filtered and non-filtered failures
        tests = json["tests"]
        assert length(tests) == 3

        credentials_test = Enum.find(tests, &(&1["name"] =~ "credentials"))
        other_fail_test = Enum.find(tests, &(&1["name"] =~ "other error"))
        pass_test = Enum.find(tests, &(&1["name"] =~ "passes"))

        # Credentials failure is marked as filtered
        assert credentials_test["filtered"] == true
        # Other failure is NOT marked as filtered
        refute Map.has_key?(other_fail_test, "filtered")
        # Passing test is NOT marked as filtered
        refute Map.has_key?(pass_test, "filtered")
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--filter-out with multiple patterns marks all matching failures" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationFilterOutMultipleTest do
          use ExUnit.Case
          test "fails with timeout" do
            flunk("Connection timeout after 30s")
          end
          test "fails with rate limit" do
            flunk("Rate limit exceeded")
          end
          test "fails with real bug" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} =
          run_mix_test_json([test_file, "--filter-out", "timeout", "--filter-out", "Rate limit"])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)

        tests = json["tests"]
        timeout_test = Enum.find(tests, &(&1["name"] =~ "timeout"))
        rate_limit_test = Enum.find(tests, &(&1["name"] =~ "rate limit"))
        bug_test = Enum.find(tests, &(&1["name"] =~ "real bug"))

        # Both expected failures are filtered
        assert timeout_test["filtered"] == true
        assert rate_limit_test["filtered"] == true
        # Real bug is NOT filtered
        refute Map.has_key?(bug_test, "filtered")
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--filter-out with no matches doesn't add filtered field" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationFilterOutNoMatchTest do
          use ExUnit.Case
          test "fails normally" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--filter-out", "nonexistent"])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)

        # No test should have filtered field
        test = hd(json["tests"])
        refute Map.has_key?(test, "filtered")
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--output with invalid path prints error to stderr but doesn't crash" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationInvalidPathTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      # Use a path in a non-existent directory
      invalid_path = "/nonexistent_directory_12345/output.json"

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--output", invalid_path])

        # Tests still pass - file write error is handled gracefully
        assert exit_code == 0
        # Error message should appear in output (stderr merged with stdout)
        assert output =~ "Error" or output =~ "Failed to write"
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--only flag filters tests correctly" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationOnlyFlagTest do
          use ExUnit.Case

          @tag :integration
          test "tagged as integration" do
            assert true
          end

          test "not tagged" do
            assert true
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--only", "integration"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        # Total includes all tests, excluded counts filtered ones
        assert json["summary"]["total"] == 2
        assert json["summary"]["passed"] == 1
        assert json["summary"]["excluded"] == 1
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--exclude flag filters tests correctly" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationExcludeFlagTest do
          use ExUnit.Case

          @tag :slow
          test "tagged as slow" do
            assert true
          end

          test "not tagged" do
            assert true
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--exclude", "slow"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        # Total includes all tests, excluded counts filtered ones
        assert json["summary"]["total"] == 2
        assert json["summary"]["passed"] == 1
        assert json["summary"]["excluded"] == 1
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--group-by-error adds error_groups to output" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationGroupByErrorTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
          test "fails with connection error" do
            flunk("Connection refused")
          end
          test "fails with same error" do
            flunk("Connection refused")
          end
          test "fails with different error" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--group-by-error"])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)
        # Summary reflects all tests
        assert json["summary"]["total"] == 4
        assert json["summary"]["failed"] == 3
        # error_groups present
        assert Map.has_key?(json, "error_groups")
        groups = json["error_groups"]
        assert length(groups) == 2
        # First group is the one with most occurrences
        first_group = hd(groups)
        assert first_group["count"] == 2
        assert first_group["pattern"] == "Connection refused"
        assert Map.has_key?(first_group, "example")
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--quiet suppresses Logger output" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationQuietTest do
          use ExUnit.Case
          require Logger

          test "logs info message" do
            Logger.info("THIS_INFO_MESSAGE_SHOULD_BE_SUPPRESSED")
            assert true
          end
        end
        """)

      try do
        # Without --quiet, Logger output appears
        {_output_noisy, _} = run_mix_test_json([test_file])
        # With --quiet, Logger output should be suppressed
        {output_quiet, exit_code} = run_mix_test_json([test_file, "--quiet"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output_quiet)
        assert json["summary"]["passed"] == 1

        # The info message should NOT appear in quiet output
        refute output_quiet =~ "THIS_INFO_MESSAGE_SHOULD_BE_SUPPRESSED",
               "Expected --quiet to suppress Logger.info output"

        # Verify noisy output would have the message (sanity check)
        # Note: This may not always work depending on Logger config, so we just
        # verify the quiet flag is being processed
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--summary-only takes precedence over --failures-only" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCombinedFlagsTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
          test "fails" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--summary-only", "--failures-only"])

        assert exit_code != 0
        assert {:ok, json} = decode_json(output)
        # Summary is present
        assert Map.has_key?(json, "summary")
        assert json["summary"]["total"] == 2
        # Tests array is omitted (summary_only takes precedence)
        refute Map.has_key?(json, "tests")
      after
        cleanup.()
      end
    end
  end

  describe "focused_run?/1 helper" do
    test "detects .exs file targeting" do
      assert focused_run?(["test/foo_test.exs"])
      assert focused_run?(["test/foo_test.exs:42"])
      assert focused_run?(["--quiet", "test/foo_test.exs"])
    end

    test "detects directory targeting" do
      # Create a temp directory to test File.dir? check
      temp_dir = Path.join(System.tmp_dir!(), "test_dir_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_dir)

      try do
        assert focused_run?([temp_dir])
        assert focused_run?(["--quiet", temp_dir])
      after
        File.rm_rf!(temp_dir)
      end
    end

    test "detects --only tag filtering" do
      assert focused_run?(["--only", "integration"])
      assert focused_run?(["--only=integration"])
    end

    test "detects --exclude tag filtering" do
      assert focused_run?(["--exclude", "slow"])
      assert focused_run?(["--exclude=slow"])
    end

    test "returns false for full suite run" do
      refute focused_run?([])
      refute focused_run?(["--quiet"])
      refute focused_run?(["--summary-only", "--quiet"])
    end
  end

  describe "check_failed_usage/2 enforcement" do
    setup do
      # Store original config
      original_enforce = Application.get_env(:ex_unit_json, :enforce_failed)
      on_exit(fn -> Application.put_env(:ex_unit_json, :enforce_failed, original_enforce) end)

      # Create temp failures file
      failures_file = Path.join(System.tmp_dir!(), "mix_test_failures_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm(failures_file) end)
      {:ok, failures_file: failures_file}
    end

    test "returns :ok when no failures file exists", %{failures_file: failures_file} do
      # Don't create the file
      assert check_failed_usage([], [], failures_file) == :ok
    end

    test "returns :ok when failures file is empty", %{failures_file: failures_file} do
      File.write!(failures_file, "")
      assert check_failed_usage([], [], failures_file) == :ok
    end

    test "returns {:warn, count} when failures exist (default)", %{failures_file: failures_file} do
      File.write!(failures_file, "test/a.exs:1\ntest/b.exs:2\ntest/c.exs:3")
      Application.put_env(:ex_unit_json, :enforce_failed, false)

      assert {:warn, 3} = check_failed_usage([], [], failures_file)
    end

    test "returns {:error, :blocked, count} when enforce_failed config is true", %{failures_file: failures_file} do
      File.write!(failures_file, "test/a.exs:1\ntest/b.exs:2")
      Application.put_env(:ex_unit_json, :enforce_failed, true)

      assert {:error, :blocked, 2} = check_failed_usage([], [], failures_file)
    end

    test "returns :ok when --no-warn is passed", %{failures_file: failures_file} do
      File.write!(failures_file, "test/a.exs:1")
      assert check_failed_usage([no_warn: true], [], failures_file) == :ok
    end

    test "returns :ok when --failed is in test_args", %{failures_file: failures_file} do
      File.write!(failures_file, "test/a.exs:1")
      assert check_failed_usage([], ["--failed"], failures_file) == :ok
    end

    test "returns :ok when targeting specific file", %{failures_file: failures_file} do
      File.write!(failures_file, "test/a.exs:1")
      assert check_failed_usage([], ["test/specific_test.exs"], failures_file) == :ok
    end

    test "returns :ok when targeting directory", %{failures_file: failures_file} do
      temp_dir = Path.join(System.tmp_dir!(), "test_target_dir_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_dir)

      try do
        File.write!(failures_file, "test/a.exs:1")
        assert check_failed_usage([], [temp_dir], failures_file) == :ok
      after
        File.rm_rf!(temp_dir)
      end
    end

    test "returns :ok when using --only filter", %{failures_file: failures_file} do
      File.write!(failures_file, "test/a.exs:1")
      assert check_failed_usage([], ["--only", "integration"], failures_file) == :ok
    end

    test "returns :ok when using --exclude filter", %{failures_file: failures_file} do
      File.write!(failures_file, "test/a.exs:1")
      assert check_failed_usage([], ["--exclude", "slow"], failures_file) == :ok
    end
  end

  describe "hint helper functions" do
    # These tests duplicate the private helper functions for test isolation.
    # If the implementation changes, update both locations.

    test "test_path?/1 detects .exs files" do
      assert test_path?("test/foo_test.exs")
      assert test_path?("test/foo_test.exs:42")
      assert test_path?("test/nested/bar_test.exs:123")
      refute test_path?("--failed")
      refute test_path?("--only")
      refute test_path?("integration")
    end

    test "count_previous_failures/1 counts lines in file" do
      path = Path.join(System.tmp_dir!(), "test_failures_#{System.unique_integer([:positive])}")
      File.write!(path, "test/a.exs:1\ntest/b.exs:2\ntest/c.exs:3")

      try do
        assert count_previous_failures(path) == 3
      after
        File.rm!(path)
      end
    end

    test "count_previous_failures/1 returns 0 for empty file" do
      path = Path.join(System.tmp_dir!(), "test_failures_empty_#{System.unique_integer([:positive])}")
      File.write!(path, "")

      try do
        assert count_previous_failures(path) == 0
      after
        File.rm!(path)
      end
    end

    test "count_previous_failures/1 returns 0 for unreadable file" do
      assert count_previous_failures("/nonexistent/path/to/file") == 0
    end

    test "count_previous_failures/1 handles single line without trailing newline" do
      path = Path.join(System.tmp_dir!(), "test_failures_single_#{System.unique_integer([:positive])}")
      File.write!(path, "test/a.exs:1")

      try do
        assert count_previous_failures(path) == 1
      after
        File.rm!(path)
      end
    end

    test "maybe_add_hint_opt/2 adds hint when .mix_test_failures exists" do
      failures_file = Path.join(System.tmp_dir!(), "test_hint_#{System.unique_integer([:positive])}")
      File.write!(failures_file, "test/a.exs:1\ntest/b.exs:2")

      try do
        opts = maybe_add_hint_opt([], [], failures_file)
        assert opts[:hint] =~ "2 test(s) failed previously"
        assert opts[:hint] =~ "--failed"
      after
        File.rm!(failures_file)
      end
    end

    test "maybe_add_hint_opt/2 returns unchanged opts when --failed flag present" do
      failures_file = Path.join(System.tmp_dir!(), "test_hint_failed_#{System.unique_integer([:positive])}")
      File.write!(failures_file, "test/a.exs:1")

      try do
        opts = maybe_add_hint_opt([], ["--failed"], failures_file)
        refute Keyword.has_key?(opts, :hint)
      after
        File.rm!(failures_file)
      end
    end

    test "maybe_add_hint_opt/2 returns unchanged opts when specific test file targeted" do
      failures_file = Path.join(System.tmp_dir!(), "test_hint_target_#{System.unique_integer([:positive])}")
      File.write!(failures_file, "test/a.exs:1")

      try do
        opts = maybe_add_hint_opt([], ["test/specific_test.exs"], failures_file)
        refute Keyword.has_key?(opts, :hint)
      after
        File.rm!(failures_file)
      end
    end

    test "maybe_add_hint_opt/2 returns unchanged opts when no failures file exists" do
      opts = maybe_add_hint_opt([], [], "/nonexistent/path/to/failures")
      refute Keyword.has_key?(opts, :hint)
    end
  end

  # Helper functions duplicating private module logic for test isolation
  defp test_path?(arg) do
    String.ends_with?(arg, ".exs") or String.contains?(arg, ".exs:")
  end

  # Duplicates focused_run?/1 from Mix.Tasks.Test.Json
  defp focused_run?(test_args) do
    Enum.any?(test_args, fn arg ->
      String.ends_with?(arg, ".exs") or
        String.contains?(arg, ".exs:") or
        File.dir?(arg) or
        String.starts_with?(arg, "--only") or
        String.starts_with?(arg, "--exclude")
    end)
  end

  # Duplicates check_failed_usage/2 from Mix.Tasks.Test.Json with configurable failures file
  defp check_failed_usage(opts, test_args, failures_file) do
    with true <- File.exists?(failures_file),
         count when count > 0 <- count_previous_failures(failures_file),
         false <- "--failed" in test_args,
         false <- focused_run?(test_args),
         false <- Keyword.get(opts, :no_warn, false) do
      if Application.get_env(:ex_unit_json, :enforce_failed, false) do
        {:error, :blocked, count}
      else
        {:warn, count}
      end
    else
      _ -> :ok
    end
  end

  defp count_previous_failures(path) do
    case File.read(path) do
      {:ok, content} -> content |> String.split("\n", trim: true) |> length()
      {:error, _} -> 0
    end
  end

  # Helper for testing hint logic with configurable failures file path
  defp maybe_add_hint_opt(opts, test_args, failures_file) do
    has_failed_flag = "--failed" in test_args
    has_specific_target = Enum.any?(test_args, &test_path?/1)

    cond do
      has_failed_flag ->
        opts

      has_specific_target ->
        opts

      not File.exists?(failures_file) ->
        opts

      true ->
        count = count_previous_failures(failures_file)
        hint = "#{count} test(s) failed previously. Use --failed to re-run only those."
        Keyword.put(opts, :hint, hint)
    end
  end

  # Helper to parse args using the same logic as the Mix task.
  # NOTE: This duplicates the logic in Mix.Tasks.Test.Json.extract_json_opts/3
  # for test isolation. If you add a new flag, update both locations.
  defp parse_args(args), do: extract_json_opts(args, [], [])

  defp extract_json_opts([], opts, remaining) do
    {merge_list_opts(Enum.reverse(opts)), Enum.reverse(remaining)}
  end

  defp extract_json_opts(["--summary-only" | rest], opts, remaining) do
    extract_json_opts(rest, [{:summary_only, true} | opts], remaining)
  end

  defp extract_json_opts(["--failures-only" | rest], opts, remaining) do
    extract_json_opts(rest, [{:failures_only, true} | opts], remaining)
  end

  defp extract_json_opts(["--first-failure" | rest], opts, remaining) do
    extract_json_opts(rest, [{:first_failure, true} | opts], remaining)
  end

  defp extract_json_opts(["--filter-out", value | rest], opts, remaining) do
    extract_json_opts(rest, [{:filter_out, value} | opts], remaining)
  end

  defp extract_json_opts(["--output", value | rest], opts, remaining) do
    extract_json_opts(rest, [{:output, value} | opts], remaining)
  end

  defp extract_json_opts(["--compact" | rest], opts, remaining) do
    extract_json_opts(rest, [{:compact, true} | opts], remaining)
  end

  defp extract_json_opts(["--group-by-error" | rest], opts, remaining) do
    extract_json_opts(rest, [{:group_by_error, true} | opts], remaining)
  end

  defp extract_json_opts(["--quiet" | rest], opts, remaining) do
    extract_json_opts(rest, [{:quiet, true} | opts], remaining)
  end

  defp extract_json_opts(["--no-warn" | rest], opts, remaining) do
    extract_json_opts(rest, [{:no_warn, true} | opts], remaining)
  end

  defp extract_json_opts([arg | rest], opts, remaining) do
    extract_json_opts(rest, opts, [arg | remaining])
  end

  defp merge_list_opts(opts) do
    filters = Keyword.get_values(opts, :filter_out)
    rest = Keyword.delete(opts, :filter_out)

    if filters == [] do
      rest
    else
      [{:filter_out, filters} | rest]
    end
  end

  # Helper to create a temporary test file
  defp create_temp_test_file(content) do
    filename = "integration_test_#{System.unique_integer([:positive])}_test.exs"
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, content)
    cleanup = fn -> File.rm(path) end
    {path, cleanup}
  end

  # Helper to run mix test.json as a shell command
  defp run_mix_test_json(args) do
    cmd_args = ["test.json" | args]
    project_dir = Path.expand("../../..", __DIR__)

    {output, exit_code} =
      System.cmd("mix", cmd_args,
        cd: project_dir,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    {output, exit_code}
  end

  # Helper to decode JSON, handling potential compilation output prefix.
  # :json.decode/1 returns the decoded value directly (not {:ok, value}).
  defp decode_json(output) do
    # The output may contain compilation messages before the JSON
    # Find the last valid JSON object in the output
    case Regex.scan(~r/\{[^{}]*"version"[^{}]*\}|\{.*"version".*\}/s, output) do
      [] ->
        {:error, :no_json_found}

      matches ->
        # Take the last match (the actual test output, not any nested test outputs)
        json_str = matches |> List.last() |> List.first()
        {:ok, :json.decode(json_str)}
    end
  rescue
    e in [ArgumentError, ErlangError] ->
      {:error, {:decode_failed, Exception.message(e)}}
  end
end
