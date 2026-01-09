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
end
