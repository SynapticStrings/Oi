defmodule Oi.Compiler.RecipeBundle do
  @moduledoc """
  Container for a compiled Orchid recipe and its associated metadata.

  A RecipeBundle is the static output of `Oi.Compiler.compile/3` — it pairs
  an `Orchid.Recipe` with the boundary information (requires/exports) and
  the interventions bound to the nodes within this cluster.
  """

  alias Oi.Topology.Graph

  @type id :: String.t() | atom()

  @type t :: %__MODULE__{
          recipe: Orchid.Recipe.t(),
          requires: [Orchid.Step.io_key()],
          exports: [Orchid.Step.io_key()],
          node_ids: [Graph.Node.id()],
          interventions: interventions_map()
        }

  @type interventions_map :: %{
          Graph.PortRef.t() => {intervention_type :: atom(), payload :: term()}
        }

  defstruct [
    :recipe,
    requires: [],
    exports: [],
    node_ids: [],
    interventions: %{}
  ]

  @doc """
  Bind interventions to static recipe bundles, filtering by node membership.

  Only interventions whose target node belongs to a bundle's `node_ids`
  are attached to that bundle.
  """
  @spec bind_interventions([t()], interventions_map()) :: [t()]
  def bind_interventions(static_bundles, interventions_map) do
    Enum.map(static_bundles, fn %{node_ids: node_ids} = bundle ->
      filtered =
        Map.filter(interventions_map, fn {{:port, target_node, _}, _} ->
          target_node in node_ids
        end)

      %{bundle | interventions: filtered}
    end)
  end
end
