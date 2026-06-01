defmodule ExUnitJSON.RetryTest do
  use ExUnit.Case, async: true

  alias ExUnitJSON.Retry

  # Builds a string-keyed test map matching the formatter's decoded output.
  defp test_map(module, name, state, extra \\ %{}) do
    Map.merge(
      %{
        "module" => module,
        "name" => name,
        "state" => state,
        "file" => "test/example_test.exs",
        "line" => 1,
        "failures" => failures_for(state)
      },
      extra
    )
  end

  defp failures_for("failed"), do: [%{"kind" => "assertion", "message" => "boom"}]
  defp failures_for(_), do: []

  # Builds a string-keyed run document.
  defp doc(tests, opts \\ []) do
    failed = Enum.count(tests, &(&1["state"] == "failed"))
    passed = Enum.count(tests, &(&1["state"] == "passed"))

    summary =
      %{
        "total" => length(tests),
        "passed" => passed,
        "failed" => failed,
        "skipped" => 0,
        "excluded" => 0,
        "invalid" => Keyword.get(opts, :invalid, 0),
        "duration_us" => 1234,
        "result" => if(failed > 0 or Keyword.get(opts, :invalid, 0) > 0, do: "failed", else: "passed")
      }

    maybe_put(
      %{"version" => 1, "seed" => 7, "summary" => summary, "tests" => tests},
      "module_failures",
      Keyword.get(opts, :module_failures)
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp module_failure(name) do
    %{
      "name" => name,
      "file" => "test/foo_test.exs",
      "state" => "failed",
      "failures" => [%{"message" => "setup_all boom"}]
    }
  end

  describe "merge/2 — all flaky (heal to green)" do
    test "every run-1 failure passing in run 2 goes green, surfaced as flaky" do
      run1 = doc([test_map("FooTest", "test a", "failed"), test_map("FooTest", "test b", "failed")])
      run2 = doc([test_map("FooTest", "test a", "passed"), test_map("FooTest", "test b", "passed")])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "passed"
      assert merged["summary"]["failed"] == 0
      assert merged["summary"]["flaky"] == 2
      assert merged["tests"] == []
      assert length(merged["flaky"]) == 2
      assert merged["retry"] == %{"ran" => true, "passes" => 1, "retried" => 2, "confirmed" => 0, "flaky" => 2}
    end

    test "flaky entries preserve run-1 failure detail" do
      run1 = doc([test_map("FooTest", "test a", "failed")])
      run2 = doc([test_map("FooTest", "test a", "passed")])

      merged = Retry.merge(run1, run2)

      [flaky] = merged["flaky"]
      assert flaky["name"] == "test a"
      assert flaky["failures"] == [%{"kind" => "assertion", "message" => "boom"}]
    end
  end

  describe "merge/2 — all confirmed (stays red)" do
    test "every run-1 failure failing again stays in tests, no flaky key" do
      run1 = doc([test_map("FooTest", "test a", "failed"), test_map("FooTest", "test b", "failed")])
      run2 = doc([test_map("FooTest", "test a", "failed"), test_map("FooTest", "test b", "failed")])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "failed"
      assert merged["summary"]["failed"] == 2
      assert merged["summary"]["flaky"] == 0
      assert length(merged["tests"]) == 2
      refute Map.has_key?(merged, "flaky")
      assert merged["retry"]["confirmed"] == 2
    end

    test "confirmed failures retain run-1 detail (not run-2)" do
      run1 = doc([test_map("FooTest", "test a", "failed", %{"failures" => [%{"message" => "run1 detail"}]})])
      run2 = doc([test_map("FooTest", "test a", "failed", %{"failures" => [%{"message" => "run2 detail"}]})])

      merged = Retry.merge(run1, run2)

      [confirmed] = merged["tests"]
      assert confirmed["failures"] == [%{"message" => "run1 detail"}]
    end
  end

  describe "merge/2 — mixed" do
    test "one flaky, one confirmed, one not re-verified stays confirmed" do
      run1 =
        doc([
          test_map("FooTest", "heals", "failed"),
          test_map("FooTest", "stays", "failed"),
          test_map("FooTest", "not_rerun", "failed")
        ])

      # run 2 only re-ran two of them: one healed, one still failing.
      run2 = doc([test_map("FooTest", "heals", "passed"), test_map("FooTest", "stays", "failed")])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "failed"
      assert merged["summary"]["failed"] == 2
      assert merged["summary"]["flaky"] == 1

      flaky_names = Enum.map(merged["flaky"], & &1["name"])
      assert flaky_names == ["heals"]

      confirmed_names = merged["tests"] |> Enum.map(& &1["name"]) |> Enum.sort()
      assert confirmed_names == ["not_rerun", "stays"]
    end
  end

  describe "merge/2 — {module, name} matching" do
    test "same test name in different modules is matched independently" do
      run1 = doc([test_map("ATest", "same name", "failed"), test_map("BTest", "same name", "failed")])
      # Only A's heals; B still fails.
      run2 = doc([test_map("ATest", "same name", "passed"), test_map("BTest", "same name", "failed")])

      merged = Retry.merge(run1, run2)

      assert Enum.map(merged["flaky"], & &1["module"]) == ["ATest"]
      assert Enum.map(merged["tests"], & &1["module"]) == ["BTest"]
    end
  end

  describe "merge/2 — --all preserves passing tests" do
    test "passing tests survive the merge; only flaky failures are removed" do
      run1 =
        doc([
          test_map("FooTest", "passer", "passed"),
          test_map("FooTest", "flaker", "failed"),
          test_map("FooTest", "real", "failed")
        ])

      run2 = doc([test_map("FooTest", "flaker", "passed"), test_map("FooTest", "real", "failed")])

      merged = Retry.merge(run1, run2)

      names = merged["tests"] |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == ["passer", "real"]
      assert Enum.map(merged["flaky"], & &1["name"]) == ["flaker"]
    end
  end

  describe "merge/2 — module failures (setup_all)" do
    test "a cleared setup_all failure becomes a flaky module" do
      run1 = doc([], module_failures: [module_failure("FlakyModuleTest")])
      run2 = doc([])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "passed"
      refute Map.has_key?(merged, "module_failures")
      [flaky] = merged["flaky"]
      assert flaky["name"] == "FlakyModuleTest"
      assert flaky["scope"] == "module"
      assert merged["retry"]["confirmed"] == 0
      assert merged["retry"]["flaky"] == 1
    end

    test "a recurring setup_all failure stays confirmed" do
      run1 = doc([], module_failures: [module_failure("RealModuleTest")], invalid: 2)
      run2 = doc([], module_failures: [module_failure("RealModuleTest")])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "failed"
      assert merged["summary"]["invalid"] == 2
      assert merged["module_failures"] == [module_failure("RealModuleTest")]
      refute Map.has_key?(merged, "flaky")
      assert merged["retry"]["confirmed"] == 1
    end

    test "healed module clears the stale invalid count" do
      run1 = doc([], module_failures: [module_failure("FlakyModuleTest")], invalid: 3)
      run2 = doc([])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["invalid"] == 0
    end
  end

  describe "merge/2 — invalid tests (setup_all casualties)" do
    test "--all: healed invalid tests are replaced with their run-2 passing entries" do
      # Codex-bot-flagged scenario (PR #2): run 1 setup_all fails, tests are
      # invalid (visible with --all); run 2 heals → no stale invalid entries
      # may survive in a green document.
      run1 =
        doc(
          [test_map("FlakyModuleTest", "test a", "invalid"), test_map("FlakyModuleTest", "test b", "invalid")],
          module_failures: [module_failure("FlakyModuleTest")],
          invalid: 2
        )

      run2 = doc([test_map("FlakyModuleTest", "test a", "passed"), test_map("FlakyModuleTest", "test b", "passed")])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "passed"
      assert merged["summary"]["invalid"] == 0
      assert merged["summary"]["failed"] == 0
      assert Enum.map(merged["tests"], & &1["state"]) == ["passed", "passed"]
      refute Map.has_key?(merged, "module_failures")
      assert [%{"scope" => "module"}] = merged["flaky"]
    end

    test "--all: healed invalid tests move from invalid into passed counts" do
      run1 =
        doc(
          [test_map("FlakyModuleTest", "test a", "invalid")],
          module_failures: [module_failure("FlakyModuleTest")],
          invalid: 1
        )

      run2 = doc([test_map("FlakyModuleTest", "test a", "passed")])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["passed"] == 1
      assert merged["summary"]["invalid"] == 0
    end

    test "--all: invalid test that fails on retry becomes a confirmed failure" do
      run1 =
        doc(
          [test_map("FlakyModuleTest", "test a", "invalid")],
          module_failures: [module_failure("FlakyModuleTest")],
          invalid: 1
        )

      # setup_all healed, but the test fails on its own in run 2.
      run2 = doc([test_map("FlakyModuleTest", "test a", "failed", %{"failures" => [%{"message" => "run2 detail"}]})])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "failed"
      assert merged["summary"]["failed"] == 1
      assert merged["summary"]["invalid"] == 0
      [confirmed] = merged["tests"]
      assert confirmed["state"] == "failed"
      assert confirmed["failures"] == [%{"message" => "run2 detail"}]
    end

    test "failures-only: run-2 failures from a healed setup_all are surfaced, heals counted" do
      # Default output hides invalid tests: run 1's array is empty even though
      # the setup_all failure invalidated 2 tests.
      run1 = doc([], module_failures: [module_failure("FlakyModuleTest")], invalid: 2)

      # Run 2 (--failed --all): setup_all healed; one test passes, one fails.
      run2 =
        doc([
          test_map("FlakyModuleTest", "test a", "passed"),
          test_map("FlakyModuleTest", "test b", "failed")
        ])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "failed"
      assert merged["summary"]["failed"] == 1
      assert merged["summary"]["invalid"] == 0
      assert merged["summary"]["passed"] == 1
      assert [%{"name" => "test b", "state" => "failed"}] = merged["tests"]
    end

    test "partial heal: healed module's invalid count clears even when an unrelated failure is confirmed" do
      # Copilot-flagged scenario (PR #2): module A's setup_all heals on retry, but
      # an unrelated test stays confirmed — the stale invalid count must not survive.
      run1 =
        doc(
          [test_map("OtherTest", "stays red", "failed")],
          module_failures: [module_failure("FlakyModuleTest")],
          invalid: 3
        )

      run2 =
        doc([
          test_map("OtherTest", "stays red", "failed"),
          test_map("FlakyModuleTest", "test a", "passed"),
          test_map("FlakyModuleTest", "test b", "passed"),
          test_map("FlakyModuleTest", "test c", "passed")
        ])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "failed"
      assert merged["summary"]["failed"] == 1
      assert merged["summary"]["invalid"] == 0
      assert merged["summary"]["passed"] == 3
      assert [%{"scope" => "module"}] = merged["flaky"]
    end

    test "recurring setup_all failure keeps its invalid tests and count" do
      run1 =
        doc(
          [test_map("RealModuleTest", "test a", "invalid")],
          module_failures: [module_failure("RealModuleTest")],
          invalid: 1
        )

      # Run 2: setup_all fails again — test stays invalid.
      run2 =
        doc(
          [test_map("RealModuleTest", "test a", "invalid")],
          module_failures: [module_failure("RealModuleTest")],
          invalid: 1
        )

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "failed"
      assert merged["summary"]["invalid"] == 1
      assert [%{"state" => "invalid"}] = merged["tests"]
      assert merged["module_failures"] == [module_failure("RealModuleTest")]
    end

    test "retried count includes invalid tests and module failures" do
      run1 =
        doc(
          [test_map("FooTest", "fails", "failed"), test_map("FlakyModuleTest", "casualty", "invalid")],
          module_failures: [module_failure("FlakyModuleTest")],
          invalid: 1
        )

      run2 = doc([test_map("FooTest", "fails", "passed"), test_map("FlakyModuleTest", "casualty", "passed")])

      merged = Retry.merge(run1, run2)

      # 1 failed test + 1 invalid test + 1 module failure re-run
      assert merged["retry"]["retried"] == 3
    end
  end

  describe "merge/2 — preserves baseline document fields" do
    test "version, seed, and untouched summary counts carry through" do
      run1 = doc([test_map("FooTest", "a", "failed")])
      run2 = doc([test_map("FooTest", "a", "passed")])

      merged = Retry.merge(run1, run2)

      assert merged["version"] == 1
      assert merged["seed"] == 7
      assert merged["summary"]["total"] == 1
      assert merged["summary"]["duration_us"] == 1234
    end

    test "empty run (no failures) yields a green, retry-tagged document" do
      run1 = doc([])
      run2 = doc([])

      merged = Retry.merge(run1, run2)

      assert merged["summary"]["result"] == "passed"
      assert merged["tests"] == []
      refute Map.has_key?(merged, "flaky")
      assert merged["retry"] == %{"ran" => true, "passes" => 1, "retried" => 0, "confirmed" => 0, "flaky" => 0}
    end
  end
end
