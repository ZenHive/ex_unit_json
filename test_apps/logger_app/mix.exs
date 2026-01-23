defmodule LoggerApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :logger_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: ["test.json": :test]]
  end

  defp deps do
    [
      {:ex_unit_json, path: "../.."}
    ]
  end
end
