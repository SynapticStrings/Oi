defmodule Oi.MixProject do
  use Mix.Project

  @version "0.6.3"

  def project do
    [
      app: :oi,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"],
        groups_for_modules: [
          Core: [Oi, Oi.Compiled, Oi.Result],
          DSL: [Oi.Flowgraph, Oi.Step],
          Compile: [Oi.Compile.Bundle, Oi.Compile.Planning],
          Dispatch: [
            Oi.Dispatch.Config,
            Oi.Dispatch.Drafting,
            Oi.Dispatch.Orchestrator,
            Oi.Dispatch.Worker
          ],
          Topology: [
            Oi.Topology.Cluster,
            Oi.Topology.Graph,
            Oi.Topology.Graph.Node,
            Oi.Topology.Graph.Edge,
            Oi.Topology.Graph.PortRef
          ],
          Executors: [Oi.Executor, Oi.Executor.Sync, Oi.Executor.TaskSup],
          Adapters: [Oi.Adapters],
          Runtime: [
            Oi.Runtime.Session,
            Oi.Runtime.Session.Instances,
            Oi.Runtime.Registry
          ]
        ]
      ],
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
      # Orchid related.
      {:orchid, "~> 0.6"},
      {:orchid_symbiont, "~> 0.2", optional: true},
      {:orchid_intervention, "~> 0.2", optional: true},
      {:orchid_stratum, "~> 0.2", optional: true},

      # Package
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
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
