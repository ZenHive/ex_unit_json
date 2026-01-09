defmodule ExUnitJSON.FormatterTest do
  use ExUnit.Case, async: false

  alias ExUnitJSON.Formatter

  # Store original config to restore after each test
  setup do
    original = Application.get_env(:ex_unit_json, :opts)
    on_exit(fn -> Application.put_env(:ex_unit_json, :opts, original) end)

    # Stop any existing formatter process
    case GenServer.whereis(Formatter) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    :ok
  end

  describe "init/1" do
    test "creates initial state with empty collections" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()
      state = GenServer.call(pid, :get_state)

      assert state.tests == []
      assert state.modules == []
      assert state.seed == nil
      assert is_integer(state.start_time)
    end

    test "merges options from Application env" do
      Application.put_env(:ex_unit_json, :opts, summary_only: true)
      {:ok, pid} = Formatter.start_link()
      state = GenServer.call(pid, :get_state)

      assert Keyword.get(state.opts, :summary_only) == true
    end

    test "merges options from start_link argument" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link(failures_only: true)
      state = GenServer.call(pid, :get_state)

      assert Keyword.get(state.opts, :failures_only) == true
    end

    test "start_link opts override Application env opts" do
      Application.put_env(:ex_unit_json, :opts, summary_only: true)
      {:ok, pid} = Formatter.start_link(summary_only: false)
      state = GenServer.call(pid, :get_state)

      assert Keyword.get(state.opts, :summary_only) == false
    end
  end

  describe "handle_cast {:suite_started, opts}" do
    test "captures seed from suite options" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:suite_started, seed: 12_345, max_cases: 8})
      state = GenServer.call(pid, :get_state)

      assert state.seed == 12_345
    end

    test "handles missing seed gracefully" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:suite_started, []})
      state = GenServer.call(pid, :get_state)

      assert state.seed == nil
    end
  end

  describe "handle_cast {:test_finished, test}" do
    test "accumulates passed test" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      test = build_test(name: :"test passes", state: nil)
      GenServer.cast(pid, {:test_finished, test})
      state = GenServer.call(pid, :get_state)

      assert length(state.tests) == 1
      [encoded] = state.tests
      assert encoded.name == "test passes"
      assert encoded.state == "passed"
    end

    test "accumulates failed test" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      error = %RuntimeError{message: "boom"}
      test = build_test(name: :"test fails", state: {:failed, [{:error, error, []}]})
      GenServer.cast(pid, {:test_finished, test})
      state = GenServer.call(pid, :get_state)

      assert length(state.tests) == 1
      [encoded] = state.tests
      assert encoded.name == "test fails"
      assert encoded.state == "failed"
      assert length(encoded.failures) == 1
    end

    test "accumulates multiple tests in order" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      test1 = build_test(name: :"test one", state: nil)
      test2 = build_test(name: :"test two", state: nil)
      test3 = build_test(name: :"test three", state: nil)

      GenServer.cast(pid, {:test_finished, test1})
      GenServer.cast(pid, {:test_finished, test2})
      GenServer.cast(pid, {:test_finished, test3})
      state = GenServer.call(pid, :get_state)

      assert length(state.tests) == 3

      # Tests are prepended for O(1) insertion during accumulation.
      # The final output (Task 5) will reverse to restore chronological order.
      names = Enum.map(state.tests, & &1.name)
      assert names == ["test three", "test two", "test one"]
    end

    test "accumulates skipped test" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      test = build_test(name: :"test skipped", state: {:skipped, "not implemented"})
      GenServer.cast(pid, {:test_finished, test})
      state = GenServer.call(pid, :get_state)

      [encoded] = state.tests
      assert encoded.state == "skipped"
    end

    test "accumulates excluded test" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      test = build_test(name: :"test excluded", state: {:excluded, "tag filter"})
      GenServer.cast(pid, {:test_finished, test})
      state = GenServer.call(pid, :get_state)

      [encoded] = state.tests
      assert encoded.state == "excluded"
    end
  end

  describe "handle_cast {:module_finished, module}" do
    test "tracks module with setup_all failure" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      error = %RuntimeError{message: "setup_all failed"}
      module = build_module(state: {:failed, [{:error, error, []}]})

      GenServer.cast(pid, {:module_finished, module})
      state = GenServer.call(pid, :get_state)

      assert length(state.modules) == 1
      [encoded] = state.modules
      assert encoded.state == "failed"
      assert length(encoded.failures) == 1
    end

    test "ignores module without failures" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      module = build_module(state: nil)
      GenServer.cast(pid, {:module_finished, module})
      state = GenServer.call(pid, :get_state)

      assert state.modules == []
    end

    test "encodes module name and file" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      error = %RuntimeError{message: "boom"}

      module = %ExUnit.TestModule{
        name: MyApp.FailingModuleTest,
        file: "test/failing_module_test.exs",
        state: {:failed, [{:error, error, []}]},
        tags: %{}
      }

      GenServer.cast(pid, {:module_finished, module})
      state = GenServer.call(pid, :get_state)

      [encoded] = state.modules
      assert encoded.name == "MyApp.FailingModuleTest"
      assert encoded.file == "test/failing_module_test.exs"
    end
  end

  describe "handle_cast unknown events" do
    test "ignores :test_started event" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:test_started, %{}})
      state = GenServer.call(pid, :get_state)

      # Should not crash, state unchanged
      assert state.tests == []
    end

    test "ignores :case_started event" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:case_started, %{}})
      state = GenServer.call(pid, :get_state)

      assert state.tests == []
    end

    test "ignores :sigquit event" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:sigquit, []})
      state = GenServer.call(pid, :get_state)

      assert state.tests == []
    end

    test "ignores completely unknown event" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:completely_unknown, :random, :data})
      state = GenServer.call(pid, :get_state)

      assert state.tests == []
    end
  end

  describe "handle_cast {:suite_finished, times_us}" do
    # Helper to run formatter with file output and read JSON result
    defp run_formatter_to_file(setup_fn) do
      output_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(1_000_000)}.json")
      Application.put_env(:ex_unit_json, :opts, output: output_file)
      {:ok, pid} = Formatter.start_link()

      setup_fn.(pid)

      GenServer.cast(pid, {:suite_finished, %{async: 1000, sync: 500}})
      # Block until cast is processed
      GenServer.call(pid, :get_state)

      {:ok, content} = File.read(output_file)
      File.rm!(output_file)
      :json.decode(content)
    end

    # Helper with custom times_us
    defp run_formatter_to_file(setup_fn, times_us) do
      output_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(1_000_000)}.json")
      Application.put_env(:ex_unit_json, :opts, output: output_file)
      {:ok, pid} = Formatter.start_link()

      setup_fn.(pid)

      GenServer.cast(pid, {:suite_finished, times_us})
      GenServer.call(pid, :get_state)

      {:ok, content} = File.read(output_file)
      File.rm!(output_file)
      :json.decode(content)
    end

    # Helper for options other than file output
    defp run_formatter_with_opts(opts, setup_fn) do
      output_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(1_000_000)}.json")
      merged_opts = Keyword.put(opts, :output, output_file)
      Application.put_env(:ex_unit_json, :opts, merged_opts)
      {:ok, pid} = Formatter.start_link()

      setup_fn.(pid)

      GenServer.cast(pid, {:suite_finished, %{async: 0, sync: 0}})
      GenServer.call(pid, :get_state)

      {:ok, content} = File.read(output_file)
      File.rm!(output_file)
      :json.decode(content)
    end

    test "outputs valid JSON with version and seed" do
      json =
        run_formatter_to_file(fn pid ->
          GenServer.cast(pid, {:suite_started, seed: 12_345})
          GenServer.cast(pid, {:test_finished, build_test(name: :"test passes", state: nil)})
        end)

      assert json["version"] == 1
      assert json["seed"] == 12_345
    end

    test "calculates summary statistics correctly" do
      json =
        run_formatter_to_file(fn pid ->
          GenServer.cast(pid, {:suite_started, seed: 1})
          # 2 passed, 1 failed, 1 skipped, 1 excluded
          GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: nil)})
          GenServer.cast(pid, {:test_finished, build_test(name: :t2, state: nil)})
          GenServer.cast(pid, {:test_finished, build_test(name: :t3, state: {:failed, [{:error, %RuntimeError{}, []}]})})
          GenServer.cast(pid, {:test_finished, build_test(name: :t4, state: {:skipped, "pending"})})
          GenServer.cast(pid, {:test_finished, build_test(name: :t5, state: {:excluded, "tag"})})
        end)

      summary = json["summary"]

      assert summary["total"] == 5
      assert summary["passed"] == 2
      assert summary["failed"] == 1
      assert summary["skipped"] == 1
      assert summary["excluded"] == 1
      assert summary["invalid"] == 0
      assert summary["duration_us"] == 1500
      assert summary["result"] == "failed"
    end

    test "result is 'passed' when no failures" do
      json =
        run_formatter_to_file(
          fn pid ->
            GenServer.cast(pid, {:suite_started, seed: 1})
            GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: nil)})
            GenServer.cast(pid, {:test_finished, build_test(name: :t2, state: {:skipped, "pending"})})
          end,
          %{async: 100, sync: 50}
        )

      assert json["summary"]["result"] == "passed"
    end

    test "sorts tests deterministically by file, line, name" do
      json =
        run_formatter_to_file(
          fn pid ->
            GenServer.cast(pid, {:suite_started, seed: 1})
            # Add tests in random order
            GenServer.cast(pid, {:test_finished, build_test_at(name: :z_test, file: "b.exs", line: 10)})
            GenServer.cast(pid, {:test_finished, build_test_at(name: :a_test, file: "b.exs", line: 10)})
            GenServer.cast(pid, {:test_finished, build_test_at(name: :m_test, file: "a.exs", line: 20)})
            GenServer.cast(pid, {:test_finished, build_test_at(name: :m_test, file: "a.exs", line: 10)})
          end,
          %{async: 0, sync: 0}
        )

      names = Enum.map(json["tests"], & &1["name"])

      # a.exs:10 < a.exs:20 < b.exs:10 (a_test) < b.exs:10 (z_test)
      assert names == ["m_test", "m_test", "a_test", "z_test"]
    end

    test "summary_only omits tests array" do
      json =
        run_formatter_with_opts([summary_only: true], fn pid ->
          GenServer.cast(pid, {:suite_started, seed: 1})
          GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: nil)})
        end)

      assert Map.has_key?(json, "summary")
      refute Map.has_key?(json, "tests")
    end

    test "failures_only filters to failed tests" do
      json =
        run_formatter_with_opts([failures_only: true], fn pid ->
          GenServer.cast(pid, {:suite_started, seed: 1})
          GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: nil)})
          GenServer.cast(pid, {:test_finished, build_test(name: :t2, state: {:failed, [{:error, %RuntimeError{}, []}]})})
          GenServer.cast(pid, {:test_finished, build_test(name: :t3, state: nil)})
        end)

      # Summary includes all tests
      assert json["summary"]["total"] == 3
      assert json["summary"]["passed"] == 2
      assert json["summary"]["failed"] == 1

      # Tests array only has failures
      assert length(json["tests"]) == 1
      assert hd(json["tests"])["name"] == "t2"
    end

    test "empty test suite produces valid output" do
      json =
        run_formatter_to_file(
          fn pid ->
            GenServer.cast(pid, {:suite_started, seed: 99})
          end,
          %{async: 0, sync: 0}
        )

      assert json["summary"]["total"] == 0
      assert json["summary"]["result"] == "passed"
      assert json["tests"] == []
    end

    test "all excluded tests result in 'passed'" do
      json =
        run_formatter_to_file(
          fn pid ->
            GenServer.cast(pid, {:suite_started, seed: 1})
            GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: {:excluded, "tag"})})
            GenServer.cast(pid, {:test_finished, build_test(name: :t2, state: {:excluded, "tag"})})
          end,
          %{async: 0, sync: 0}
        )

      assert json["summary"]["result"] == "passed"
      assert json["summary"]["excluded"] == 2
    end

    test "includes module_failures when present" do
      json =
        run_formatter_to_file(
          fn pid ->
            GenServer.cast(pid, {:suite_started, seed: 1})
            GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: nil)})

            error = %RuntimeError{message: "setup_all failed"}

            module = %ExUnit.TestModule{
              name: FailingSetup.Test,
              file: "test/failing_test.exs",
              state: {:failed, [{:error, error, []}]},
              tags: %{}
            }

            GenServer.cast(pid, {:module_finished, module})
          end,
          %{async: 0, sync: 0}
        )

      assert Map.has_key?(json, "module_failures")
      assert length(json["module_failures"]) == 1
      assert hd(json["module_failures"])["name"] == "FailingSetup.Test"
    end

    test "writes to specified output file" do
      output_file = Path.join(System.tmp_dir!(), "explicit_test_output_#{:rand.uniform(100_000)}.json")
      Application.put_env(:ex_unit_json, :opts, output: output_file)
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:suite_started, seed: 42})
      GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: nil)})
      GenServer.cast(pid, {:suite_finished, %{async: 100, sync: 50}})
      GenServer.call(pid, :get_state)

      assert File.exists?(output_file)

      {:ok, content} = File.read(output_file)
      json = :json.decode(content)
      assert json["seed"] == 42

      File.rm!(output_file)
    end

    test "outputs to stdout when no output file specified" do
      # This tests that the code path works, though we can't easily capture stdout
      # from a GenServer. We verify by checking no error is raised.
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      GenServer.cast(pid, {:suite_started, seed: 1})
      GenServer.cast(pid, {:test_finished, build_test(name: :t1, state: nil)})
      GenServer.cast(pid, {:suite_finished, %{async: 0, sync: 0}})

      # If we get here without crash, stdout output worked
      state = GenServer.call(pid, :get_state)
      assert state.seed == 1
    end
  end

  describe "integration: full event sequence" do
    test "handles complete test suite lifecycle" do
      Application.put_env(:ex_unit_json, :opts, [])
      {:ok, pid} = Formatter.start_link()

      # 1. Suite starts
      GenServer.cast(pid, {:suite_started, seed: 54_321, max_cases: 4})

      # 2. Tests run and finish
      test1 = build_test(name: :"test one passes", state: nil, time: 100)
      test2 = build_test(name: :"test two passes", state: nil, time: 200)

      error = %ExUnit.AssertionError{
        message: "Expected 1, got 2",
        left: 1,
        right: 2,
        expr: quote(do: 1 == 2)
      }

      test3 = build_test(name: :"test three fails", state: {:failed, [{:error, error, []}]}, time: 300)
      test4 = build_test(name: :"test four skipped", state: {:skipped, "pending"}, time: 0)

      GenServer.cast(pid, {:test_finished, test1})
      GenServer.cast(pid, {:test_finished, test2})
      GenServer.cast(pid, {:test_finished, test3})
      GenServer.cast(pid, {:test_finished, test4})

      # 3. Module finishes (with a setup_all failure in a different module)
      setup_error = %RuntimeError{message: "setup_all exploded"}

      module = %ExUnit.TestModule{
        name: FailingSetup.Test,
        file: "test/failing_setup_test.exs",
        state: {:failed, [{:error, setup_error, []}]},
        tags: %{}
      }

      GenServer.cast(pid, {:module_finished, module})

      # 4. Suite finishes
      GenServer.cast(pid, {:suite_finished, %{async: 1000, sync: 500}})

      # Verify final state
      state = GenServer.call(pid, :get_state)

      # Check seed was captured
      assert state.seed == 54_321

      # Check all tests accumulated
      assert length(state.tests) == 4

      # Tests are prepended for O(1) insertion; Task 5 reverses for final output
      test_names = Enum.map(state.tests, & &1.name)
      assert test_names == ["test four skipped", "test three fails", "test two passes", "test one passes"]

      # Check states
      test_states = Enum.map(state.tests, & &1.state)
      assert test_states == ["skipped", "failed", "passed", "passed"]

      # Check module failure was tracked
      assert length(state.modules) == 1
      [mod] = state.modules
      assert mod.name == "FailingSetup.Test"
      assert mod.state == "failed"
    end
  end

  # Helper to build ExUnit.Test structs for testing
  defp build_test(opts) do
    name = Keyword.get(opts, :name, :"test example")
    module = Keyword.get(opts, :module, __MODULE__.FakeTest)
    state = Keyword.get(opts, :state, nil)
    time = Keyword.get(opts, :time, 1000)

    tags = %{
      file: "test/fake_test.exs",
      line: 10,
      module: module,
      test: name,
      test_type: :test,
      async: false,
      registered: %{}
    }

    %ExUnit.Test{
      name: name,
      module: module,
      state: state,
      time: time,
      tags: tags,
      logs: ""
    }
  end

  # Helper to build ExUnit.TestModule structs for testing
  defp build_module(opts) do
    name = Keyword.get(opts, :name, __MODULE__.FakeModule)
    state = Keyword.get(opts, :state, nil)

    %ExUnit.TestModule{
      name: name,
      file: "test/fake_module_test.exs",
      state: state,
      tags: %{}
    }
  end

  # Helper to build ExUnit.Test with custom file/line for sorting tests
  defp build_test_at(opts) do
    name = Keyword.get(opts, :name, :test_example)
    file = Keyword.get(opts, :file, "test/fake_test.exs")
    line = Keyword.get(opts, :line, 10)
    state = Keyword.get(opts, :state, nil)

    tags = %{
      file: file,
      line: line,
      module: __MODULE__.FakeTest,
      test: name,
      test_type: :test,
      async: false,
      registered: %{}
    }

    %ExUnit.Test{
      name: name,
      module: __MODULE__.FakeTest,
      state: state,
      time: 100,
      tags: tags,
      logs: ""
    }
  end
end
