defmodule Oi.Topology.GraphTest do
  use ExUnit.Case

  import Oi.Topology.Graph
  alias Oi.Topology.Graph.{Node, Edge, PortRef}
  alias OiTest.DummyOrchidStep.{DummyStep1, DummyStep2}

  import OiTest.GraphFactory

  describe "Item creation" do
    test "same step impl can use different node ids" do
      node_1 = %Node{id: :node_1, container: DummyStep1, inputs: [:in], outputs: [:out]}
      node_2 = %Node{id: :node_2, container: DummyStep1, inputs: [:in], outputs: [:out]}

      assert Map.from_struct(node_1) != Map.from_struct(node_2)

      {:ok, res1} = node_1.container.run(%Orchid.Param{payload: "NodeIn"}, [])
      {:ok, res2} = node_2.container.run(%Orchid.Param{payload: "NodeIn"}, [])

      assert res1.payload == res2.payload
    end

    test "Edge.new/4" do
      edge = Edge.new(:node_a, :port_out, :node_b, :port_in)

      assert edge.from_node == :node_a
      assert edge.from_port == :port_out
      assert edge.to_node == :node_b
      assert edge.to_port == :port_in
    end
  end

  describe "PortRef" do
    test "to_orchid_key with atom port" do
      assert PortRef.to_orchid_key({:port, :foo, :bar}) == "foo|bar"
    end

    test "to_orchid_key with binary port" do
      assert PortRef.to_orchid_key({:port, :foo, "barr"}) == "foo|barr"
    end

    test "to_orchid_key with binary node" do
      assert PortRef.to_orchid_key({:port, "my_node", :out}) == "my_node|out"
    end
  end

  describe "Item operation" do
    test "add_node/2" do
      graph =
        new()
        |> add_node(%Node{id: :node_1, container: DummyStep1, inputs: [:in], outputs: [:out]})

      assert graph.nodes[:node_1].container == DummyStep1
    end

    test "add_edge/2 ignores duplicate and self-loop edges" do
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :b, :in))
        |> add_edge(Edge.new(:a, :out, :b, :in))
        |> add_edge(Edge.new(:a, :out, :a, :in))

      assert Enum.count(graph.edges) == 1
      edge = Enum.at(graph.edges, 0)
      assert edge.from_node == :a
      assert edge.to_node == :b
    end

    test "remove_node/2 cleans up node and its edges" do
      graph = build_graph_v1()
      graph = remove_node(graph, :node_a)

      assert graph.nodes == %{
               :node_b => %Node{
                 id: :node_b,
                 container: DummyStep2,
                 inputs: [:mid],
                 outputs: [:out],
                 options: [],
                 extra: %{}
               }
             }

      assert graph.edges == MapSet.new()
    end

    test "remove_node/2 no-ops when node does not exist" do
      old_graph = build_graph_v1()
      graph = remove_node(old_graph, :node_foo)

      assert graph.nodes == old_graph.nodes
      assert graph.edges == old_graph.edges
    end

    test "update_node/2 with struct replacement" do
      graph = build_graph_v1()

      graph =
        update_node(graph, :node_b, %Node{
          id: :node_b,
          container: DummyStep1,
          inputs: [:mid],
          outputs: [:out]
        })

      assert graph.nodes[:node_b].container == DummyStep1
    end

    test "update_node/2 with function updater" do
      graph = build_graph_v1()
      graph = update_node(graph, :node_b, fn old -> %{old | container: DummyStep1} end)

      assert graph.nodes[:node_b].container == DummyStep1
    end

    test "update_node/2 no-ops when node does not exist" do
      graph = build_graph_v1()
      new_graph = update_node(graph, :node_c, fn _ -> %Node{} end)

      assert graph == new_graph
    end

    test "remove_edge/2" do
      edge = Edge.new(:a, :out, :b, :in)

      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(edge)

      graph = remove_edge(graph, edge)
      assert graph.edges == MapSet.new()
    end

    test "get_in_edges/2" do
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :c, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :c, :in))
        |> add_edge(Edge.new(:b, :out, :c, :in))

      in_edges = get_in_edges(graph, :c)
      assert length(in_edges) == 2
      assert Enum.all?(in_edges, &(&1.to_node == :c))
    end

    test "get_out_edges/2" do
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :c, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :b, :in))
        |> add_edge(Edge.new(:a, :out, :c, :in))

      out_edges = get_out_edges(graph, :a)
      assert length(out_edges) == 2
      assert Enum.all?(out_edges, &(&1.from_node == :a))
    end
  end

  describe "same?/2" do
    test "identical graphs are same" do
      graph1 = build_graph_v1()
      graph2 = build_graph_v1()

      assert same?(graph1, graph2)
    end

    test "graphs diverge after mutation" do
      graph1 = build_graph_v1()
      graph2 = build_graph_v1() |> remove_node(:node_a)

      refute same?(graph1, graph2)
    end
  end

  describe "topological_sort" do
    test "fan-in/fan-out graph" do
      graph = build_finin_and_fanout_dag()

      assert {:ok, order} = topological_sort(graph)
      idx = fn id -> Enum.find_index(order, &(&1 == id)) end
      assert idx.(:step1) < idx.(:step3)
      assert idx.(:step2) < idx.(:step3)
      assert idx.(:step3) < idx.(:step4)
    end

    test "cycle returns error" do
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :b, :in))
        |> add_edge(Edge.new(:b, :out, :a, :in))

      {:error, nodes} = topological_sort(graph)
      assert Enum.sort(nodes) == [:a, :b]
    end
  end
end
