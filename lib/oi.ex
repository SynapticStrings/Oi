defmodule Oi do
  @doc_header """
  Oi means Orchid integration.
  """

  @external_resource readme = Path.join([__DIR__, "../README.md"])
  @doc_main readme
            |> File.read!()
            |> String.split("<!-- MDOC -->")
            |> Enum.fetch!(1)

  @moduledoc @doc_header <> @doc_main

  @type name :: String.t()

  alias Oi.Workspace
  alias Oi.{Compiler} #, Dispatcher, Configurator}
  alias Oi.Workspace.{Planning} #, Drafting}

  @doc """
  Compile a workspace's graph into a plan.

  Pure function: fills `workspace.plan` with a `Planning.Plan`.
  Does not touch `drafting`.
  """
  @spec compile(Workspace.t()) :: {:ok, Workspace.t()} | {:error, :cycle_detected}
  def compile(%Workspace{} = ws) do
    case Compiler.compile(ws.graph, ws.cluster, ws.interventions) do
      {:ok, bundles} ->
        {:ok, plan} = Planning.build(bundles)
        {:ok, %{ws | plan: plan}}

      {:error, _} = err ->
        err
    end
  end
end
