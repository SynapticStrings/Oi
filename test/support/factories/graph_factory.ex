defmodule OiTest.GraphFactory do
  @moduledoc false

  import Oi.Topology.Graph

  alias Oi.Topology.Graph.{Node, Edge}
  alias OiTest.DummyOrchidStep, as: S

  def build_graph_v1 do
    new()
    |> add_node(%Node{
      id: :node_a,
      container: S.DummyStep1,
      inputs: [:in],
      outputs: [:mid]
    })
    |> add_node(%Node{
      id: :node_b,
      container: S.DummyStep2,
      inputs: [:mid],
      outputs: [:out]
    })
    |> add_edge(Edge.new(:node_a, :mid, :node_b, :mid))
  end

  def build_finin_and_fanout_dag do
    new()
    |> add_node(%Node{id: :step1, container: S.DummyStep1, inputs: [:in], outputs: [:out]})
    |> add_node(%Node{id: :step2, container: S.DummyStep2, inputs: [:in], outputs: [:out]})
    |> add_node(%Node{id: :step3, container: S.DummyStep3, inputs: [:in1, :in2], outputs: [:out]})
    |> add_node(%Node{
      id: :step4,
      container: S.DummyStep4,
      inputs: [:in],
      outputs: [:out1, :out2]
    })
    |> add_edge(Edge.new(:step1, :out, :step3, :in1))
    |> add_edge(Edge.new(:step2, :out, :step3, :in2))
    |> add_edge(Edge.new(:step3, :out, :step4, :in))
  end
end
