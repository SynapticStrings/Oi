defmodule Oi.Workspace do
  @moduledoc """
  Pure data container for a single computation unit.

  A Workspace holds the resolved graph (projected by the upstream editor),
  cluster declaration, interventions, and the products of compilation and
  dispatch. It is a plain struct — no process, no state machine.

  ## Lifecycle

      workspace = Oi.Workspace.new("svs-1", graph, cluster, interventions)
      {:ok, workspace} = Oi.compile(workspace)
      {:ok, workspace} = Oi.dispatch(workspace, executor: Oi.Executor.Sync)
      results = workspace.drafting

  """

  alias Oi.Topology.{Graph, Cluster}
  alias Oi.Compiler.RecipeBundle
  alias Oi.Workspace.{Planning, Drafting}

  @type id :: String.t() | atom()

  @type t :: %__MODULE__{
          id: id(),
          graph: Graph.t(Orchid.Step.implementation()),
          cluster: Cluster.t(),
          interventions: RecipeBundle.interventions_map(),
          plan: Planning.Plan.t() | nil,
          drafting: Drafting.t() | nil
        }

  defstruct [
    :id,
    :graph,
    :cluster,
    :interventions,
    :plan,
    :drafting
  ]

  @spec new(
          id(),
          Graph.t(Orchid.Step.implementation()),
          Cluster.t(),
          RecipeBundle.interventions_map()
        ) :: t()
  def new(id, graph, cluster \\ %Cluster{}, interventions \\ %{}) do
    %__MODULE__{
      id: id,
      graph: graph,
      cluster: cluster,
      interventions: interventions
    }
  end
end
