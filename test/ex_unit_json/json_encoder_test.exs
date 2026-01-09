defmodule ExUnitJSON.JSONEncoderTest do
  use ExUnit.Case, async: true

  alias ExUnitJSON.JSONEncoder

  describe "encode_state/1" do
    test "encodes nil as passed" do
      assert JSONEncoder.encode_state(nil) == "passed"
    end

    test "encodes failed state" do
      assert JSONEncoder.encode_state({:failed, []}) == "failed"
    end

    test "encodes skipped state" do
      assert JSONEncoder.encode_state({:skipped, "reason"}) == "skipped"
    end

    test "encodes excluded state" do
      assert JSONEncoder.encode_state({:excluded, "filter"}) == "excluded"
    end

    test "encodes invalid state" do
      assert JSONEncoder.encode_state({:invalid, SomeModule}) == "invalid"
    end
  end

  describe "encode_tags/1" do
    test "returns empty map for empty tags" do
      assert JSONEncoder.encode_tags(%{}) == %{}
    end

    test "keeps user-defined tags" do
      tags = %{slow: true, integration: true}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"slow" => true, "integration" => true}
    end

    test "filters internal ExUnit keys" do
      tags = %{
        file: "test/foo_test.exs",
        line: 10,
        module: MyTest,
        test: :"test example",
        test_type: :test,
        registered: %{},
        async: false,
        describe: "some describe",
        describe_line: 5,
        custom_tag: "keep me"
      }

      result = JSONEncoder.encode_tags(tags)

      assert result == %{"custom_tag" => "keep me"}
    end

    test "filters keys starting with ex_" do
      tags = %{ex_internal: true, ex_something: "value", user_tag: "keep"}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"user_tag" => "keep"}
    end

    test "filters ex_unit_no_meaningful_value marker" do
      tags = %{some_tag: :ex_unit_no_meaningful_value, real_tag: "value"}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"real_tag" => "value"}
    end

    test "converts atom values to strings" do
      tags = %{status: :active}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"status" => "active"}
    end

    test "preserves string values" do
      tags = %{name: "test name"}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"name" => "test name"}
    end

    test "preserves numeric values" do
      tags = %{count: 42, ratio: 3.14}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"count" => 42, "ratio" => 3.14}
    end

    test "preserves boolean values" do
      tags = %{enabled: true, disabled: false}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"enabled" => true, "disabled" => false}
    end

    test "converts list values" do
      tags = %{categories: [:a, :b, :c]}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"categories" => ["a", "b", "c"]}
    end

    test "inspects non-serializable values" do
      pid = self()
      tags = %{process: pid}
      result = JSONEncoder.encode_tags(tags)

      assert result["process"] == inspect(pid)
    end

    test "returns empty map for non-map input" do
      assert JSONEncoder.encode_tags(nil) == %{}
      assert JSONEncoder.encode_tags([]) == %{}
      assert JSONEncoder.encode_tags("string") == %{}
      assert JSONEncoder.encode_tags(123) == %{}
    end

    test "handles nested maps" do
      tags = %{config: %{timeout: 5000, retries: 3}}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"config" => %{"timeout" => 5000, "retries" => 3}}
    end

    test "handles deeply nested lists" do
      tags = %{matrix: [[:a, :b], [:c, :d]]}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{"matrix" => [["a", "b"], ["c", "d"]]}
    end

    test "handles mixed nested structures" do
      tags = %{data: %{items: [:one, :two], meta: %{count: 2}}}
      result = JSONEncoder.encode_tags(tags)

      assert result == %{
               "data" => %{
                 "items" => ["one", "two"],
                 "meta" => %{"count" => 2}
               }
             }
    end

    test "handles non-atom tag keys" do
      # Edge case: tags map with string keys (rare, but possible)
      tags = %{"string_key" => "value", 123 => "number_key"}
      result = JSONEncoder.encode_tags(tags)

      # Non-atom keys should be kept (internal_tag? returns false for them)
      assert result == %{"string_key" => "value", "123" => "number_key"}
    end
  end

  describe "encode_test/1" do
    test "encodes a passed test" do
      test = build_test(state: nil, time: 1234)
      result = JSONEncoder.encode_test(test)

      assert result.name == "test example"
      assert result.module == "ExUnitJSON.JSONEncoderTest.FakeTest"
      assert result.file == "test/fake_test.exs"
      assert result.line == 10
      assert result.state == "passed"
      assert result.duration_us == 1234
      assert is_map(result.tags)
    end

    test "encodes a failed test" do
      test = build_test(state: {:failed, [{:error, %RuntimeError{}, []}]})
      result = JSONEncoder.encode_test(test)

      assert result.state == "failed"
    end

    test "encodes a skipped test" do
      test = build_test(state: {:skipped, "not implemented"})
      result = JSONEncoder.encode_test(test)

      assert result.state == "skipped"
    end

    test "encodes an excluded test" do
      test = build_test(state: {:excluded, "tag filter"})
      result = JSONEncoder.encode_test(test)

      assert result.state == "excluded"
    end

    test "handles Unicode in test names" do
      test = build_test(name: :"test émojis 🎉 and ünïcödë")
      result = JSONEncoder.encode_test(test)

      assert result.name == "test émojis 🎉 and ünïcödë"
    end

    test "handles long module names" do
      test =
        build_test(module: Very.Long.Nested.Module.Name.For.Testing.Purposes.FakeTest)

      result = JSONEncoder.encode_test(test)

      assert result.module ==
               "Very.Long.Nested.Module.Name.For.Testing.Purposes.FakeTest"
    end

    test "includes user-defined tags but filters internal ones" do
      test = build_test(extra_tags: %{slow: true, integration: true})
      result = JSONEncoder.encode_test(test)

      assert result.tags["slow"] == true
      assert result.tags["integration"] == true
      refute Map.has_key?(result.tags, "file")
      refute Map.has_key?(result.tags, "line")
      refute Map.has_key?(result.tags, "module")
    end

    test "output is JSON-serializable" do
      test = build_test()
      result = JSONEncoder.encode_test(test)

      json = JSON.encode!(result)
      assert is_binary(json)
      decoded = JSON.decode!(json)
      assert decoded["name"] == "test example"
      assert decoded["state"] == "passed"
    end

    test "handles nil file in tags" do
      test =
        build_test_with_raw_tags(%{
          file: nil,
          line: 10,
          module: __MODULE__.FakeTest,
          test: :"test nil file",
          test_type: :test
        })

      result = JSONEncoder.encode_test(test)

      assert result.file == nil
    end

    test "handles charlist file path in tags" do
      test =
        build_test_with_raw_tags(%{
          file: ~c"test/charlist_path_test.exs",
          line: 10,
          module: __MODULE__.FakeTest,
          test: :"test charlist file",
          test_type: :test
        })

      result = JSONEncoder.encode_test(test)

      # Charlist should be converted to string
      assert result.file == "test/charlist_path_test.exs"
    end
  end

  describe "encode_failure/1" do
    test "returns empty list for passed test" do
      assert JSONEncoder.encode_failure(nil) == []
    end

    test "returns empty list for skipped test" do
      assert JSONEncoder.encode_failure({:skipped, "reason"}) == []
    end

    test "returns empty list for excluded test" do
      assert JSONEncoder.encode_failure({:excluded, "filter"}) == []
    end

    test "returns empty list for invalid test" do
      assert JSONEncoder.encode_failure({:invalid, SomeModule}) == []
    end

    test "returns empty list for empty failures list" do
      assert JSONEncoder.encode_failure({:failed, []}) == []
    end

    test "encodes assertion error with == comparison" do
      error = %ExUnit.AssertionError{
        message: "Assertion failed",
        left: 1,
        right: 2,
        expr: quote(do: 1 == 2)
      }

      state = {:failed, [{:error, error, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      assert failure.kind == "assertion"
      assert failure.message =~ "Assertion"
      assert failure.assertion.left == "1"
      assert failure.assertion.right == "2"
      assert failure.assertion.expr == "1 == 2"
    end

    test "encodes assertion error with pattern match" do
      error = %ExUnit.AssertionError{
        message: "match (=) failed",
        left: {:ok, :value},
        right: {:error, :fail},
        expr: quote(do: {:ok, _} = {:error, :fail})
      }

      state = {:failed, [{:error, error, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      assert failure.kind == "assertion"
      assert failure.assertion.left == "{:ok, :value}"
      assert failure.assertion.right == "{:error, :fail}"
    end

    test "encodes non-assertion error (raise)" do
      error = %RuntimeError{message: "something went wrong"}
      state = {:failed, [{:error, error, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      assert failure.kind == "error"
      assert failure.message == "something went wrong"
      refute Map.has_key?(failure, :assertion)
    end

    test "encodes exit error" do
      state = {:failed, [{:exit, :normal, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      assert failure.kind == "exit"
      assert failure.message == ":normal"
    end

    test "encodes throw error" do
      state = {:failed, [{:throw, :something, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      assert failure.kind == "throw"
      assert failure.message == ":something"
    end

    test "encodes unknown failure kind as string" do
      state = {:failed, [{:custom_kind, "some value", []}]}
      [failure] = JSONEncoder.encode_failure(state)

      assert failure.kind == "custom_kind"
      assert failure.message == "\"some value\""
    end

    test "handles assertion error with nil expr" do
      error = %ExUnit.AssertionError{
        message: "Assertion failed",
        left: 1,
        right: 2,
        expr: nil
      }

      state = {:failed, [{:error, error, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      assert failure.assertion.expr == nil
    end

    test "truncates very long expression" do
      # Create an expression longer than 200 chars (@expr_char_limit)
      # Build a long expression via nested function calls
      long_expr =
        quote do
          very_long_function_name_that_is_quite_descriptive(
            another_very_long_argument_name_here,
            yet_another_extremely_long_parameter_name,
            one_more_ridiculously_long_variable_name,
            final_unnecessarily_verbose_argument_name
          )
        end

      error = %ExUnit.AssertionError{
        message: "Assertion failed",
        left: 1,
        right: 2,
        expr: long_expr
      }

      state = {:failed, [{:error, error, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      # Should be truncated with "..." appended
      assert String.length(failure.assertion.expr) <= 203
      assert String.ends_with?(failure.assertion.expr, "...")
    end

    test "encodes multiple failures" do
      error1 = %RuntimeError{message: "first error"}
      error2 = %RuntimeError{message: "second error"}
      state = {:failed, [{:error, error1, []}, {:error, error2, []}]}
      failures = JSONEncoder.encode_failure(state)

      assert length(failures) == 2
      assert Enum.at(failures, 0).message == "first error"
      assert Enum.at(failures, 1).message == "second error"
    end

    test "truncates very long assertion values" do
      long_value = String.duplicate("a", 15_000)

      error = %ExUnit.AssertionError{
        message: "Assertion failed",
        left: long_value,
        right: "short",
        expr: quote(do: long == short)
      }

      state = {:failed, [{:error, error, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      # Value should be truncated with "..." appended
      assert String.length(failure.assertion.left) <= 10_003
      assert String.ends_with?(failure.assertion.left, "...")
    end

    test "handles non-serializable values in assertions" do
      pid = self()

      error = %ExUnit.AssertionError{
        message: "Assertion failed",
        left: pid,
        right: :expected,
        expr: quote(do: pid == :expected)
      }

      state = {:failed, [{:error, error, []}]}
      [failure] = JSONEncoder.encode_failure(state)

      # PID should be inspected to string
      assert failure.assertion.left =~ ~r/#PID<[\d.]+>/
    end

    test "output is JSON-serializable" do
      error = %ExUnit.AssertionError{
        message: "Assertion failed",
        left: %{nested: [1, 2, 3]},
        right: %{nested: [4, 5, 6]},
        expr: quote(do: left == right)
      }

      stacktrace = [
        {MyModule, :my_function, 2, [file: ~c"test/my_test.exs", line: 42]}
      ]

      state = {:failed, [{:error, error, stacktrace}]}
      failures = JSONEncoder.encode_failure(state)

      json = JSON.encode!(failures)
      assert is_binary(json)

      decoded = JSON.decode!(json)
      assert is_list(decoded)
      [failure] = decoded
      assert failure["kind"] == "assertion"
    end
  end

  describe "encode_stacktrace/1" do
    test "encodes stacktrace frame with full info" do
      stacktrace = [
        {MyModule, :my_function, 2, [file: ~c"lib/my_module.ex", line: 42]}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)

      assert frame.module == "MyModule"
      assert frame.function == "my_function"
      assert frame.arity == 2
      assert frame.file == "lib/my_module.ex"
      assert frame.line == 42
    end

    test "handles arity as list of arguments" do
      stacktrace = [
        {MyModule, :my_function, [:arg1, :arg2], [file: ~c"lib/my_module.ex", line: 42]}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)
      assert frame.arity == 2
    end

    test "handles invalid arity value" do
      stacktrace = [
        {MyModule, :my_function, "invalid", [file: ~c"lib/my_module.ex", line: 42]}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)
      assert frame.arity == nil
    end

    test "handles missing file/line info" do
      stacktrace = [
        {MyModule, :my_function, 2, []}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)

      assert frame.module == "MyModule"
      assert frame.function == "my_function"
      assert frame.file == nil
      assert frame.line == nil
    end

    test "encodes multiple frames" do
      stacktrace = [
        {ModuleA, :func_a, 1, [file: ~c"a.ex", line: 10]},
        {ModuleB, :func_b, 2, [file: ~c"b.ex", line: 20]},
        {ModuleC, :func_c, 3, [file: ~c"c.ex", line: 30]}
      ]

      frames = JSONEncoder.encode_stacktrace(stacktrace)

      assert length(frames) == 3
      assert Enum.at(frames, 0).module == "ModuleA"
      assert Enum.at(frames, 1).module == "ModuleB"
      assert Enum.at(frames, 2).module == "ModuleC"
    end

    test "returns empty list for non-list input" do
      assert JSONEncoder.encode_stacktrace(nil) == []
      assert JSONEncoder.encode_stacktrace("invalid") == []
    end

    test "handles malformed stacktrace entry" do
      stacktrace = [{:not, :a, :valid, :frame, :extra}]
      [frame] = JSONEncoder.encode_stacktrace(stacktrace)

      # Malformed entries return empty map with nil values for consistency
      assert frame.module == nil
      assert frame.function == nil
      assert frame.arity == nil
      assert frame.file == nil
      assert frame.line == nil
      assert frame.app == nil
    end

    test "handles stacktrace entry with non-list location" do
      # Location is an atom instead of keyword list
      stacktrace = [
        {MyModule, :my_function, 2, :no_location}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)

      assert frame.module == "MyModule"
      assert frame.function == "my_function"
      assert frame.arity == 2
      assert frame.file == nil
      assert frame.line == nil
    end

    test "handles stacktrace entry with nil location" do
      stacktrace = [
        {MyModule, :my_function, 2, nil}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)

      assert frame.module == "MyModule"
      assert frame.file == nil
      assert frame.line == nil
    end

    test "includes app name for known modules" do
      # Kernel is part of :elixir application
      stacktrace = [
        {Kernel, :+, 2, [file: ~c"lib/kernel.ex", line: 1]}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)

      assert frame.module == "Kernel"
      assert frame.app == "elixir"
    end

    test "handles non-atom module in stacktrace" do
      # Edge case: module is not an atom (e.g., a string)
      stacktrace = [
        {"NotAModule", :my_function, 2, [file: ~c"test.ex", line: 1]}
      ]

      [frame] = JSONEncoder.encode_stacktrace(stacktrace)

      # Non-atom module means get_app returns nil
      assert frame.app == nil
    end

    test "output is JSON-serializable" do
      stacktrace = [
        {MyModule, :my_function, 2, [file: ~c"lib/my_module.ex", line: 42]}
      ]

      frames = JSONEncoder.encode_stacktrace(stacktrace)

      json = JSON.encode!(frames)
      assert is_binary(json)

      decoded = JSON.decode!(json)
      [frame] = decoded
      assert frame["module"] == "MyModule"
    end
  end

  # Helper to build ExUnit.Test structs for testing
  defp build_test(opts \\ []) do
    name = Keyword.get(opts, :name, :"test example")
    module = Keyword.get(opts, :module, __MODULE__.FakeTest)
    state = Keyword.get(opts, :state, nil)
    time = Keyword.get(opts, :time, 1000)
    extra_tags = Keyword.get(opts, :extra_tags, %{})

    base_tags = %{
      file: "test/fake_test.exs",
      line: 10,
      module: module,
      test: name,
      test_type: :test,
      async: false,
      registered: %{}
    }

    tags = Map.merge(base_tags, extra_tags)

    %ExUnit.Test{
      name: name,
      module: module,
      state: state,
      time: time,
      tags: tags,
      logs: ""
    }
  end

  # Helper to build ExUnit.Test with raw tags (no merging with defaults)
  defp build_test_with_raw_tags(tags) do
    %ExUnit.Test{
      name: tags[:test] || :"test example",
      module: tags[:module] || __MODULE__.FakeTest,
      state: nil,
      time: 1000,
      tags: tags,
      logs: ""
    }
  end
end
