defmodule Oi.Compiler.RecipeBundle do
  @moduledoc """
  Container for a compiled Orchid recipe and its associated metadata.

  A RecipeBundle is the static output of `Oi.Compiler.compile_graph/2` — it pairs
  an `Orchid.Recipe` with the boundary information (requires/exports) and
  the interventions bound to the nodes within this cluster.
  """

  alias Oi.Topology.Graph

  @type id :: String.t() | atom()

  @type t :: %__MODULE__{
          recipe: Orchid.Recipe.t(),
          requires: [Orchid.Step.io_key()],
          exports: [Orchid.Step.io_key()],
          inputs: [Orchid.Step.io_key()],
          node_ids: [Graph.Node.id()],
        }

  defstruct [
    :recipe,
    requires: [],
    exports: [],
    inputs: [],
    node_ids: []
  ]

end
