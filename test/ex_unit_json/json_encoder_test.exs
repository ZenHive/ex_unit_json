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
end
