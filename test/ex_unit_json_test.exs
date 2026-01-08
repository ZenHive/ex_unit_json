defmodule ExUnitJSONTest do
  use ExUnit.Case

  describe "module structure" do
    test "ExUnitJSON module exists" do
      assert Code.ensure_loaded?(ExUnitJSON)
    end

    test "ExUnitJSON.Formatter module exists" do
      assert Code.ensure_loaded?(ExUnitJSON.Formatter)
    end

    test "ExUnitJSON.JSONEncoder module exists" do
      assert Code.ensure_loaded?(ExUnitJSON.JSONEncoder)
    end

    test "Mix.Tasks.Test.Json module exists" do
      assert Code.ensure_loaded?(Mix.Tasks.Test.Json)
    end
  end
end
