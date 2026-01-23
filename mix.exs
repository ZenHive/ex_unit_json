defmodule ExUnitJSON.MixProject do
  use Mix.Project

  @version "0.2.7"
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
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: ["test.json": :test]
    ]
  end

  defp deps do
    [
      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: :dev}
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4001) end)'"
      ]
    ]
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
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE AGENT.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "AGENT.md"],
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
      # Mix task is tested via integration tests that run in subprocess
      # (System.cmd), so coverage tracking doesn't see it. Exclude from coverage.
      ignore_modules: [Mix.Tasks.Test.Json],
      threshold: 90
    ]
  end
end
