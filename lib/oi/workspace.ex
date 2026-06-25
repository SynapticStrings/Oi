defmodule Oi.Workspace do
  @moduledoc """
  Pure data container for a single computation unit.

  A Workspace holds the resolved graph (projected by the upstream editor),
  cluster declaration, interventions, and the products of compilation and
  dispatch. It is a plain struct — no process, no state machine.

  ## Lifecycle

      # Phase 1: static compile (topology only, reusable)
      workspace = Oi.Workspace.new("svs-1", graph, cluster)
      {:ok, workspace} = Oi.compile(workspace)

      # Phase 2: dispatch with interventions (can swap interventions)
      {:ok, ws_a} = Oi.dispatch(workspace, interventions: interventions_a)
      {:ok, ws_b} = Oi.dispatch(workspace, interventions: interventions_b)
  """

  alias Oi.Topology.{Graph, Cluster}
  alias Oi.Compiler.RecipeBundle
  alias Oi.Workspace.{Planning, Drafting}

  @type id :: String.t() | atom()

  @type t :: %__MODULE__{
          id: id(),
          graph: Graph.t(Orchid.Step.implementation()),
          cluster: Cluster.t(),
          interventions: map(),
          static_bundles: [RecipeBundle.t()] | nil,
          plan: Planning.Plan.t() | nil,
          drafting: Drafting.t() | nil
        }

  defstruct [
    :id,
    :graph,
    cluster: %Cluster{},
    interventions: %{},
    static_bundles: nil,
    plan: nil,
    drafting: nil
  ]

  @spec new(id(), Graph.t(Orchid.Step.implementation()), Cluster.t(), map()) :: t()
  def new(id, graph, cluster \\ %Cluster{}, interventions \\ %{}) do
    %__MODULE__{
      id: id,
      graph: graph,
      cluster: cluster,
      interventions: interventions
    }
  end
end
