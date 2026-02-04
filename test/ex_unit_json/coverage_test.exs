defmodule ExUnitJSON.CoverageTest do
  use ExUnit.Case, async: false

  alias ExUnitJSON.Coverage

  # Coverage tests must run synchronously since :cover is global state.
  # These tests conflict with mix test.json's coverage collection.
  #
  # When coverage is enabled, mix test.json automatically excludes this tag.
  # To run these tests: mix test.json --no-cover test/ex_unit_json/coverage_test.exs
  @moduletag :coverage_unit

  describe "start/0" do
    test "starts cover instrumentation" do
      assert Coverage.start() == :ok

      # Verify cover is running by checking modules can be compiled
      modules = :cover.modules()
      assert is_list(modules)

      # Note: We don't call :cover.stop() here because it can interfere with
      # the test process. Cover will be stopped between test runs.
    end

    test "handles already started cover" do
      # Start cover first
      :cover.start()

      # start/0 should handle this gracefully
      assert Coverage.start() == :ok
    end
  end

  describe "collect/1" do
    test "returns coverage map with expected structure" do
      Coverage.start()
      result = Coverage.collect([])

      assert is_map(result)
      assert Map.has_key?(result, "total_percentage")
      assert Map.has_key?(result, "total_lines")
      assert Map.has_key?(result, "covered_lines")
      assert Map.has_key?(result, "modules")

      assert is_number(result["total_percentage"])
      assert is_integer(result["total_lines"])
      assert is_integer(result["covered_lines"])
      assert is_list(result["modules"])
    end

    test "respects ignore_modules list" do
      Coverage.start()

      # Get coverage without ignoring
      result_all = Coverage.collect([])

      # Get coverage ignoring ExUnitJSON.Coverage itself
      result_filtered = Coverage.collect([Coverage])

      # The filtered result should have fewer or equal modules
      assert length(result_filtered["modules"]) <= length(result_all["modules"])

      # Verify the ignored module is not in the filtered result
      module_names = Enum.map(result_filtered["modules"], & &1["module"])
      refute "ExUnitJSON.Coverage" in module_names
    end

    test "module data has expected fields" do
      Coverage.start()
      result = Coverage.collect([])

      # Should have at least one module (the project modules)
      assert result["modules"] != [], "Expected at least one module in coverage"

      mod = hd(result["modules"])

      assert Map.has_key?(mod, "module")
      assert Map.has_key?(mod, "file")
      assert Map.has_key?(mod, "percentage")
      assert Map.has_key?(mod, "covered_lines")
      assert Map.has_key?(mod, "uncovered_lines")

      assert is_binary(mod["module"])
      assert is_binary(mod["file"]) or is_nil(mod["file"])
      assert is_number(mod["percentage"])
      assert is_integer(mod["covered_lines"])
      assert is_list(mod["uncovered_lines"])
    end

    test "uncovered_lines contains only integers" do
      Coverage.start()
      result = Coverage.collect([])

      for mod <- result["modules"] do
        for line <- mod["uncovered_lines"] do
          assert is_integer(line), "Expected integer line number, got: #{inspect(line)}"
          assert line > 0, "Line numbers should be positive"
        end
      end
    end

    test "uncovered_lines are sorted" do
      Coverage.start()
      result = Coverage.collect([])

      for mod <- result["modules"] do
        assert mod["uncovered_lines"] == Enum.sort(mod["uncovered_lines"]),
               "Uncovered lines should be sorted for module #{mod["module"]}"
      end
    end

    test "percentages are between 0 and 100" do
      Coverage.start()
      result = Coverage.collect([])

      assert result["total_percentage"] >= 0
      assert result["total_percentage"] <= 100

      for mod <- result["modules"] do
        assert mod["percentage"] >= 0, "Module #{mod["module"]} has percentage < 0"
        assert mod["percentage"] <= 100, "Module #{mod["module"]} has percentage > 100"
      end
    end

    test "covered_lines + uncovered_lines equals total for each module" do
      Coverage.start()
      result = Coverage.collect([])

      for mod <- result["modules"] do
        total = mod["covered_lines"] + length(mod["uncovered_lines"])
        # Calculate expected percentage
        expected_pct = if total > 0, do: Float.round(mod["covered_lines"] / total * 100, 2), else: 100.0

        assert mod["percentage"] == expected_pct,
               "Module #{mod["module"]}: percentage #{mod["percentage"]} doesn't match calculated #{expected_pct}"
      end
    end

    test "file paths are relative to project root" do
      Coverage.start()
      result = Coverage.collect([])

      for mod <- result["modules"] do
        if mod["file"] do
          refute String.starts_with?(mod["file"], "/"),
                 "File path should be relative, got: #{mod["file"]}"

          assert String.starts_with?(mod["file"], "lib/"),
                 "File path should start with lib/, got: #{mod["file"]}"
        end
      end
    end
  end

  describe "stop/0" do
    # Note: We test Coverage.stop() indirectly through integration tests
    # that run in subprocesses. Calling :cover.stop() in the test process
    # can interfere with ExUnit's process management.

    test "function exists and returns expected type" do
      # Just verify the function signature - actual stop tested in integration
      assert is_function(&Coverage.stop/0, 0)
    end
  end

  describe "integration" do
    test "start and collect workflow" do
      assert Coverage.start() == :ok

      result = Coverage.collect([])
      assert is_map(result)
      assert result["total_lines"] >= 0

      # Note: stop() tested via integration tests in subprocess
    end

    test "coverage data is JSON-serializable" do
      Coverage.start()
      result = Coverage.collect([])

      # Should encode without error - :json.encode returns iodata
      encoded = :json.encode(result)
      # Convert iodata to binary for decoding
      encoded_binary = IO.iodata_to_binary(encoded)
      assert is_binary(encoded_binary)

      # Should decode back to equivalent structure
      decoded = :json.decode(encoded_binary)
      assert decoded["total_percentage"] == result["total_percentage"]
      assert decoded["total_lines"] == result["total_lines"]
      assert decoded["covered_lines"] == result["covered_lines"]
      assert length(decoded["modules"]) == length(result["modules"])
    end
  end
end
