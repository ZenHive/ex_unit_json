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

  @typedoc "JSON-serializable test result map"
  @type encoded_test :: %{
          name: String.t(),
          module: String.t(),
          file: String.t() | nil,
          line: non_neg_integer() | nil,
          state: String.t(),
          duration_us: non_neg_integer(),
          tags: map()
        }

  @doc """
  Encodes an `ExUnit.Test` struct to a JSON-serializable map.

  ## Examples

      test = %ExUnit.Test{name: :"test example", state: nil, time: 1000}
      encode_test(test)
      %{name: "test example", state: "passed", duration_us: 1000, ...}

  """
  @spec encode_test(test()) :: encoded_test()
  def encode_test(%ExUnit.Test{} = test) do
    %{
      name: to_string(test.name),
      module: inspect(test.module),
      file: test.tags[:file],
      line: test.tags[:line],
      state: encode_state(test.state),
      duration_us: test.time,
      tags: encode_tags(test.tags)
    }
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
  def encode_state(nil), do: "passed"
  def encode_state({:failed, _}), do: "failed"
  def encode_state({:skipped, _}), do: "skipped"
  def encode_state({:excluded, _}), do: "excluded"
  def encode_state({:invalid, _}), do: "invalid"

  # Internal ExUnit tag keys to filter out (moved to top-level or metadata)
  @internal_tag_keys [
    :registered,
    :file,
    :line,
    :describe,
    :describe_line,
    :async,
    :module,
    :test,
    :test_type
  ]

  @doc """
  Encodes test tags, filtering out internal ExUnit keys.

  Removes internal ExUnit keys and converts remaining tags to JSON-safe values.
  Keys starting with `:ex_` are also filtered as they are ExUnit internal.
  """
  @spec encode_tags(map()) :: map()
  def encode_tags(tags) when is_map(tags) do
    tags
    |> Enum.reject(&internal_tag?/1)
    |> Map.new(&encode_tag_entry/1)
  end

  def encode_tags(_), do: %{}

  @doc false
  # Checks if a tag entry should be filtered out
  defp internal_tag?({_key, :ex_unit_no_meaningful_value}), do: true
  defp internal_tag?({key, _value}) when key in @internal_tag_keys, do: true

  defp internal_tag?({key, _value}) when is_atom(key) do
    key |> Atom.to_string() |> String.starts_with?("ex_")
  end

  defp internal_tag?(_), do: false

  @doc false
  # Converts a tag key-value pair to JSON-safe format
  defp encode_tag_entry({key, value}) do
    {to_string(key), encode_tag_value(value)}
  end

  @doc false
  # Converts tag values to JSON-serializable format
  # NOTE: is_boolean must come before is_atom since true/false are atoms
  defp encode_tag_value(value) when is_boolean(value), do: value
  defp encode_tag_value(value) when is_atom(value), do: to_string(value)
  defp encode_tag_value(value) when is_binary(value), do: value
  defp encode_tag_value(value) when is_number(value), do: value
  defp encode_tag_value(value) when is_list(value), do: Enum.map(value, &encode_tag_value/1)
  defp encode_tag_value(value) when is_map(value), do: Map.new(value, &encode_tag_entry/1)
  defp encode_tag_value(value), do: inspect(value)

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
