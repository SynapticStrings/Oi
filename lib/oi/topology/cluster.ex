defmodule Oi.Topology.Cluster do
  @moduledoc """
  Cluster dependencies based on user selections and dependency relationships at the front end
  to achieve parallel control.

  i.e., isolate resource-intensive services and convert the entire parallel task into a
  serial + parallel process.
  """

  alias Oi.Topology.Graph.{Node, Edge}

  @type cluster_name :: atom() | String.t() | [cluster_name()]

  @type t :: %__MODULE__{
          node_colors: %{Node.id() => cluster_name()},
          merge_groups: [{cluster_name() | MapSet.t(cluster_name()), cluster_name()}]
        }
  defstruct node_colors: %{},
            merge_groups: []

  @spec paint_graph([Node.t()], MapSet.t(Edge.t()), Oi.Topology.Cluster.t()) ::
          %{Node.id() => cluster_name()}
  @doc "Return `%{node_name => final_cluster_name}`"
  def paint_graph(sorted_nodes, edges, %__MODULE__{} = clusters) do
    Enum.reduce(sorted_nodes, %{}, fn node_id, color_map ->
      explicit_color =
        case Map.get(clusters.node_colors, node_id) do
          nil -> get_upstream_colors(node_id, edges, color_map)
          explicit_color -> explicit_color
        end

      Map.put(color_map, node_id, explicit_color)
    end)
    # normalize clusters
    |> Enum.map(fn {k, v} ->
      {k,
       case v do
         v when is_list(v) -> Enum.sort(v)
         v -> v
       end}
    end)
    |> Enum.into(%{})
  end

  defp get_upstream_colors(node_id, edges, color_map) do
    upstream =
      edges
      |> Enum.filter(fn e -> e.to_node == node_id end)
      |> Enum.map(fn e -> Map.get(color_map, e.from_node, :default_cluster) end)
      |> List.flatten()
      |> Enum.uniq()

    case upstream do
      [] -> :default_cluster
      [single] -> single
      multiple -> multiple
    end
  end
end
