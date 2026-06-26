defmodule Oi.MixProject do
  use Mix.Project

  @version "0.5.0"

  def project do
    [
      app: :oi,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      docs: [main: "readme", extras: ["README.md"]],
      description: "Lightweight Orchid integration layer with pluggable execution strategies",
      test_coverage: [
        ignore_modules: [
          ~r/.*Test.*/
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    observer = if Mix.env() == :dev, do: [:observer, :wx], else: []

    [
      extra_applications: [:logger] ++ observer,
      mod: {Oi.Application, []}
    ]
  end

  defp deps do
    [
      {:orchid, "~> 0.6"},
      {:orchid_symbiont, "~> 0.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["awachestnut"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/SynapticStrings/Oi"},
      source_ref: @version,
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md)
    ]
  end
end
