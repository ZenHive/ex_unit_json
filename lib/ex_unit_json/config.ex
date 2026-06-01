defmodule ExUnitJSON.Config do
  @moduledoc """
  Centralized configuration handling for ExUnitJSON.

  Provides option parsing, validation, and retrieval. Options are stored
  in Application environment during test runs (single-instance, so this
  is acceptable).

  ## Options

    * `:summary_only` - When true, omit individual test results
    * `:failures_only` - When true, include only failed tests
    * `:first_failure` - When true, include only the first failed test
    * `:filter_out` - List of patterns to mark matching failures as filtered
    * `:output` - File path to write JSON output (default: stdout)
    * `:compact` - When true, output JSONL with minimal fields
    * `:group_by_error` - When true, add error_groups array grouping failures by message
    * `:quiet` - When true, suppress Logger output for clean JSON
    * `:hint` - Controls the "use --failed" tip behavior
    * `:retry` - When false (via `--no-retry`), disable auto-retry of failed tests

  """

  @typedoc "Valid option keys for ExUnitJSON configuration"
  @type option ::
          :summary_only
          | :failures_only
          | :first_failure
          | :filter_out
          | :output
          | :compact
          | :group_by_error
          | :quiet
          | :hint
          | :retry

  @typedoc "Keyword list of ExUnitJSON options"
  @type opts :: [
          summary_only: boolean(),
          failures_only: boolean(),
          first_failure: boolean(),
          filter_out: [String.t()],
          output: String.t() | nil,
          compact: boolean(),
          group_by_error: boolean(),
          quiet: boolean(),
          hint: boolean(),
          retry: boolean()
        ]

  @valid_options [
    :summary_only,
    :failures_only,
    :first_failure,
    :filter_out,
    :output,
    :compact,
    :group_by_error,
    :quiet,
    :hint,
    :retry
  ]

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

  Returns true by default (AI-optimized output). Use `--all` flag to get all tests.
  """
  @spec failures_only?() :: boolean()
  def failures_only? do
    get_opt(:failures_only, true)
  end

  @doc """
  Checks if first-failure mode is enabled.
  """
  @spec first_failure?() :: boolean()
  def first_failure? do
    get_opt(:first_failure, false)
  end

  @doc """
  Gets the list of filter-out patterns.
  """
  @spec filter_out_patterns() :: [String.t()]
  def filter_out_patterns do
    get_opt(:filter_out, [])
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

  @doc """
  Checks if group-by-error mode is enabled.
  """
  @spec group_by_error?() :: boolean()
  def group_by_error? do
    get_opt(:group_by_error, false)
  end

  @doc """
  Checks if automatic retry-on-flaky is enabled via project config.

  Reads `config :ex_unit_json, :retry` directly from the application
  environment (default `true`), mirroring how `:enforce_failed` is read. This
  is a project-level setting evaluated before per-invocation `:opts` are stored,
  so it deliberately does not consult `get_opts/0`. The `--no-retry` flag is
  honored separately as a per-invocation opt by `Mix.Tasks.Test.Json`.
  """
  @spec retry?() :: boolean()
  def retry? do
    Application.get_env(:ex_unit_json, :retry, true)
  end

  @doc false
  # Validates and filters options to only known keys
  defp validate_opts(opts) when is_list(opts) do
    Keyword.take(opts, @valid_options)
  end

  defp validate_opts(_), do: []
end
