defmodule CoverageAppTest do
  use ExUnit.Case

  test "add/2 works" do
    assert CoverageApp.add(1, 2) == 3
  end

  test "multiply/2 works" do
    assert CoverageApp.multiply(3, 4) == 12
  end

  test "positive?/1 returns true for positive numbers" do
    assert CoverageApp.positive?(5) == true
  end

  test "positive?/1 returns false for zero and negative" do
    assert CoverageApp.positive?(0) == false
    assert CoverageApp.positive?(-1) == false
  end

  test "greet/1 returns greeting" do
    assert CoverageApp.greet("World") == "Hello, World!"
  end
end
