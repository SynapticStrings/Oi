defmodule Oi.MixProject do
  use Mix.Project

  def project do
    [
      app: :oi,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Oi.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:orchid, "~> 0.6"},
      {:orchid_symbiont, "~> 0.2"}
    ]
  end
end
