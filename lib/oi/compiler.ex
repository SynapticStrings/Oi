defmodule Oi.Compiler do
  @moduledoc """
  Compiles a pure structural graph into Orchid RecipeBundles.

  Two-phase compilation:

  1. `compile_graph/2` — pure topology: topological sort + cluster paint
     + recipe construction. Produces *static* bundles without interventions.
     Result is reusable across different intervention sets.

  """

  alias Oi.Topology.{Graph, Cluster}
  alias Oi.Topology.Graph.PortRef
  alias Oi.Compiler.RecipeBundle

  # ---- Phase I: Build RecipeBundle ----

  @doc """
  Compile graph + cluster into static RecipeBundles (no interventions).

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

  # ---- Phase II: Build Plannings ----

  alias Oi.Compiler.Planning.{Plan, Stage}

  @doc """
  Build a Plan from a flat list of RecipeBundles.

  Bundles are grouped by their position in the compiled output.
  Within a single workspace, all bundles form a linear sequence
  (one bundle per cluster). Bundles at the same index across
  different compilations would run in the same stage.

  For a single workspace (one graph → one compile call), each
  bundle is its own stage — they execute sequentially in topo order.
  """
  @spec build([RecipeBundle.t()]) :: {:ok, Plan.t()} | {:error, :cycle_detected}
  def build(bundles) do
    # producer_key => bundle.name
    # producer means its io_key
    producers =
      for b <- bundles, key <- b.exports, into: %{}, do: {key, b.node_ids}

    # bundle.name => [upstream bundle.name]
    deps =
      Map.new(bundles, fn b ->
        upstream =
          b.requires
          |> Enum.flat_map(fn key ->
            case producers[key] do
              # external dependency
              nil -> []

              ids -> [ids]
            end
          end)
          |> Enum.uniq()

        {b.node_ids, upstream}
      end)

    case assign_levels(bundles, deps) do
      {:ok, level_of} -> {:ok, Plan.new(to_stages(bundles, level_of))}
      :error -> {:error, :cycle_detected}
    end
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

  # ---- Phase 2 internals ----

  defp assign_levels(bundles, deps) do
    ids = Enum.map(bundles, & &1.node_ids)
    do_assign(ids, deps, %{}, length(ids))
  end

  # max(fuel) <- num(bundle)
  # fuel < 0 -> has cycle
  defp do_assign(_ids, _deps, _levels, fuel) when fuel < 0, do: :error

  defp do_assign(ids, deps, levels, fuel) do
    {resolved, pending} =
      Enum.split_with(ids, fn id ->
        Enum.all?(deps[id], &Map.has_key?(levels, &1))
      end)

    cond do
      resolved == [] and pending != [] -> :error
      pending == [] -> {:ok, merge_levels(resolved, deps, levels)}
      true -> do_assign(pending, deps, merge_levels(resolved, deps, levels), fuel - 1)
    end
  end

  defp merge_levels(resolved, deps, levels) do
    Enum.reduce(resolved, levels, fn id, acc ->
      level =
        deps[id]
        |> Enum.map(&Map.fetch!(acc, &1))
        |> Enum.max(fn -> -1 end)
        |> Kernel.+(1)

      Map.put(acc, id, level)
    end)
  end

  defp to_stages(bundles, level_of) do
    bundles
    |> Enum.group_by(fn b -> level_of[b.node_ids] end)
    |> Enum.sort_by(fn {level, _} -> level end)
    |> Enum.map(fn {level, bs} -> %Stage{index: level, tasks: bs} end)
  end
end
