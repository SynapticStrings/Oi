defmodule Oi.Topology.Graph do
  @moduledoc """
  The pure mathematical representation of the DAG.
  """

  defmodule Node do
    @moduledoc "A pure data representation of a computation step in the DAG."

    @type id :: atom() | String.t()

    @type node_port :: atom() | binary()

    @type t(type) :: %__MODULE__{
            id: id(),
            container: type,
            inputs: [node_port()],
            outputs: [node_port()],
            options: keyword(),
            extra: map()
          }
    @type t() :: t(term())

    defstruct [
      :id,
      :container,
      inputs: [],
      outputs: [],
      options: [],
      extra: %{}
    ]
  end

  defmodule Edge do
    @moduledoc """
    A directed edge representing data flow between two node ports.

    It also serves as the deterministic variable name across the larger system.
    """

    @type t :: %__MODULE__{
            from_node: Node.id(),
            from_port: Node.node_port(),
            to_node: Node.id(),
            to_port: Node.node_port()
          }

    defstruct [:from_node, :from_port, :to_node, :to_port]

    def new(from_node, from_port, to_node, to_port) do
      %__MODULE__{
        from_node: from_node,
        from_port: from_port,
        to_node: to_node,
        to_port: to_port
      }
    end
  end

  defmodule PortRef do
    @moduledoc "A container based on the node/port representation, used to dynamically generate Orchid keys."

    @type t :: {:port, node :: Node.id(), Node.node_port()}

    @spec to_orchid_key(t()) :: Orchid.Step.io_key()
    def to_orchid_key({:port, node, port}) do
      node_part = case node do
        node when is_atom(node) -> Atom.to_string(node)
        node when is_binary(node) -> node
      end

      node_part <> "|" <> parse_port(port)
    end

    defp parse_port(p) when is_binary(p), do: p
    defp parse_port(p) when is_atom(p), do: Atom.to_string(p)
  end

  # May add adjacency lists in future
  # (if graph is REALLY big)
  # in/out edge => %{Node.id() => [Edge.t()]}
  @type t(container_type) :: %__MODULE__{
          nodes: %{Node.id() => Node.t(container_type)},
          edges: MapSet.t(Edge.t()),
          in_edges: %{Node.id() => [Edge.t()]},
          out_edges: %{Node.id() => [Edge.t()]}
        }
  @type t() :: t(term())
  defstruct [:nodes, :edges, :in_edges, :out_edges]

  def new,
    do: %__MODULE__{
      nodes: %{},
      edges: MapSet.new(),
      in_edges: %{},
      out_edges: %{}
    }

  # https://elixirforum.com/t/what-is-a-good-way-to-compare-structs/59303
  def same?(graph1, graph2), do: graph1 == graph2

  def add_node(%__MODULE__{nodes: old_nodes} = graph, %Node{id: node_id} = node) do
    %{
      graph
      | nodes: Map.put(old_nodes, node_id, node),
        in_edges: Map.put_new(graph.in_edges, node_id, []),
        out_edges: Map.put_new(graph.out_edges, node_id, [])
    }
  end

  def remove_node(%__MODULE__{nodes: nodes} = graph, node_id) do
    case nodes[node_id] do
      nil ->
        graph

      _ ->
        in_edges_to_remove = Map.get(graph.in_edges, node_id, [])
        out_edges_to_remove = Map.get(graph.out_edges, node_id, [])
        edges_to_remove = in_edges_to_remove ++ out_edges_to_remove

        new_edges = Enum.reduce(edges_to_remove, graph.edges, &MapSet.delete(&2, &1))

        new_in_edges =
          Enum.reduce(out_edges_to_remove, graph.in_edges, fn edge, acc ->
            Map.update!(acc, edge.to_node, &List.delete(&1, edge))
          end)
          |> Map.delete(node_id)

        new_out_edges =
          Enum.reduce(in_edges_to_remove, graph.out_edges, fn edge, acc ->
            Map.update!(acc, edge.from_node, &List.delete(&1, edge))
          end)
          |> Map.delete(node_id)

        %{
          graph
          | nodes: Map.delete(graph.nodes, node_id),
            edges: new_edges,
            in_edges: new_in_edges,
            out_edges: new_out_edges
        }
    end
  end

  def update_node(%__MODULE__{nodes: nodes} = graph, node_id, new_node) do
    case nodes[node_id] do
      nil ->
        graph

      old_node = %Node{} ->
        %{
          graph
          | nodes: %{
              nodes
              | node_id =>
                  case new_node do
                    new_node when is_function(new_node, 1) -> new_node.(old_node)
                    _ -> new_node
                  end
            }
        }
    end
  end

  def add_edge(%__MODULE__{} = graph, edge) do
    cond do
      # Avoid self-loop
      edge.from_node == edge.to_node ->
        graph

      # Avoid duplicated edge
      MapSet.member?(graph.edges, edge) ->
        graph

      true ->
        %{
          graph
          | edges: MapSet.put(graph.edges, edge),
            in_edges: Map.update(graph.in_edges, edge.to_node, [edge], &[edge | &1]),
            out_edges: Map.update(graph.out_edges, edge.from_node, [edge], &[edge | &1])
        }
    end
  end

  def remove_edge(%__MODULE__{edges: edges} = graph, edge) do
    %{
      graph
      | edges: MapSet.delete(edges, edge),
        in_edges: Map.update(graph.in_edges, edge.to_node, [], &List.delete(&1, edge)),
        out_edges: Map.update(graph.out_edges, edge.from_node, [], &List.delete(&1, edge))
    }
  end

  @doc "Get all input edges pointing to a given node"
  @spec get_in_edges(t(), Node.id()) :: [Edge.t()]
  def get_in_edges(%__MODULE__{} = graph, node_id) do
    Map.get(graph.in_edges, node_id, [])
  end

  @doc "Get all output edges emanating from a given node."
  @spec get_out_edges(t(), Node.id()) :: [Edge.t()]
  def get_out_edges(%__MODULE__{} = graph, node_id) do
    Map.get(graph.out_edges, node_id, [])
  end

  @spec topological_sort(t()) :: {:ok, [Node.id()]} | {:error, :cycle_detected}
  def topological_sort(%__MODULE__{} = graph) do
    in_degrees =
      Map.new(graph.nodes, fn {id, _node} ->
        {id, length(Map.get(graph.in_edges, id, []))}
      end)

    zero_in_degree_nodes =
      in_degrees
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(fn {id, _degree} -> id end)

    do_topo_sort(zero_in_degree_nodes, in_degrees, graph.out_edges, map_size(graph.nodes), [])
  end

  defp do_topo_sort([], _in_degrees, _out_edges, total_nodes, sorted_acc) do
    if length(sorted_acc) == total_nodes do
      {:ok, Enum.reverse(sorted_acc)}
    else
      {:error, :cycle_detected}
    end
  end

  defp do_topo_sort([node_id | rest_zero_nodes], in_degrees, out_edges, total, sorted_acc) do
    edges = Map.get(out_edges, node_id, [])

    {new_in_degrees, new_zero_nodes} =
      Enum.reduce(edges, {in_degrees, rest_zero_nodes}, fn edge, {deg_acc, zero_acc} ->
        to_node = edge.to_node
        new_deg = deg_acc[to_node] - 1
        deg_acc = Map.put(deg_acc, to_node, new_deg)

        case new_deg do
          0 -> {deg_acc, [to_node | zero_acc]}
          _ -> {deg_acc, zero_acc}
        end
      end)

    do_topo_sort(new_zero_nodes, new_in_degrees, out_edges, total, [node_id | sorted_acc])
  end
end
