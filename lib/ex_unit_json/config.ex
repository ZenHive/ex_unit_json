defmodule ExUnitJSON.Config do
  @moduledoc """
  Centralized configuration handling for ExUnitJSON.

  Provides option parsing, validation, and retrieval. Options are stored
  in Application environment during test runs (single-instance, so this
  is acceptable).

  ## Options

    * `:summary_only` - When true, omit individual test results
    * `:failures_only` - When true, include only failed tests
    * `:output` - File path to write JSON output (default: stdout)
    * `:compact` - When true, output JSONL with minimal fields

  """

  @typedoc "Valid option keys for ExUnitJSON configuration"
  @type option :: :summary_only | :failures_only | :output | :compact

  @typedoc "Keyword list of ExUnitJSON options"
  @type opts :: [
          summary_only: boolean(),
          failures_only: boolean(),
          output: String.t() | nil,
          compact: boolean()
        ]

  @valid_options [:summary_only, :failures_only, :output, :compact]

  @doc """
  Gets options from Application environment.

  Returns validated options, filtering out any invalid keys.

  ## Examples

      Application.put_env(:ex_unit_json, :opts, summary_only: true)
      ExUnitJSON.Config.get_opts()
      #=> [summary_only: true]

      Application.put_env(:ex_unit_json, :opts, invalid_key: "ignored")
      ExUnitJSON.Config.get_opts()
      #=> []

  """
  @spec get_opts() :: opts()
  def get_opts do
    :ex_unit_json
    |> Application.get_env(:opts, [])
    |> validate_opts()
  end

  @doc """
  Gets a specific option value.

  ## Examples

      Application.put_env(:ex_unit_json, :opts, summary_only: true)
      ExUnitJSON.Config.get_opt(:summary_only)
      #=> true

      Application.put_env(:ex_unit_json, :opts, [])
      ExUnitJSON.Config.get_opt(:summary_only, false)
      #=> false

  """
  @spec get_opt(option(), any()) :: any()
  def get_opt(key, default \\ nil) when key in @valid_options do
    Keyword.get(get_opts(), key, default)
  end

  @doc """
  Checks if summary-only mode is enabled.
  """
  @spec summary_only?() :: boolean()
  def summary_only? do
    get_opt(:summary_only, false)
  end

  @doc """
  Checks if failures-only mode is enabled.
  """
  @spec failures_only?() :: boolean()
  def failures_only? do
    get_opt(:failures_only, false)
  end

  @doc """
  Gets the output file path, or nil for stdout.
  """
  @spec output_path() :: String.t() | nil
  def output_path do
    get_opt(:output)
  end

  @doc """
  Checks if compact mode is enabled.
  """
  @spec compact?() :: boolean()
  def compact? do
    get_opt(:compact, false)
  end

  @doc false
  # Validates and filters options to only known keys
  defp validate_opts(opts) when is_list(opts) do
    Keyword.take(opts, @valid_options)
  end

  defp validate_opts(_), do: []
end
