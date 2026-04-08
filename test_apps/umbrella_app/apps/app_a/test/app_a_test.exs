defmodule AppATest do
  use ExUnit.Case

  test "app_a hello" do
    assert AppA.hello() == :world_a
  end

  test "app_a math" do
    assert 1 + 1 == 2
  end

  test "app_a truth" do
    assert true
  end
end
