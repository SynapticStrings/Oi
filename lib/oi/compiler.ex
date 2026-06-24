defmodule Oi.Compiler do
  @moduledoc """
  Compiles a pure structural graph into Orchid RecipeBundles.

  Two-phase compilation:

  1. `compile_graph/2` — pure topology: topological sort + cluster paint
     + recipe construction. Produces *static* bundles without interventions.
     Result is reusable across different intervention sets.

  2. `bind/2` — attaches interventions to static bundles, filtered by node
     membership. Cheap; can be called repeatedly with different interventions.
  """

  alias Oi.Topology.{Graph, Cluster}
  alias Oi.Topology.Graph.PortRef
  alias Oi.Compiler.RecipeBundle

  @doc """
  Phase 1: Compile graph + cluster into static RecipeBundles (no interventions).

  Reusable across different intervention sets.
  """
  @spec compile_graph(Graph.t(Orchid.Step.implementation()), Cluster.t()) ::
          {:error, :cycle_detected} | {:ok, [RecipeBundle.t()]}
  def compile_graph(graph, cluster_decl \\ %Cluster{}) do
    with {:ok, sorted_node_ids} <- Graph.topological_sort(graph) do
      node_colors = Cluster.paint_graph(sorted_node_ids, graph.edges, cluster_decl)

      bundles =
        sorted_node_ids
        |> Enum.group_by(&Map.get(node_colors, &1, :default_cluster))
        |> Enum.map(fn {_cluster_name, node_ids} ->
          build_bundle(node_ids, graph)
        end)

      {:ok, bundles}
    end
  end

  @doc """
  Phase 2: Bind interventions to static bundles.

  Thin wrapper around `RecipeBundle.bind_interventions/2`.
  """
  @spec bind([RecipeBundle.t()], RecipeBundle.interventions_map()) :: [RecipeBundle.t()]
  def bind(static_bundles, interventions) do
    RecipeBundle.bind_interventions(static_bundles, interventions)
  end

  # --- Phase 1 internals ---

  defp build_bundle(node_ids, graph) do
    steps =
      node_ids
      |> Enum.map(&Map.fetch!(graph.nodes, &1))
      |> Enum.map(&node_to_step(&1, graph))

    {requires, exports} = calculate_boundaries(node_ids, graph)
    inputs = (requires -- exports)

    %RecipeBundle{
      recipe: Orchid.Recipe.new(steps),
      requires: requires,
      exports: exports,
      inputs: inputs,
      node_ids: node_ids
    }
  end

  defp node_to_step(%Graph.Node{} = node, graph) do
    in_edges = Graph.get_in_edges(graph, node.id)

    step_inputs =
      Enum.map(node.inputs, fn port_name ->
        case Enum.find(in_edges, &(&1.to_port == port_name)) do
          nil -> PortRef.to_orchid_key({:port, node.id, port_name})
          edge -> PortRef.to_orchid_key({:port, edge.from_node, edge.from_port})
        end
      end)
      |> case do
        [single] -> single
        other -> other
      end

    step_outputs =
      Enum.map(node.outputs, fn p -> PortRef.to_orchid_key({:port, node.id, p}) end)
      |> case do
        [single] -> single
        other -> other
      end

    {node.container, step_inputs, step_outputs, node.options}
  end

  defp calculate_boundaries(node_ids_in_cluster, graph) do
    cluster_nodes_set = MapSet.new(node_ids_in_cluster)

    external_edges =
      graph.edges
      |> Enum.reject(&(&1.from_node in cluster_nodes_set and &1.to_node in cluster_nodes_set))

    in_keys =
      external_edges
      |> Enum.filter(&(&1.to_node in cluster_nodes_set))
      |> Enum.map(&PortRef.to_orchid_key({:port, &1.from_node, &1.from_port}))

    out_keys =
      external_edges
      |> Enum.filter(&(&1.from_node in cluster_nodes_set))
      |> Enum.map(&PortRef.to_orchid_key({:port, &1.from_node, &1.from_port}))

    dangling_inputs = Enum.flat_map(node_ids_in_cluster, &get_dangling_port(&1, graph, :inputs))
    dangling_outputs = Enum.flat_map(node_ids_in_cluster, &get_dangling_port(&1, graph, :outputs))

    {Enum.uniq(in_keys ++ dangling_inputs), Enum.uniq(out_keys ++ dangling_outputs)}
  end

  defp get_dangling_port(node_id, graph, direction) do
    node = graph.nodes[node_id]

    ports = if direction == :outputs, do: node.outputs, else: node.inputs
    match_field = if direction == :outputs, do: :from_port, else: :to_port
    group_func = if direction == :outputs, do: & &1.from_node, else: & &1.to_node

    edges =
      graph.edges
      |> Enum.group_by(group_func)
      |> Map.get(node_id, [])

    ports
    |> Enum.reject(fn port -> Enum.any?(edges, &(Map.get(&1, match_field) == port)) end)
    |> Enum.map(fn port -> PortRef.to_orchid_key({:port, node.id, port}) end)
  end
end
