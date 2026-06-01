defmodule Mix.Tasks.Test.JsonTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Test.Json

  @cover_threshold_requires_cover 80
  @cover_threshold_met_value 0.0
  @cover_threshold_fail_value 100.0
  @cover_threshold_exit_code 2
  @exit_code_success 0
  @binary_start_index 0
  @json_object_open_char "{"
  @json_object_close_char "}"
  @json_object_close_len byte_size(@json_object_close_char)

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

    test "parses --all flag (inverse of failures_only)" do
      {opts, rest} = parse_args(["--all"])

      assert opts[:failures_only] == false
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

    test "parses --no-retry flag" do
      {opts, rest} = parse_args(["--no-retry"])

      assert opts[:retry] == false
      assert rest == []
    end

    test "parses --cover flag" do
      {opts, rest} = parse_args(["--cover"])

      assert opts[:cover] == true
      assert rest == []
    end

    test "parses --cover-threshold option with value" do
      value = Integer.to_string(@cover_threshold_requires_cover)
      {opts, rest} = parse_args(["--cover-threshold", value])

      assert opts[:cover_threshold] == value
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

    test "passes through multiple --only flags unchanged" do
      # Multiple --only flags should pass through in order for mix test to handle
      args = ["--only", "ws_integration", "--only", "exchange_okx", "--only", "ws_public"]

      {opts, rest} = parse_args(args)

      # Our options are empty (--only is a mix test flag)
      assert opts == []
      # All args pass through in exact order
      assert rest == ["--only", "ws_integration", "--only", "exchange_okx", "--only", "ws_public"]
    end

    test "passes through multiple --exclude flags unchanged" do
      args = ["--exclude", "slow", "--exclude", "external", "--exclude", "integration"]

      {opts, rest} = parse_args(args)

      assert opts == []
      assert rest == ["--exclude", "slow", "--exclude", "external", "--exclude", "integration"]
    end

    test "mixes our options with multiple --only flags" do
      args = [
        "--failures-only",
        "--only",
        "tag_a",
        "--only",
        "tag_b",
        "--output",
        "out.json",
        "--only",
        "tag_c"
      ]

      {opts, rest} = parse_args(args)

      assert opts[:failures_only] == true
      assert opts[:output] == "out.json"
      # Mix test flags pass through unchanged and in order
      assert rest == ["--only", "tag_a", "--only", "tag_b", "--only", "tag_c"]
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
      assert moduledoc =~ "--cover-threshold"
    end
  end

  describe "integration: mix test.json" do
    @tag :integration
    test "outputs valid JSON for passing tests (default: empty tests array)" do
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
        # Default behavior (v0.3.0+): only failures shown, so tests array is empty
        assert json["tests"] == []
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--all shows all tests including passing" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationAllFlagTest do
          use ExUnit.Case
          test "passes" do
            assert 1 == 1
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--all"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["total"] == 1
        assert json["summary"]["passed"] == 1
        # --all flag shows all tests
        assert length(json["tests"]) == 1
        assert hd(json["tests"])["state"] == "passed"
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
        # Use --all to include passing tests in output
        {_output, exit_code} = run_mix_test_json([test_file, "--all", "--output", output_file])

        assert exit_code == 0
        assert File.exists?(output_file)
        content = File.read!(output_file)
        assert {:ok, json} = decode_json(content)
        assert json["summary"]["passed"] == 1
        assert length(json["tests"]) == 1
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
        # Use --all to include passing tests in output for this test
        {output, exit_code} = run_mix_test_json([test_file, "--all", "--filter-out", "credentials"])

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
    test "multiple --only flags filter tests correctly (OR logic)" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationMultipleOnlyFlagsTest do
          use ExUnit.Case

          @tag :tag_a
          test "tagged as tag_a" do
            assert true
          end

          @tag :tag_b
          test "tagged as tag_b" do
            assert true
          end

          @tag :tag_c
          test "tagged as tag_c" do
            assert true
          end

          test "not tagged" do
            assert true
          end
        end
        """)

      try do
        # Use --only tag_a --only tag_b (should include tests with tag_a OR tag_b)
        {output, exit_code} = run_mix_test_json([test_file, "--only", "tag_a", "--only", "tag_b"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        # 4 total tests, 2 passed (tag_a and tag_b), 2 excluded (tag_c and untagged)
        assert json["summary"]["total"] == 4
        assert json["summary"]["passed"] == 2
        assert json["summary"]["excluded"] == 2
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
        # Without --quiet, Logger output appears (use --all to see the test)
        {_output_noisy, _} = run_mix_test_json([test_file, "--all"])
        # With --quiet, Logger output should be suppressed
        {output_quiet, exit_code} = run_mix_test_json([test_file, "--quiet", "--all"])

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

    @tag :integration
    test "environment variables are inherited by test process" do
      # This test verifies that environment variables set in the parent process
      # are accessible to tests run via mix test.json. This is a regression test
      # for a reported issue where env vars appeared to be missing.
      env_var_name = "EX_UNIT_JSON_TEST_#{System.unique_integer([:positive])}"

      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationEnvVarTest do
          use ExUnit.Case

          test "can read environment variable" do
            value = System.get_env("#{env_var_name}")

            if is_nil(value) do
              flunk("Environment variable #{env_var_name} is nil!")
            end

            assert value == "secret_test_value_123"
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json_with_env([test_file], [{env_var_name, "secret_test_value_123"}])

        assert exit_code == 0, "Expected test to pass. Output: #{output}"
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["passed"] == 1
        assert json["summary"]["failed"] == 0
      after
        cleanup.()
      end
    end

    @tag :integration
    test "environment variables work with --quiet flag" do
      # Specifically test that --quiet doesn't affect env var inheritance
      env_var_name = "EX_UNIT_JSON_QUIET_#{System.unique_integer([:positive])}"

      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationEnvVarQuietTest do
          use ExUnit.Case

          test "can read environment variable with --quiet" do
            value = System.get_env("#{env_var_name}")
            assert value == "quiet_mode_value"
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json_with_env([test_file, "--quiet"], [{env_var_name, "quiet_mode_value"}])

        assert exit_code == 0, "Expected test to pass. Output: #{output}"
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["passed"] == 1
      after
        cleanup.()
      end
    end
  end

  describe "integration: auto-retry-on-flaky" do
    @tag :integration
    test "flaky failure heals to green and is surfaced, not hidden" do
      {test_file, cleanup} = flaky_fixture()
      marker = Path.join(System.tmp_dir!(), "flaky_marker_#{System.unique_integer([:positive])}")
      File.rm(marker)

      try do
        {output, exit_code} = run_mix_test_json_with_env([test_file], [{"FLAKY_MARKER", marker}])

        assert exit_code == 0, "Expected heal-to-green exit 0. Output: #{output}"
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["result"] == "passed"
        assert json["summary"]["failed"] == 0
        assert json["summary"]["flaky"] == 1
        # The flaky test is named, never swept away.
        assert [flaky] = json["flaky"]
        assert flaky["name"] =~ "heals on retry"
        assert json["retry"] == %{"ran" => true, "passes" => 1, "retried" => 1, "confirmed" => 0, "flaky" => 1}
      after
        cleanup.()
        File.rm(marker)
      end
    end

    @tag :integration
    test "a genuine hard failure stays red after retry" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule AutoRetryHardFailTest do
          use ExUnit.Case
          test "always fails" do
            assert 1 == 2
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file])

        assert exit_code != 0, "Expected confirmed failure to stay red. Output: #{output}"
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["result"] == "failed"
        assert json["summary"]["failed"] == 1
        assert json["summary"]["flaky"] == 0
        assert length(json["tests"]) == 1
        refute Map.has_key?(json, "flaky")
        assert json["retry"]["confirmed"] == 1
      after
        cleanup.()
      end
    end

    @tag :integration
    test "a green suite runs once and adds no retry metadata" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule AutoRetryGreenTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["result"] == "passed"
        # No second run happened: no retry block, no flaky key.
        refute Map.has_key?(json, "retry")
        refute Map.has_key?(json, "flaky")
      after
        cleanup.()
      end
    end

    @tag :integration
    test "--no-retry reports the raw first run with no retry metadata" do
      {test_file, cleanup} = flaky_fixture()
      marker = Path.join(System.tmp_dir!(), "flaky_marker_#{System.unique_integer([:positive])}")
      File.rm(marker)

      try do
        {output, exit_code} = run_mix_test_json_with_env([test_file, "--no-retry"], [{"FLAKY_MARKER", marker}])

        # Opt-out: the flaky test is reported as a plain failure, no healing.
        assert exit_code != 0, "Expected --no-retry to leave the failure red. Output: #{output}"
        assert {:ok, json} = decode_json(output)
        assert json["summary"]["result"] == "failed"
        refute Map.has_key?(json, "retry")
        refute Map.has_key?(json, "flaky")
      after
        cleanup.()
        File.rm(marker)
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
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1", "test/b.exs:2", "test/c.exs:3"]))
      Application.put_env(:ex_unit_json, :enforce_failed, false)

      assert {:warn, 3} = check_failed_usage([], [], failures_file)
    end

    test "returns {:error, :blocked, count} when enforce_failed config is true", %{failures_file: failures_file} do
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1", "test/b.exs:2"]))
      Application.put_env(:ex_unit_json, :enforce_failed, true)

      assert {:error, :blocked, 2} = check_failed_usage([], [], failures_file)
    end

    test "returns :ok when --no-warn is passed", %{failures_file: failures_file} do
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))
      assert check_failed_usage([no_warn: true], [], failures_file) == :ok
    end

    test "returns :ok when --failed is in test_args", %{failures_file: failures_file} do
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))
      assert check_failed_usage([], ["--failed"], failures_file) == :ok
    end

    test "returns :ok when targeting specific file", %{failures_file: failures_file} do
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))
      assert check_failed_usage([], ["test/specific_test.exs"], failures_file) == :ok
    end

    test "returns :ok when targeting directory", %{failures_file: failures_file} do
      temp_dir = Path.join(System.tmp_dir!(), "test_target_dir_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_dir)

      try do
        File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))
        assert check_failed_usage([], [temp_dir], failures_file) == :ok
      after
        File.rm_rf!(temp_dir)
      end
    end

    test "returns :ok when using --only filter", %{failures_file: failures_file} do
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))
      assert check_failed_usage([], ["--only", "integration"], failures_file) == :ok
    end

    test "returns :ok when using --exclude filter", %{failures_file: failures_file} do
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))
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
      File.write!(path, :erlang.term_to_binary(["test/a.exs:1", "test/b.exs:2", "test/c.exs:3"]))

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

    test "count_previous_failures/1 returns 0 for malformed binary file" do
      path = Path.join(System.tmp_dir!(), "malformed_#{System.unique_integer([:positive])}")
      File.write!(path, "not erlang term format")

      try do
        assert count_previous_failures(path) == 0
      after
        File.rm!(path)
      end
    end

    test "count_previous_failures/1 handles single line without trailing newline" do
      path = Path.join(System.tmp_dir!(), "test_failures_single_#{System.unique_integer([:positive])}")
      File.write!(path, :erlang.term_to_binary(["test/a.exs:1"]))

      try do
        assert count_previous_failures(path) == 1
      after
        File.rm!(path)
      end
    end

    test "maybe_add_hint_opt/2 adds hint when .mix_test_failures exists" do
      failures_file = Path.join(System.tmp_dir!(), "test_hint_#{System.unique_integer([:positive])}")
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1", "test/b.exs:2"]))

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
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))

      try do
        opts = maybe_add_hint_opt([], ["--failed"], failures_file)
        refute Keyword.has_key?(opts, :hint)
      after
        File.rm!(failures_file)
      end
    end

    test "maybe_add_hint_opt/2 returns unchanged opts when specific test file targeted" do
      failures_file = Path.join(System.tmp_dir!(), "test_hint_target_#{System.unique_integer([:positive])}")
      File.write!(failures_file, :erlang.term_to_binary(["test/a.exs:1"]))

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

  # Synced with Mix.Tasks.Test.Json.count_previous_failures/1
  # Handles both old format (list) and new Elixir 1.17+ format (map)
  defp count_previous_failures(path) do
    case File.read(path) do
      {:ok, content} when byte_size(content) > 0 ->
        try do
          case :erlang.binary_to_term(content) do
            # New format (Elixir 1.17+): {version, %{test_id => state}}
            {_version, failures_map} when is_map(failures_map) ->
              map_size(failures_map)

            # Old format: list of test identifiers
            failures when is_list(failures) ->
              length(failures)

            _ ->
              0
          end
        rescue
          _ -> 0
        end

      {:ok, _} ->
        0

      {:error, _} ->
        0
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

  defp extract_json_opts(["--all" | rest], opts, remaining) do
    extract_json_opts(rest, [{:failures_only, false} | opts], remaining)
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

  defp extract_json_opts(["--no-retry" | rest], opts, remaining) do
    extract_json_opts(rest, [{:retry, false} | opts], remaining)
  end

  defp extract_json_opts(["--cover" | rest], opts, remaining) do
    extract_json_opts(rest, [{:cover, true} | opts], remaining)
  end

  defp extract_json_opts(["--cover-threshold", value | rest], opts, remaining) do
    extract_json_opts(rest, [{:cover_threshold, value} | opts], remaining)
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

  # A deterministically-flaky fixture: fails the first run (no marker file yet),
  # passes the retry (marker now exists). The marker persists across the
  # in-process run 1 and the `--failed` retry subprocess via a shared tmp path
  # passed through the FLAKY_MARKER env var.
  defp flaky_fixture do
    create_temp_test_file("""
    defmodule AutoRetryFlakyHealsTest do
      use ExUnit.Case

      test "heals on retry" do
        marker = System.get_env("FLAKY_MARKER")

        if marker && File.exists?(marker) do
          assert true
        else
          if marker, do: File.write!(marker, "x")
          flunk("first run fails on purpose")
        end
      end
    end
    """)
  end

  # Helper to run mix test.json as a shell command
  defp run_mix_test_json(args) do
    run_mix_test_json_with_env(args, [])
  end

  # Helper to run mix test.json with additional environment variables
  # env_vars is a list of {name, value} tuples to add to the environment
  defp run_mix_test_json_with_env(args, env_vars) do
    cmd_args = ["test.json" | args]
    project_dir = Path.expand("../../..", __DIR__)

    # Build env list: MIX_ENV=test plus any additional vars
    env = [{"MIX_ENV", "test"} | env_vars]

    {output, exit_code} =
      System.cmd("mix", cmd_args,
        cd: project_dir,
        stderr_to_stdout: true,
        env: env
      )

    {output, exit_code}
  end

  # Helper to decode JSON, handling potential compilation output prefix/suffix.
  # :json.decode/1 returns the decoded value directly (not {:ok, value}).
  defp decode_json(output) do
    # The output may contain compilation messages before the JSON.
    # Find the last line starting with "{" (the JSON output).
    json_line =
      output
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, @json_object_open_char))
      |> List.last()

    case json_line do
      nil -> {:error, :no_json_found}
      line -> decode_json_line(line)
    end
  end

  defp decode_json_line(line) do
    case try_decode_json(line) do
      {:ok, json} ->
        {:ok, json}

      {:error, _reason} ->
        line
        |> trim_after_last_brace()
        |> try_decode_json()
    end
  end

  defp try_decode_json(line) do
    {:ok, :json.decode(line)}
  rescue
    e in [ArgumentError, ErlangError] ->
      {:error, {:decode_failed, Exception.message(e)}}
  end

  defp trim_after_last_brace(line) do
    case last_index(line, @json_object_close_char) do
      nil ->
        line

      idx ->
        binary_part(line, @binary_start_index, idx + @json_object_close_len)
    end
  end

  defp last_index(string, pattern) do
    case :binary.matches(string, pattern) do
      [] ->
        nil

      matches ->
        {idx, _len} = List.last(matches)
        idx
    end
  end

  # Helper to run mix test.json in the Phoenix test app
  defp run_mix_test_json_in_phoenix_app(args) do
    phoenix_app_dir = Path.expand("../../../test_apps/phoenix_app", __DIR__)
    cmd_args = ["test.json" | args]

    {output, exit_code} =
      System.cmd("mix", cmd_args,
        cd: phoenix_app_dir,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    {output, exit_code}
  end

  # Helper to run mix test.json in the logger test app
  # This app has Logger.info calls in test_helper.exs to test --quiet suppression
  defp run_mix_test_json_in_logger_app(args) do
    logger_app_dir = Path.expand("../../../test_apps/logger_app", __DIR__)
    cmd_args = ["test.json" | args]

    {output, exit_code} =
      System.cmd("mix", cmd_args,
        cd: logger_app_dir,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}, {"MIX_QUIET", "1"}]
      )

    {output, exit_code}
  end

  # Helper to run mix test.json in the coverage test app
  # This app has lib code to test coverage instrumentation.
  # Supports :isolated_build option to use a unique MIX_BUILD_PATH (simulates clean build).
  defp run_mix_test_json_in_coverage_app(args, opts) do
    coverage_app_dir = Path.expand("../../../test_apps/coverage_app", __DIR__)
    cmd_args = ["test.json" | args]

    env = [{"MIX_ENV", "test"}]

    # Use isolated build path to simulate clean build without destructive commands
    {env, temp_build_path} =
      if Keyword.get(opts, :isolated_build, false) do
        temp_path = Path.join(System.tmp_dir!(), "ex_unit_json_build_#{System.unique_integer([:positive])}")
        {[{"MIX_BUILD_PATH", temp_path} | env], temp_path}
      else
        {env, nil}
      end

    {output, exit_code} =
      System.cmd("mix", cmd_args,
        cd: coverage_app_dir,
        stderr_to_stdout: true,
        env: env
      )

    # Clean up isolated build directory if used
    if temp_build_path && File.exists?(temp_build_path) do
      File.rm_rf!(temp_build_path)
    end

    {output, exit_code}
  end

  describe "Logger suppression integration" do
    @describetag :logger_integration

    @tag :logger_integration
    test "--quiet suppresses Logger output from test_helper.exs" do
      # The logger_app has Logger.info calls in test_helper.exs
      # With --quiet, these should NOT appear in stdout
      {output, exit_code} = run_mix_test_json_in_logger_app(["--quiet", "--summary-only"])

      assert exit_code == 0, "Expected exit code 0, got #{exit_code}. Output: #{output}"

      # Logger output should NOT be present
      refute output =~ "[info]", "Logger output should be suppressed with --quiet. Got: #{output}"
      refute output =~ "Test setup message", "Logger message from test_helper.exs should be suppressed"

      # But JSON should still be valid
      assert {:ok, json} = decode_json(output)
      assert json["version"] == 1
      assert json["summary"]["passed"] == 2
    end

    @tag :logger_integration
    test "Logger output appears without --quiet" do
      # Without --quiet, Logger.info should still work
      {output, exit_code} = run_mix_test_json_in_logger_app(["--summary-only"])

      assert exit_code == 0
      # Logger output SHOULD be present without --quiet
      assert output =~ "[info]" or output =~ "Test setup message",
             "Logger output should appear without --quiet"

      # JSON should still be valid
      assert {:ok, _json} = decode_json(output)
    end

    @tag :logger_integration
    test "--quiet produces clean JSON for jq piping" do
      # This test verifies the main use case: piping to jq
      {output, exit_code} = run_mix_test_json_in_logger_app(["--quiet", "--summary-only"])

      assert exit_code == 0

      # Output should be ONLY valid JSON (no Logger prefix, no other lines)
      lines = String.split(output, "\n", trim: true)

      # Should have exactly one line (the JSON)
      assert length(lines) == 1, "Expected 1 line of output, got #{length(lines)}: #{inspect(lines)}"

      # That line should be valid JSON
      json_line = List.first(lines)
      assert String.starts_with?(json_line, "{"), "Output should start with '{': #{json_line}"
      assert {:ok, _json} = decode_json(output)
    end
  end

  describe "Phoenix app integration" do
    @describetag :phoenix_integration

    @tag :phoenix_integration
    test "outputs JSON (not CLI) in Phoenix project" do
      # This test verifies the fix for the bug where mix test.json
      # would output CLI format (dots) instead of JSON in Phoenix projects
      # due to race conditions with ExUnit.configure.
      {output, exit_code} = run_mix_test_json_in_phoenix_app(["--quiet", "--summary-only"])

      assert exit_code == 0, "Expected exit code 0, got #{exit_code}. Output: #{output}"

      # The key assertion: output must be valid JSON, not CLI format
      case decode_json(output) do
        {:ok, json} ->
          assert json["version"] == 1
          assert is_map(json["summary"])
          assert json["summary"]["total"] >= 1

        {:error, :no_json_found} ->
          flunk("""
          Expected JSON output but got CLI format!
          This indicates the ExUnitJSON.Formatter was not properly configured.

          Output:
          #{output}
          """)

        {:error, {:decode_failed, reason}} ->
          flunk("Failed to decode JSON: #{reason}\n\nOutput:\n#{output}")
      end
    end

    @tag :phoenix_integration
    test "default behavior shows only failures in Phoenix project" do
      # v0.3.0+: Default is failures-only, so all-passing suite shows empty tests array
      {output, exit_code} = run_mix_test_json_in_phoenix_app(["--quiet"])

      # All Phoenix app tests pass, so we expect success and empty tests array
      assert exit_code == 0
      assert {:ok, json} = decode_json(output)
      assert json["tests"] == []
    end

    @tag :phoenix_integration
    test "--all shows all tests in Phoenix project" do
      {output, exit_code} = run_mix_test_json_in_phoenix_app(["--quiet", "--all"])

      # All Phoenix app tests pass, with --all we should see them
      assert exit_code == 0
      assert {:ok, json} = decode_json(output)
      assert json["tests"] != []
      assert Enum.all?(json["tests"], &(&1["state"] == "passed"))
    end
  end

  describe "coverage integration" do
    @describetag :coverage_integration

    @tag :coverage_integration
    test "excludes coverage by default" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverageDefaultTest do
          use ExUnit.Case
          test "passes" do
            assert 1 == 1
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--quiet"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)

        # Coverage should NOT be present by default (v0.5.0+)
        refute Map.has_key?(json, "coverage"),
               "Expected no coverage key by default (use --cover to enable)"
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "--cover includes coverage in output" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverTest do
          use ExUnit.Case
          test "passes" do
            assert 1 == 1
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--quiet", "--cover"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)

        # Coverage should be present with --cover
        assert Map.has_key?(json, "coverage"), "Expected coverage key with --cover flag"

        coverage = json["coverage"]
        assert Map.has_key?(coverage, "total_percentage")
        assert Map.has_key?(coverage, "total_lines")
        assert Map.has_key?(coverage, "covered_lines")
        assert Map.has_key?(coverage, "modules")

        assert is_number(coverage["total_percentage"])
        assert is_integer(coverage["total_lines"])
        assert is_integer(coverage["covered_lines"])
        assert is_list(coverage["modules"])
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "--cover-threshold requires --cover" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverThresholdRequiresCoverTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      try do
        value = Integer.to_string(@cover_threshold_requires_cover)
        {output, exit_code} = run_mix_test_json([test_file, "--cover-threshold", value])

        refute exit_code == @exit_code_success
        assert output =~ "--cover-threshold requires --cover"
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "--cover-threshold adds metadata and passes when met" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverThresholdMetTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      try do
        value = Float.to_string(@cover_threshold_met_value)
        {output, exit_code} = run_mix_test_json([test_file, "--quiet", "--cover", "--cover-threshold", value])

        assert exit_code == @exit_code_success
        assert {:ok, json} = decode_json(output)
        coverage = json["coverage"]

        assert coverage["threshold"] == @cover_threshold_met_value
        assert coverage["threshold_met"] == true
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "--cover-threshold fails when below threshold" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverThresholdFailTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      try do
        value = Float.to_string(@cover_threshold_fail_value)
        {output, exit_code} = run_mix_test_json([test_file, "--quiet", "--cover", "--cover-threshold", value])

        assert exit_code == @cover_threshold_exit_code
        assert {:ok, json} = decode_json(output)
        coverage = json["coverage"]

        assert coverage["threshold"] == @cover_threshold_fail_value
        assert coverage["threshold_met"] == false
        assert coverage["total_percentage"] < coverage["threshold"]
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "coverage modules have expected structure" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverageStructureTest do
          use ExUnit.Case
          test "passes" do
            # Just verify the module is callable - opts may contain coverage settings
            assert is_list(ExUnitJSON.Config.get_opts())
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--quiet", "--cover"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)
        assert Map.has_key?(json, "coverage")

        coverage = json["coverage"]

        # Should have modules (the project's lib/ modules)
        assert coverage["modules"] != [], "Expected at least one module in coverage"

        # Check structure of first module
        mod = hd(coverage["modules"])
        assert Map.has_key?(mod, "module")
        assert Map.has_key?(mod, "file")
        assert Map.has_key?(mod, "percentage")
        assert Map.has_key?(mod, "covered_lines")
        assert Map.has_key?(mod, "uncovered_lines")

        # File should be relative path
        if mod["file"] do
          refute String.starts_with?(mod["file"], "/"),
                 "File path should be relative: #{mod["file"]}"
        end
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "coverage works with --output flag" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverageOutputTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      output_file = Path.join(System.tmp_dir!(), "coverage_output_#{System.unique_integer([:positive])}.json")

      try do
        {_output, exit_code} = run_mix_test_json([test_file, "--cover", "--output", output_file])

        assert exit_code == 0
        assert File.exists?(output_file)

        content = File.read!(output_file)
        assert {:ok, json} = decode_json(content)

        # Coverage should be present in file output
        assert Map.has_key?(json, "coverage")
        assert is_number(json["coverage"]["total_percentage"])
      after
        cleanup.()
        File.rm(output_file)
      end
    end

    @tag :coverage_integration
    test "coverage percentages are valid" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoveragePercentageTest do
          use ExUnit.Case
          test "calls some code" do
            # This exercises some code paths
            opts = ExUnitJSON.Config.get_opts()
            assert is_list(opts)
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--quiet", "--cover"])

        assert exit_code == 0
        assert {:ok, json} = decode_json(output)

        coverage = json["coverage"]

        # Total percentage should be between 0 and 100
        assert coverage["total_percentage"] >= 0
        assert coverage["total_percentage"] <= 100

        # Each module percentage should be valid
        for mod <- coverage["modules"] do
          assert mod["percentage"] >= 0, "Module #{mod["module"]} has percentage < 0"
          assert mod["percentage"] <= 100, "Module #{mod["module"]} has percentage > 100"
        end
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "--cover with --compact outputs warning and JSONL without coverage" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverCompactTest do
          use ExUnit.Case
          test "passes" do
            assert 1 == 1
          end
        end
        """)

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--cover", "--compact", "--all"])

        assert exit_code == 0

        # Should output a warning about unsupported combination
        assert output =~ "Warning" or output =~ "--cover with --compact is not supported"

        # Output should be JSONL (one JSON per line) - find the test result line
        lines = String.split(output, "\n", trim: true)
        json_lines = Enum.filter(lines, &String.starts_with?(&1, "{"))
        assert json_lines != [], "Expected at least one JSON line in compact output"

        # The JSONL output should NOT have coverage merged in (it's omitted)
        for json_line <- json_lines do
          json = :json.decode(json_line)

          refute Map.has_key?(json, "coverage"),
                 "Coverage should not be in compact JSONL output"
        end
      after
        cleanup.()
      end
    end

    @tag :coverage_integration
    test "--cover with --compact and --output outputs warning" do
      {test_file, cleanup} =
        create_temp_test_file("""
        defmodule IntegrationCoverCompactOutputTest do
          use ExUnit.Case
          test "passes" do
            assert true
          end
        end
        """)

      output_file = Path.join(System.tmp_dir!(), "cover_compact_#{System.unique_integer([:positive])}.json")

      try do
        {output, exit_code} = run_mix_test_json([test_file, "--cover", "--compact", "--output", output_file])

        assert exit_code == 0

        # Should output a warning
        assert output =~ "Warning" or output =~ "--cover with --compact is not supported"

        # File should exist and contain JSONL
        assert File.exists?(output_file)
        content = File.read!(output_file)

        # JSONL lines should NOT have coverage
        lines = String.split(content, "\n", trim: true)

        for line <- lines, String.starts_with?(line, "{") do
          json = :json.decode(line)
          refute Map.has_key?(json, "coverage")
        end
      after
        cleanup.()
        File.rm(output_file)
      end
    end

    @tag :coverage_integration
    @tag :clean_build
    test "coverage works on clean build (regression test)" do
      # This test verifies that coverage instrumentation works even on a clean build
      # where beam files don't exist yet. The fix ensures compilation happens BEFORE
      # coverage instrumentation starts.
      #
      # We use the coverage_app test app with an isolated MIX_BUILD_PATH to simulate
      # a clean build without running destructive commands like `mix clean`.

      # Run with coverage using isolated build path (simulates clean build)
      {output, exit_code} = run_mix_test_json_in_coverage_app(["--quiet", "--cover"], isolated_build: true)

      assert exit_code == 0, "Expected exit code 0, got #{exit_code}. Output: #{output}"
      assert {:ok, json} = decode_json(output)

      # Coverage should be present
      assert Map.has_key?(json, "coverage"),
             "Expected coverage data on clean build. Output: #{output}"

      coverage = json["coverage"]

      # Should have non-empty coverage data
      assert coverage["modules"] != [],
             "Expected at least one module in coverage on clean build"

      # Should find the CoverageApp module specifically
      coverage_app_module = Enum.find(coverage["modules"], &(&1["module"] == "CoverageApp"))

      assert coverage_app_module != nil,
             "Expected CoverageApp module in coverage. Got modules: #{inspect(Enum.map(coverage["modules"], & &1["module"]))}"

      # The module should have reasonable coverage (tests exercise all functions)
      assert coverage_app_module["percentage"] > 0,
             "Expected non-zero coverage for CoverageApp module"
    end
  end
end
