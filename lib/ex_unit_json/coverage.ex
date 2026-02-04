defmodule ExUnitJSON.Coverage do
  @moduledoc """
  Coverage collection for ExUnitJSON.

  Note: Unit tests for this module directly manipulate `:cover` state.
  They work fine with coverage OFF (default) but conflict with `--cover`.
  Run with: `mix test.json test/ex_unit_json/coverage_test.exs`

  Provides functions to start, collect, and stop code coverage analysis
  using Erlang's `:cover` module. Outputs machine-readable coverage data
  that can be merged into JSON test output.

  ## Usage

  Coverage is typically managed by the `mix test.json` task:

      # Coverage off by default (faster)
      mix test.json

      # Enable coverage
      mix test.json --cover

  ## Direct Usage

      ExUnitJSON.Coverage.start()
      # ... run tests ...
      coverage = ExUnitJSON.Coverage.collect()
      ExUnitJSON.Coverage.stop()

  """

  @doc """
  Starts cover instrumentation for local modules.

  Compiles all modules in the project for coverage analysis.
  Uses `:cover.local_only/0` to avoid distributed coverage.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec start() :: :ok | {:error, term()}
  def start do
    # Use local_only mode to avoid distributed coverage issues.
    # Note: local_only() starts the cover server, so start() will return {:already_started}.
    :cover.local_only()

    case :cover.start() do
      {:ok, _pid} ->
        # Fresh start - compile modules for coverage
        compile_project_modules()

      {:error, {:already_started, _pid}} ->
        # Cover is already running. Check if modules need to be compiled.
        # - If modules list is empty, we started it (via local_only) and need to compile
        # - If modules list is not empty, it was started externally with modules already
        #   compiled, so skip to avoid process kills from recompilation
        if :cover.modules() == [] do
          compile_project_modules()
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Collects coverage data from instrumented modules.

  Returns a map with coverage statistics suitable for JSON output.
  Accepts an optional list of module names to ignore.

  ## Options

    * `ignore_modules` - List of modules to exclude from coverage report

  ## Return Value

      %{
        "total_percentage" => 96.96,
        "total_lines" => 330,
        "covered_lines" => 320,
        "modules" => [
          %{
            "module" => "ExUnitJSON.Formatter",
            "file" => "lib/ex_unit_json/formatter.ex",
            "percentage" => 92.68,
            "uncovered_lines" => [45, 67, 89]
          }
        ]
      }

  """
  @spec collect(ignore_modules :: [module()]) :: map()
  def collect(ignore_modules \\ []) do
    modules = :cover.modules()

    # Filter out ignored modules and non-project modules
    project_modules =
      modules
      |> Enum.reject(&(&1 in ignore_modules))
      |> Enum.filter(&project_module?/1)

    module_data =
      project_modules
      |> Enum.map(&collect_module_coverage/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1["module"])

    # Calculate totals
    {total_covered, total_lines} =
      Enum.reduce(module_data, {0, 0}, fn mod, {covered, total} ->
        mod_total = length(mod["uncovered_lines"]) + mod["covered_lines"]
        {covered + mod["covered_lines"], total + mod_total}
      end)

    total_percentage =
      if total_lines > 0 do
        Float.round(total_covered / total_lines * 100, 2)
      else
        100.0
      end

    %{
      "total_percentage" => total_percentage,
      "total_lines" => total_lines,
      "covered_lines" => total_covered,
      "modules" => module_data
    }
  end

  @doc """
  Stops cover and clears all coverage data.

  Call this after collecting coverage to clean up resources.
  Safe to call even if cover is not running.

  Note: :cover.stop() can kill linked processes, so we run it in a
  separate unlinked process to avoid killing the caller.
  """
  @stop_timeout_ms 1000

  @spec stop() :: :ok
  def stop do
    # Run cover.stop in a separate unlinked process to avoid killing the caller.
    # When cover stops, it terminates all cover-compiled modules which can
    # send exit signals to linked processes.
    parent = self()
    ref = make_ref()

    spawn(fn ->
      Process.flag(:trap_exit, true)

      try do
        :cover.stop()
      catch
        :exit, _ -> :ok
      end

      send(parent, {ref, :stopped})
    end)

    # Wait briefly for the stop to complete
    receive do
      {^ref, :stopped} -> :ok
    after
      @stop_timeout_ms -> :ok
    end
  end

  # Private helpers

  @doc false
  # Compiles all project modules for coverage
  @spec compile_project_modules() :: :ok | {:error, term()}
  defp compile_project_modules do
    # Get compile paths from Mix
    compile_path = Mix.Project.compile_path()

    # Find all .beam files
    beam_files =
      compile_path
      |> Path.join("*.beam")
      |> Path.wildcard()

    # Compile each module for coverage
    # Pass the beam file path directly (not module atom) so :cover can find it
    results = Enum.map(beam_files, &:cover.compile_beam(String.to_charlist(&1)))

    # Check for errors
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      :ok
    else
      {:error, {:compile_failed, errors}}
    end
  end

  @doc false
  # Checks if a module belongs to the current project
  @spec project_module?(module()) :: boolean()
  defp project_module?(module) do
    case get_module_source(module) do
      nil ->
        false

      source_path ->
        # Check if source is under lib/ directory of current project
        project_root = File.cwd!()
        lib_path = Path.join(project_root, "lib")
        String.starts_with?(source_path, lib_path)
    end
  end

  @doc false
  # Gets the source file path for a module
  @spec get_module_source(module()) :: String.t() | nil
  defp get_module_source(module) do
    case module.module_info(:compile) do
      compile_info when is_list(compile_info) ->
        case Keyword.get(compile_info, :source) do
          nil -> nil
          source when is_list(source) -> List.to_string(source)
          source when is_binary(source) -> source
        end

      _ ->
        nil
    end
  rescue
    # Module might not be loaded or might not have module_info
    ArgumentError -> nil
    UndefinedFunctionError -> nil
  end

  @doc false
  # Collects coverage data for a single module
  @spec collect_module_coverage(module()) :: map() | nil
  defp collect_module_coverage(module) do
    case :cover.analyse(module, :coverage, :line) do
      {:ok, line_data} ->
        # line_data is [{Module, Line}, {Covered, NotCovered}]
        # Filter out line 0 (module definition/generated code)
        valid_lines =
          line_data
          |> Enum.reject(fn {{_mod, line}, _} -> line == 0 end)
          |> Enum.uniq_by(fn {{_mod, line}, _} -> line end)

        # Separate covered and uncovered
        {covered_count, uncovered_lines} =
          Enum.reduce(valid_lines, {0, []}, &classify_line_coverage/2)

        total_lines = length(valid_lines)
        uncovered_lines = Enum.sort(uncovered_lines)

        percentage =
          if total_lines > 0 do
            Float.round(covered_count / total_lines * 100, 2)
          else
            100.0
          end

        source_file = get_module_source(module)
        relative_file = make_relative_path(source_file)

        %{
          "module" => inspect(module),
          "file" => relative_file,
          "percentage" => percentage,
          "covered_lines" => covered_count,
          "uncovered_lines" => uncovered_lines
        }

      {:error, _reason} ->
        nil
    end
  end

  @doc false
  # Classifies a line as covered or uncovered for the reduce accumulator
  @spec classify_line_coverage({{module(), integer()}, {integer(), integer()}}, {integer(), [integer()]}) ::
          {integer(), [integer()]}
  defp classify_line_coverage({{_mod, line}, {cov, not_cov}}, {covered, uncovered}) do
    cond do
      cov > 0 ->
        {covered + 1, uncovered}

      not_cov > 0 ->
        {covered, [line | uncovered]}

      true ->
        # Line was never executed but also not counted as uncovered
        # This can happen with certain constructs - count as covered
        {covered + 1, uncovered}
    end
  end

  @doc false
  # Makes an absolute path relative to the project root
  @spec make_relative_path(String.t() | nil) :: String.t() | nil
  defp make_relative_path(nil), do: nil

  defp make_relative_path(source_file) do
    project_root = File.cwd!()

    if String.starts_with?(source_file, project_root) do
      String.replace_prefix(source_file, project_root <> "/", "")
    else
      source_file
    end
  end
end
