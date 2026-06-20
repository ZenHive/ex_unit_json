defmodule ExUnitJSON.MixProject do
  use Mix.Project

  @version ".version" |> File.read!() |> String.trim()
  @source_url "https://github.com/ZenHive/ex_unit_json"

  def project do
    [
      app: :ex_unit_json,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: test_coverage()
    ]
  end

  def application do
    [
      # :tools provides :cover module for coverage analysis
      extra_applications: [:logger, :tools]
    ]
  end

  def cli do
    [
      preferred_envs: ["test.json": :test, "dialyzer.json": :dev]
    ]
  end

  defp deps do
    [
      # Dev/Test (pinned to current latest)
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.6.0", only: :dev},
      {:bandit, "~> 1.12.0", only: :dev},
      {:styler, "~> 1.11.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: :dev, runtime: false},
      # Analyzer trio (VibeKit baseline)
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4004) end)'"
      ],
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow --skip --exit",
        "doctor",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "dialyzer",
        # test.json guards on MIX_ENV=test; alias steps inherit the top-level
        # (dev) env, so run this step as a subprocess with MIX_ENV=test.
        &test_json_cover/1
      ]
    ]
  end

  defp test_json_cover(_args) do
    {_out, status} =
      System.cmd("mix", ["test.json", "--cover", "--cover-threshold", "90"],
        env: [{"MIX_ENV", "test"}],
        into: IO.stream(:stdio, :line)
      )

    if status != 0, do: Mix.raise("mix test.json failed (exit #{status})")
  end

  defp description do
    """
    AI-friendly JSON test output for ExUnit.
    Provides structured JSON output from mix test for use with AI editors like Claude Code.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs .version mix.exs README.md CHANGELOG.md LICENSE AGENTS.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "AGENTS.md"],
      source_url: @source_url
    ]
  end

  defp dialyzer do
    [
      # Include :mix and :ex_unit in PLT for Mix.Task and ExUnit functions
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp test_coverage do
    [
      # These modules are tested via integration tests that run in subprocesses
      # (System.cmd), so coverage tracking doesn't see their execution.
      ignore_modules: [Mix.Tasks.Test.Json, ExUnitJSON.Coverage],
      threshold: 90
    ]
  end
end
