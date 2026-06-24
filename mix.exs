defmodule Oi.MixProject do
  use Mix.Project

  def project do
    [
      app: :oi,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [
        ignore_modules: [
          ~r/.*Test.*/,
          # For other module, while complete.
          ]
        ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Oi.Application, []}
    ]
  end

  defp deps do
    [
      {:orchid, "~> 0.6"},
      {:orchid_symbiont, "~> 0.2"},
      {:orchid_intervention, "~> 0.1"}
    ]
  end
end
