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

  ## Output shape (additive to schema v1)

  The merged document is run 1's document with:

    * `tests` — flaky entries removed (passing/confirmed entries preserved, so
      `--all` runs keep their passing tests)
    * `module_failures` — only the recurring (confirmed) ones, omitted if none
    * `flaky` — flaky tests and modules, omitted when empty
    * `summary.failed` — confirmed test count; `summary.flaky` — flaky count;
      `summary.result` — `"passed"` iff nothing is confirmed
    * `retry` — `%{"ran" => true, "passes" => 1, "retried" => N, "confirmed" => X, "flaky" => Y}`

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
    run2_passed_ids = passed_ids(run2)

    {flaky_tests, kept_tests} =
      Enum.split_with(run1_tests, fn test ->
        failed?(test) and id(test) in run2_passed_ids
      end)

    {confirmed_mods, flaky_mods} = classify_modules(run1, run2)

    flaky = flaky_tests ++ Enum.map(flaky_mods, &Map.put(&1, "scope", "module"))
    confirmed_test_count = count_failed(kept_tests)
    confirmed_count = confirmed_test_count + length(confirmed_mods)
    retried = count_failed(run1_tests) + length(Map.get(run1, "module_failures", []))

    run1
    |> Map.put("tests", kept_tests)
    |> put_or_drop("module_failures", confirmed_mods)
    |> put_or_drop("flaky", flaky)
    |> Map.put("summary", merge_summary(run1, confirmed_test_count, length(flaky), confirmed_count))
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
  @spec count_failed([map()]) :: non_neg_integer()
  defp count_failed(tests), do: Enum.count(tests, &failed?/1)

  @doc false
  # Ids of tests that passed in run 2 (the re-run subset).
  @spec passed_ids(document()) :: MapSet.t()
  defp passed_ids(run2) do
    run2
    |> Map.get("tests", [])
    |> Enum.filter(&(Map.get(&1, "state") == "passed"))
    |> MapSet.new(&id/1)
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
  # Builds the merged summary: confirmed failures stay in `failed`, healed ones
  # surface in `flaky`, result goes green only when nothing is confirmed.
  @spec merge_summary(document(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: map()
  defp merge_summary(run1, confirmed_test_count, flaky_count, confirmed_count) do
    result = if confirmed_count == 0, do: "passed", else: "failed"

    summary =
      run1
      |> Map.get("summary", %{})
      |> Map.put("failed", confirmed_test_count)
      |> Map.put("flaky", flaky_count)
      |> Map.put("result", result)

    # When everything healed, any run-1 `invalid` count (from a setup_all that
    # has since recovered) is stale — passing means nothing invalid remains.
    if result == "passed", do: Map.put(summary, "invalid", 0), else: summary
  end

  @doc false
  # Sets a key to a non-empty list, or removes it when the list is empty
  # (matches the formatter's omit-when-empty convention for module_failures/flaky).
  @spec put_or_drop(map(), String.t(), [term()]) :: map()
  defp put_or_drop(doc, key, []), do: Map.delete(doc, key)
  defp put_or_drop(doc, key, list), do: Map.put(doc, key, list)
end
