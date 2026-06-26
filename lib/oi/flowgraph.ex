defmodule Oi.Flowgraph do
  alias Oi.Topology.Graph

  # ---- Functional API ----

  defguard belongs_port(key) when is_atom(key) or is_binary(key)

  defdelegate new_flowchart, to: Oi.Topology.Graph, as: :new

  @spec add_step(Graph.t(), module(), keyword()) :: Graph.t()
  def add_step(%Graph{} = graph, oi_step, opts \\ []) do
    with true <- function_exported?(oi_step, :__node_spec__, 0) do
      node = struct(Graph.Node, oi_step.__node_spec__())

      node_alias = Keyword.get(opts, :as, node.id)
      node_options = Keyword.get(opts, :opts, [])

      Graph.add_node(graph, %{node | id: node_alias, options: node_options})
    else
      _ -> graph
    end
  end

  # add_step!(graph, oi_step, opts)

  defdelegate remove_step(graph, node_id), to: Oi.Topology.Graph, as: :remove_node

  def connect(%Graph{} = graph, {from_node, from_port}, {to_node, to_port}) when belongs_port(from_node) and belongs_port(from_port) and belongs_port(to_node) and belongs_port(to_port) do
    Graph.add_edge(graph, Graph.Edge.new(from_node, from_port, to_node, to_port))
  end
end
