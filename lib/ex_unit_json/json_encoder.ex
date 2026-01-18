defmodule ExUnitJSON.JSONEncoder do
  @moduledoc """
  Encodes ExUnit test structures to JSON-serializable maps.

  This module handles the conversion of ExUnit structs (tests, failures,
  stacktraces) into plain maps that can be serialized to JSON using
  Elixir's built-in `:json` module.
  """

  # Truncation limits for large values in assertion errors
  # Kept small to reduce JSON output size for AI agents
  @value_char_limit 500
  @expr_char_limit 200
  @collection_item_limit 50
  @printable_limit 500

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
          tags: map(),
          failures: list(map())
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
      file: make_relative(test.tags[:file]),
      line: test.tags[:line],
      state: encode_state(test.state),
      duration_us: test.time,
      tags: encode_tags(test.tags),
      failures: encode_failure(test.state)
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
  def encode_failure({:failed, failures}) when is_list(failures) do
    Enum.map(failures, &encode_single_failure/1)
  end

  def encode_failure(_state), do: []

  @doc false
  # Encodes a single failure tuple {kind, error, stacktrace}
  defp encode_single_failure({kind, error, stacktrace}) do
    base = %{
      kind: encode_failure_kind(kind, error),
      message: format_error_message(error),
      stacktrace: encode_stacktrace(stacktrace)
    }

    maybe_add_assertion(base, error)
  end

  @doc false
  # Maps failure kind to string, detecting assertion errors
  defp encode_failure_kind(_kind, %ExUnit.AssertionError{}), do: "assertion"
  defp encode_failure_kind(:error, _error), do: "error"
  defp encode_failure_kind(:exit, _error), do: "exit"
  defp encode_failure_kind(:throw, _error), do: "throw"
  defp encode_failure_kind(kind, _error), do: inspect(kind)

  @doc false
  # Safely extracts error message
  defp format_error_message(error) when is_exception(error) do
    Exception.message(error)
  end

  defp format_error_message(error), do: inspect(error)

  @doc false
  # Adds assertion details for ExUnit.AssertionError
  defp maybe_add_assertion(base, %ExUnit.AssertionError{} = error) do
    assertion = %{
      left: truncate_and_inspect(error.left),
      right: truncate_and_inspect(error.right),
      expr: format_expr(error.expr)
    }

    Map.put(base, :assertion, assertion)
  end

  defp maybe_add_assertion(base, _error), do: base

  @doc false
  # Formats assertion expression to string with truncation
  defp format_expr(nil), do: nil

  defp format_expr(expr) do
    str = Macro.to_string(expr)

    if String.length(str) > @expr_char_limit do
      String.slice(str, 0, @expr_char_limit) <> "..."
    else
      str
    end
  end

  @doc false
  # Inspects value with truncation limits for JSON safety
  defp truncate_and_inspect(value) do
    inspected =
      inspect(value,
        limit: @collection_item_limit,
        printable_limit: @printable_limit
      )

    if String.length(inspected) > @value_char_limit do
      String.slice(inspected, 0, @value_char_limit) <> "..."
    else
      inspected
    end
  end

  @doc """
  Encodes a stacktrace to a list of frame maps.

  Each frame contains file, line, and optionally module, function, arity, and app.
  """
  @spec encode_stacktrace(list()) :: list(map())
  def encode_stacktrace(stacktrace) when is_list(stacktrace) do
    Enum.map(stacktrace, &encode_stacktrace_frame/1)
  end

  def encode_stacktrace(_), do: []

  @doc false
  # Encodes a single stacktrace frame
  defp encode_stacktrace_frame({module, function, arity, location}) do
    %{
      module: inspect(module),
      function: to_string(function),
      arity: normalize_arity(arity),
      file: get_location_file(location),
      line: get_location_line(location),
      app: get_app(module)
    }
  end

  defp encode_stacktrace_frame(_) do
    %{module: nil, function: nil, arity: nil, file: nil, line: nil, app: nil}
  end

  @doc false
  # Normalizes arity (can be integer or list of args)
  defp normalize_arity(arity) when is_integer(arity), do: arity
  defp normalize_arity(args) when is_list(args), do: length(args)
  defp normalize_arity(_), do: nil

  @doc false
  # Extracts file from stacktrace location and makes it relative
  defp get_location_file(location) when is_list(location) do
    case Keyword.get(location, :file) do
      nil -> nil
      file -> make_relative(to_string(file))
    end
  end

  defp get_location_file(_), do: nil

  @doc false
  # Extracts line from stacktrace location
  defp get_location_line(location) when is_list(location) do
    Keyword.get(location, :line)
  end

  defp get_location_line(_), do: nil

  @doc false
  # Gets application name for a module
  defp get_app(module) when is_atom(module) do
    case :application.get_application(module) do
      {:ok, app} -> to_string(app)
      :undefined -> nil
    end
  end

  defp get_app(_), do: nil

  @doc false
  # Makes file paths relative to the current working directory.
  # Reduces JSON output size and improves readability for AI agents.
  defp make_relative(nil), do: nil

  defp make_relative(path) when is_binary(path) do
    cwd = File.cwd!()

    if String.starts_with?(path, cwd) do
      path
      |> String.trim_leading(cwd)
      |> String.trim_leading("/")
    else
      path
    end
  end

  defp make_relative(path), do: to_string(path)
end
