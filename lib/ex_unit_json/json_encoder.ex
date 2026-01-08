defmodule ExUnitJSON.JSONEncoder do
  @moduledoc """
  Encodes ExUnit test structures to JSON-serializable maps.

  This module handles the conversion of ExUnit structs (tests, failures,
  stacktraces) into plain maps that can be serialized to JSON using
  Elixir's built-in `:json` module.
  """

  @typedoc "An ExUnit test struct"
  @type test :: %ExUnit.Test{}

  @typedoc """
  Test state as returned by ExUnit.

  - `nil` - test passed
  - `{:failed, failures}` - test failed with list of failure tuples
  - `{:skipped, message}` - test was skipped
  - `{:excluded, message}` - test was excluded by filters
  - `{:invalid, module}` - test module is invalid
  """
  @type test_state ::
          nil
          | {:failed, list()}
          | {:skipped, binary()}
          | {:excluded, binary()}
          | {:invalid, module()}

  @doc """
  Encodes an `ExUnit.Test` struct to a JSON-serializable map.

  ## Examples

      test = %ExUnit.Test{name: :"test example", state: nil, time: 1000}
      encode_test(test)
      %{name: "test example", state: "passed", duration_us: 1000, ...}

  """
  @spec encode_test(test()) :: map()
  def encode_test(_test) do
    # TODO: Implement in Task 2
    %{}
  end

  @doc """
  Encodes a test state to a string representation.

  ## State mappings

  - `nil` -> `"passed"`
  - `{:failed, _}` -> `"failed"`
  - `{:skipped, _}` -> `"skipped"`
  - `{:excluded, _}` -> `"excluded"`
  - `{:invalid, _}` -> `"invalid"`
  """
  @spec encode_state(test_state()) :: String.t()
  def encode_state(_state) do
    # TODO: Implement in Task 2
    "passed"
  end

  @doc """
  Encodes test tags, filtering out internal ExUnit keys.
  """
  @spec encode_tags(map()) :: map()
  def encode_tags(_tags) do
    # TODO: Implement in Task 2
    %{}
  end

  @doc """
  Encodes failure details from a failed test.

  Handles assertion errors specially to extract left/right values.
  """
  @spec encode_failure(test_state()) :: list(map())
  def encode_failure(_failure) do
    # TODO: Implement in Task 3
    []
  end
end
