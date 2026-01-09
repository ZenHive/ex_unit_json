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

    test "raises on unknown option" do
      assert_raise OptionParser.ParseError, fn ->
        parse_args(["--unknown-option"])
      end
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

  # Helper to parse args using the same switches as the Mix task
  defp parse_args(args) do
    switches = [
      summary_only: :boolean,
      failures_only: :boolean,
      output: :string
    ]

    OptionParser.parse!(args, strict: switches)
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
