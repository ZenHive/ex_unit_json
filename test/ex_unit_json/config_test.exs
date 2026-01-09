defmodule ExUnitJSON.ConfigTest do
  use ExUnit.Case, async: false

  alias ExUnitJSON.Config

  # Store original config to restore after each test
  setup do
    original = Application.get_env(:ex_unit_json, :opts)
    on_exit(fn -> Application.put_env(:ex_unit_json, :opts, original) end)
    :ok
  end

  describe "get_opts/0" do
    test "returns empty list when no options configured" do
      Application.delete_env(:ex_unit_json, :opts)
      assert Config.get_opts() == []
    end

    test "returns configured options" do
      Application.put_env(:ex_unit_json, :opts, summary_only: true, failures_only: true)
      opts = Config.get_opts()

      assert Keyword.get(opts, :summary_only) == true
      assert Keyword.get(opts, :failures_only) == true
    end

    test "filters out invalid option keys" do
      Application.put_env(:ex_unit_json, :opts,
        summary_only: true,
        invalid_key: "should be filtered",
        another_bad: 123
      )

      opts = Config.get_opts()

      assert Keyword.get(opts, :summary_only) == true
      refute Keyword.has_key?(opts, :invalid_key)
      refute Keyword.has_key?(opts, :another_bad)
    end

    test "handles non-list config gracefully" do
      Application.put_env(:ex_unit_json, :opts, "not a list")
      assert Config.get_opts() == []
    end

    test "handles nil config" do
      Application.put_env(:ex_unit_json, :opts, nil)
      assert Config.get_opts() == []
    end
  end

  describe "get_opt/2" do
    test "returns option value when set" do
      Application.put_env(:ex_unit_json, :opts, summary_only: true)
      assert Config.get_opt(:summary_only) == true
    end

    test "returns default when option not set" do
      Application.put_env(:ex_unit_json, :opts, [])
      assert Config.get_opt(:summary_only, false) == false
    end

    test "returns nil as default when not specified" do
      Application.put_env(:ex_unit_json, :opts, [])
      assert Config.get_opt(:output) == nil
    end
  end

  describe "summary_only?/0" do
    test "returns true when summary_only is enabled" do
      Application.put_env(:ex_unit_json, :opts, summary_only: true)
      assert Config.summary_only?() == true
    end

    test "returns false when summary_only is disabled" do
      Application.put_env(:ex_unit_json, :opts, summary_only: false)
      assert Config.summary_only?() == false
    end

    test "returns false when summary_only is not set" do
      Application.put_env(:ex_unit_json, :opts, [])
      assert Config.summary_only?() == false
    end
  end

  describe "failures_only?/0" do
    test "returns true when failures_only is enabled" do
      Application.put_env(:ex_unit_json, :opts, failures_only: true)
      assert Config.failures_only?() == true
    end

    test "returns false when failures_only is disabled" do
      Application.put_env(:ex_unit_json, :opts, failures_only: false)
      assert Config.failures_only?() == false
    end

    test "returns false when failures_only is not set" do
      Application.put_env(:ex_unit_json, :opts, [])
      assert Config.failures_only?() == false
    end
  end

  describe "output_path/0" do
    test "returns file path when output is set" do
      Application.put_env(:ex_unit_json, :opts, output: "/tmp/results.json")
      assert Config.output_path() == "/tmp/results.json"
    end

    test "returns nil when output is not set" do
      Application.put_env(:ex_unit_json, :opts, [])
      assert Config.output_path() == nil
    end
  end

  describe "compact?/0" do
    test "returns true when compact is enabled" do
      Application.put_env(:ex_unit_json, :opts, compact: true)
      assert Config.compact?() == true
    end

    test "returns false when compact is disabled" do
      Application.put_env(:ex_unit_json, :opts, compact: false)
      assert Config.compact?() == false
    end

    test "returns false when compact is not set" do
      Application.put_env(:ex_unit_json, :opts, [])
      assert Config.compact?() == false
    end
  end
end
