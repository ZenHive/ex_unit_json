defmodule ExUnitJSONTest do
  use ExUnit.Case

  doctest ExUnitJSON

  test "greets the world" do
    assert ExUnitJSON.hello() == :world
  end
end
