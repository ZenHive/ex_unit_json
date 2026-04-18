defmodule UmbrellaApp.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
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
