defmodule ExUnitJSON.Retry do
  @moduledoc """
  Merges a first test run with an automatic retry run to distinguish
  *flaky* failures from *confirmed* ones.

  `mix test.json` re-runs the previously-failed tests (ExUnit's native
  `--failed`) after a run with failures, then calls `merge/2` to overlay the
  two result documents. The goal is to never block an AI agent on a failure
  that heals on re-run, while never hiding a failure that doesn't.

  ## Classification

  Tests are matched across runs by their `{module, name}` identity (ExUnit's
  canonical manifest key — `file:line` can shift between runs).

    * **confirmed** — failed run 1 and did *not* pass run 2. Stays in `tests`
      and keeps run 1's failure detail. Counts toward `summary.failed`.
    * **flaky** — failed run 1 but passed run 2. Moved out of `tests` into a
      top-level `flaky` array (run 1's failure detail preserved so the agent
      sees what flaked). Counted in `summary.flaky`, never in `summary.failed`.

  A test that failed run 1 but was not re-verified as passing (e.g. `--failed`
  could not re-run it) stays **confirmed** — conservative by design: nothing is
  marked flaky we could not observe passing.

  `setup_all` failures (`module_failures`) are classified the same way by module
  name: recurs in run 2 → stays confirmed; cleared → moves to `flaky` tagged
  `"scope" => "module"`.

  ## Invalid tests (setup_all casualties)

  When a `setup_all` fails, ExUnit marks the module's tests `"invalid"`. ExUnit's
  failure manifest records invalid tests like failures, so the retry re-runs them.
  The merge resolves each run-1 invalid test against its run-2 state:

    * passed run 2 → **healed**: replaced by its run-2 (passing) entry, moved
      from `summary.invalid` into `summary.passed`.
    * failed run 2 → **confirmed failure**: replaced by its run-2 entry (run-2
      failure detail). Counts toward `summary.failed`.
    * still invalid / not re-run → stays as-is; its recurring module failure
      keeps the run red.

  In failures-only output (the default), run-1 invalid tests are not present in
  `tests`. Run-2 failures of those tests are surfaced into `tests` so a real
  failure is never hidden, and `summary.invalid` goes to zero only when no
  module failure recurred (invalid tests cannot outlive their `setup_all`
  failure).

  ## Output shape (additive to schema v1)

  The merged document is run 1's document with:

    * `tests` — flaky entries removed; healed/re-failed invalid entries replaced
      by their run-2 selves (passing/confirmed entries preserved, so `--all`
      runs keep their passing tests)
    * `module_failures` — only the recurring (confirmed) ones, omitted if none
    * `flaky` — flaky tests and modules, omitted when empty
    * `summary.failed` — confirmed test count; `summary.flaky` — flaky count;
      `summary.passed` / `summary.invalid` — adjusted for healed invalid tests;
      `summary.result` — `"passed"` iff nothing is confirmed and nothing is
      still invalid
    * `retry` — `%{"ran" => true, "passes" => 1, "retried" => N, "confirmed" => X, "flaky" => Y}`
      where `retried` counts the failed tests, invalid tests, and failed modules
      that were re-run

  All functions are pure — the orchestration (subprocess spawn, file IO, exit
  code) lives in `Mix.Tasks.Test.Json`.
  """

  @typedoc "A decoded (string-keyed) JSON result document."
  @type document :: %{optional(String.t()) => term()}

  @doc """
  Merges run 1 and run 2 result documents into a single document distinguishing
  confirmed failures from flaky ones.

  Both arguments are string-keyed maps (as produced by `:json.decode/1` on a
  buffered run). Run 2 is expected to have been produced with `--all` so every
  re-run test carries its `"state"`.
  """
  @spec merge(document(), document()) :: document()
  def merge(run1, run2) do
    run1_tests = Map.get(run1, "tests", [])
    run2_tests = Map.get(run2, "tests", [])
    run2_passed_ids = passed_ids(run2)
    run2_by_id = Map.new(run2_tests, &{id(&1), &1})
    run1_ids = MapSet.new(run1_tests, &id/1)

    # Failed run 1, passed run 2 → flaky (moved out of `tests`).
    {flaky_tests, kept_tests} =
      Enum.split_with(run1_tests, fn test ->
        failed?(test) and id(test) in run2_passed_ids
      end)

    # Run-1 invalid entries (setup_all casualties) resolve to their run-2 state.
    {kept_tests, resolved} = resolve_invalid_tests(kept_tests, run2_by_id)

    # Failures-only output hides invalid tests; surface their run-2 failures
    # (and count their run-2 heals) so nothing is hidden.
    surfaced_failures = surfaced_run2_failures(run2_tests, run1_ids)
    invisible_healed = invisible_healed_count(run2_tests, run1_ids)
    kept_tests = merge_surfaced(kept_tests, surfaced_failures)

    {confirmed_mods, flaky_mods} = classify_modules(run1, run2)

    flaky = flaky_tests ++ Enum.map(flaky_mods, &Map.put(&1, "scope", "module"))
    confirmed_test_count = count_failed(kept_tests)
    confirmed_count = confirmed_test_count + length(confirmed_mods)
    run1_invalid = run1 |> Map.get("summary", %{}) |> Map.get("invalid", 0)
    retried = count_failed(run1_tests) + run1_invalid + length(Map.get(run1, "module_failures", []))

    summary =
      merge_summary(run1, %{
        confirmed_test_count: confirmed_test_count,
        confirmed_count: confirmed_count,
        any_confirmed_mods?: confirmed_mods != [],
        flaky_count: length(flaky),
        healed_count: resolved.healed + invisible_healed,
        resolved_count: resolved.healed + resolved.became_failed + invisible_healed + length(surfaced_failures)
      })

    run1
    |> Map.put("tests", kept_tests)
    |> put_or_drop("module_failures", confirmed_mods)
    |> put_or_drop("flaky", flaky)
    |> Map.put("summary", summary)
    |> Map.put("retry", %{
      "ran" => true,
      "passes" => 1,
      "retried" => retried,
      "confirmed" => confirmed_count,
      "flaky" => length(flaky)
    })
  end

  @doc false
  # {module, name} identity used to match tests across runs.
  @spec id(map()) :: {term(), term()}
  defp id(test), do: {Map.get(test, "module"), Map.get(test, "name")}

  @doc false
  @spec failed?(map()) :: boolean()
  defp failed?(test), do: Map.get(test, "state") == "failed"

  @doc false
  @spec passed?(map()) :: boolean()
  defp passed?(test), do: Map.get(test, "state") == "passed"

  @doc false
  @spec invalid?(map()) :: boolean()
  defp invalid?(test), do: Map.get(test, "state") == "invalid"

  @doc false
  @spec count_failed([map()]) :: non_neg_integer()
  defp count_failed(tests), do: Enum.count(tests, &failed?/1)

  @doc false
  # Ids of tests that passed in run 2 (the re-run subset).
  @spec passed_ids(document()) :: MapSet.t()
  defp passed_ids(run2) do
    run2
    |> Map.get("tests", [])
    |> Enum.filter(&passed?/1)
    |> MapSet.new(&id/1)
  end

  @doc false
  # Resolves run-1 invalid entries against run 2: healed → run-2 (passing) entry,
  # re-failed → run-2 (failing) entry, otherwise unchanged (conservative).
  @spec resolve_invalid_tests([map()], map()) ::
          {[map()], %{healed: non_neg_integer(), became_failed: non_neg_integer()}}
  defp resolve_invalid_tests(tests, run2_by_id) do
    Enum.map_reduce(tests, %{healed: 0, became_failed: 0}, fn test, acc ->
      resolve_invalid_test(test, Map.get(run2_by_id, id(test)), acc)
    end)
  end

  @doc false
  @spec resolve_invalid_test(map(), map() | nil, map()) :: {map(), map()}
  defp resolve_invalid_test(test, run2_test, acc) do
    cond do
      not invalid?(test) or is_nil(run2_test) -> {test, acc}
      passed?(run2_test) -> {run2_test, %{acc | healed: acc.healed + 1}}
      failed?(run2_test) -> {run2_test, %{acc | became_failed: acc.became_failed + 1}}
      true -> {test, acc}
    end
  end

  @doc false
  # Run-2 failures whose id run 1's array doesn't contain — setup_all casualties
  # hidden by failures-only output, now failing on their own.
  @spec surfaced_run2_failures([map()], MapSet.t()) :: [map()]
  defp surfaced_run2_failures(run2_tests, run1_ids) do
    Enum.filter(run2_tests, fn test -> failed?(test) and id(test) not in run1_ids end)
  end

  @doc false
  # Run-2 passes whose id run 1's array doesn't contain — healed setup_all
  # casualties hidden by failures-only output.
  @spec invisible_healed_count([map()], MapSet.t()) :: non_neg_integer()
  defp invisible_healed_count(run2_tests, run1_ids) do
    Enum.count(run2_tests, fn test -> passed?(test) and id(test) not in run1_ids end)
  end

  @doc false
  # Appends surfaced run-2 failures, restoring the documented (file, line, name)
  # ordering. No-op when nothing was surfaced.
  @spec merge_surfaced([map()], [map()]) :: [map()]
  defp merge_surfaced(tests, []), do: tests

  defp merge_surfaced(tests, surfaced) do
    Enum.sort_by(tests ++ surfaced, &{Map.get(&1, "file"), Map.get(&1, "line"), Map.get(&1, "name")})
  end

  @doc false
  # Splits run 1 module failures into {confirmed (recurred), flaky (cleared)}
  # by module name.
  @spec classify_modules(document(), document()) :: {[map()], [map()]}
  defp classify_modules(run1, run2) do
    run1_mods = Map.get(run1, "module_failures", [])

    run2_failed_names =
      run2
      |> Map.get("module_failures", [])
      |> MapSet.new(&Map.get(&1, "name"))

    Enum.split_with(run1_mods, &(Map.get(&1, "name") in run2_failed_names))
  end

  @doc false
  # Builds the merged summary. Confirmed failures stay in `failed`, healed ones
  # surface in `flaky`/`passed`. `invalid` reflects what is still invalid: zero
  # when no module failure recurred (invalid tests cannot outlive their
  # setup_all failure), otherwise run 1's count minus what run 2 resolved.
  @spec merge_summary(document(), map()) :: map()
  defp merge_summary(run1, counts) do
    summary = Map.get(run1, "summary", %{})

    invalid =
      if counts.any_confirmed_mods? do
        max(Map.get(summary, "invalid", 0) - counts.resolved_count, 0)
      else
        0
      end

    result = if counts.confirmed_count == 0 and invalid == 0, do: "passed", else: "failed"

    summary
    |> Map.put("failed", counts.confirmed_test_count)
    |> Map.put("flaky", counts.flaky_count)
    |> Map.put("invalid", invalid)
    |> Map.put("result", result)
    |> bump_passed(counts.healed_count)
  end

  @doc false
  # Moves healed invalid tests into the passed count. No-op when nothing healed,
  # so summaries without invalid tests are byte-identical to run 1's.
  @spec bump_passed(map(), non_neg_integer()) :: map()
  defp bump_passed(summary, 0), do: summary
  defp bump_passed(summary, healed), do: Map.update(summary, "passed", healed, &(&1 + healed))

  @doc false
  # Sets a key to a non-empty list, or removes it when the list is empty
  # (matches the formatter's omit-when-empty convention for module_failures/flaky).
  @spec put_or_drop(map(), String.t(), [term()]) :: map()
  defp put_or_drop(doc, key, []), do: Map.delete(doc, key)
  defp put_or_drop(doc, key, list), do: Map.put(doc, key, list)
end
