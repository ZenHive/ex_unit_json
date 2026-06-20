# Reach architecture policy — drives `mix reach.check --arch --smells`.
# ExUnitJSON is a small library; the meaningful split is pure-core vs effectful.
[
  layers: [
    # Pure data transforms — no IO, no process/ETS/:cover side effects.
    core: [
      "ExUnitJSON.JSONEncoder",
      "ExUnitJSON.Filters",
      "ExUnitJSON.ErrorGroups",
      "ExUnitJSON.CompactOutput",
      "ExUnitJSON.Config"
    ],
    # Side-effecting boundary — IO, Logger, :cover, :trace, ETS, subprocess.
    runtime: [
      "ExUnitJSON.Formatter",
      "ExUnitJSON.Coverage",
      "ExUnitJSON.Trace",
      "ExUnitJSON.Trace.*",
      "Mix.Tasks.Test.Json"
    ]
  ],
  # The pure core must not depend on the effectful runtime layer.
  deps: [forbidden: [{:core, :runtime}]],
  smells: [
    fixed_shape_map: [min_keys: 3, min_occurrences: 3, evidence_limit: 10],
    behaviour_candidate: [min_modules: 3, min_callbacks: 3]
  ]
]
