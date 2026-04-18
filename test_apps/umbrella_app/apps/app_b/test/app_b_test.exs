defmodule AppBTest do
  use ExUnit.Case

  test "app_b hello" do
    assert AppB.hello() == :world_b
  end

  test "app_b math" do
    assert 2 + 2 == 4
  end
end
