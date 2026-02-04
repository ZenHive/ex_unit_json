defmodule CoverageApp do
  @moduledoc """
  A simple module with functions to test coverage instrumentation.
  """

  @doc "Adds two numbers"
  def add(a, b), do: a + b

  @doc "Multiplies two numbers"
  def multiply(a, b), do: a * b

  @doc "Checks if a number is positive"
  def positive?(n) when n > 0, do: true
  def positive?(_n), do: false

  @doc "Returns a greeting"
  def greet(name), do: "Hello, #{name}!"
end
