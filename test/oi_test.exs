defmodule OiTest do
  use ExUnit.Case

  alias Oi.Topology.Graph
  alias Oi.Topology.Graph.{Node, Edge}
  alias Oi.Dispatch.Options
  import OiTest.GraphFactory

  # ── resolve_data/2 ──────────────────────────────────────

  describe "resolve_data/2 format A (tuple keys)" do
    setup do
      graph = build_finin_and_fanout_dag()
      %{edges: graph.edges}
    end

    test "ports with no incoming edge go to memory", %{edges: edges} do
      data = %{
        {:step1, :in} => "A",
        {:step2, :in} => "B"
      }

      {memory, interventions} = Options.resolve_data(data, edges)

      assert memory == %{{:step1, :in} => "A", {:step2, :in} => "B"}
      assert interventions == %{}
    end

    test "ports with incoming edge go to intervention", %{edges: edges} do
      data = %{
        {:step3, :in1} => {:override, "overridden_in1"},
        {:step3, :in2} => "plain_overridden_in2",
        {:step4, :in} => {:offset, 42}
      }

      {memory, interventions} = Options.resolve_data(data, edges)

      assert memory == %{}

      assert interventions == %{
               {:step1, :out} => {:override, "overridden_in1"},
               {:step2, :out} => "plain_overridden_in2",
               {:step3, :out} => {:offset, 42}
             }
    end

    test "mixed: dangling + upstream ports", %{edges: edges} do
      data = %{
        {:step1, :in} => "external_input",
        {:step3, :in1} => {:override, "intercepted"},
        {:step4, :out1} => {:custom, "final_override"}
      }

      {memory, interventions} = Options.resolve_data(data, edges)

      # step1.in: no incoming edge
      # step4.out1: no incoming edge (only outgoing from step4)
      assert memory == %{
               {:step1, :in} => "external_input",
               {:step4, :out1} => {:custom, "final_override"}
             }

      # step3.in1: has incoming edge from step1.out
      assert interventions == %{
               {:step1, :out} => {:override, "intercepted"}
             }
    end

    test "values pass through as-is, no wrapping", %{edges: edges} do
      data = %{
        {:step1, :in} => 123,
        {:step3, :in1} => {:override, "bar"}
      }

      {memory, interventions} = Options.resolve_data(data, edges)

      # memory value stays as 123 (not wrapped in Orchid.Param)
      assert memory[{:step1, :in}] == 123
      # intervention value stays as {:override, "bar"}, keyed by producer output
      assert interventions[{:step1, :out}] == {:override, "bar"}
    end

    test "empty data returns two empty maps", %{edges: edges} do
      {memory, interventions} = Options.resolve_data(%{}, edges)
      assert memory == %{}
      assert interventions == %{}
    end
  end

  describe "resolve_data/2 format B (nested)" do
    setup do
      graph = build_finin_and_fanout_dag()
      %{edges: graph.edges}
    end

    test "splits by topology", %{edges: edges} do
      data = %{
        step1: %{in: "hello"},
        step2: %{in: "world"},
        step3: %{in1: {:override, "bye"}}
      }

      {memory, interventions} = Options.resolve_data(data, edges)

      assert memory == %{{:step1, :in} => "hello", {:step2, :in} => "world"}
      assert interventions == %{{:step1, :out} => {:override, "bye"}}
    end

    test "single node with multiple ports", %{edges: edges} do
      data = %{
        step3: %{
          in1: {:override, "X"},
          in2: "Y",
          out: "Z"
        }
      }

      {memory, interventions} = Options.resolve_data(data, edges)

      # in1, in2: have upstream edges → intervention
      # out: no incoming edge (only outgoing) → memory
      assert interventions == %{
               {:step1, :out} => {:override, "X"},
               {:step2, :out} => "Y"
             }

      assert memory == %{{:step3, :out} => "Z"}
    end
  end

  describe "resolve_data/2 topology logic" do
    test "port with edge targeting it IS upstream" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{id: :src, container: :dummy, inputs: [], outputs: [:out]})
        |> Graph.add_node(%Node{id: :tgt, container: :dummy, inputs: [:in], outputs: []})
        |> Graph.add_edge(Edge.new(:src, :out, :tgt, :in))

      data = %{{:tgt, :in} => {:override, "gotcha"}}

      {memory, interventions} = Options.resolve_data(data, graph.edges)

      # tgt.in has edge src.out → tgt.in → HAS upstream → intervention
      assert memory == %{}
      assert interventions == %{{:src, :out} => {:override, "gotcha"}}
    end

    test "source port with only outgoing edges is NOT upstream" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{id: :src, container: :dummy, inputs: [:in], outputs: [:out]})
        |> Graph.add_node(%Node{id: :tgt, container: :dummy, inputs: [:in], outputs: []})
        |> Graph.add_edge(Edge.new(:src, :out, :tgt, :in))

      data = %{{:src, :out} => {:override, "nope"}}

      {memory, interventions} = Options.resolve_data(data, graph.edges)

      # src.out only has outgoing edge (src.out → tgt.in), no incoming → memory
      assert memory == %{{:src, :out} => {:override, "nope"}}
      assert interventions == %{}
    end
  end

  # ── execute with :data ──────────────────────────────────

  describe "execute/2 with :data" do
    test "simple step via :data nested format" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :greeter,
          container: OiTest.DummyOiStep.Greet,
          inputs: [:name],
          outputs: [:greeting]
        })

      {:ok, compiled} = Oi.compile(graph)
      {:ok, result} = Oi.execute(compiled, data: %{greeter: %{name: "World"}})

      assert {:ok, "Hello, World"} = Oi.Result.reify(result, "greeter|greeting")
    end

    test "pipeline via :data nested format" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :greeter,
          container: OiTest.DummyOiStep.Greet,
          inputs: [:name],
          outputs: [:greeting]
        })
        |> Graph.add_node(%Node{
          id: :shouter,
          container: OiTest.DummyOiStep.Exclaim,
          inputs: [:text],
          outputs: [:shout]
        })
        |> Graph.add_edge(Edge.new(:greeter, :greeting, :shouter, :text))

      {:ok, compiled} = Oi.compile(graph)
      {:ok, result} = Oi.execute(compiled, data: %{greeter: %{name: "Oi"}})

      assert {:ok, "Hello, Oi!"} = Oi.Result.reify(result, "shouter|shout")
    end

    test "multi-output step via :data" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :calc,
          container: OiTest.DummyOiStep.MultiOut,
          inputs: [:x, :y],
          outputs: [:sum, :product]
        })

      {:ok, compiled} = Oi.compile(graph)
      {:ok, result} = Oi.execute(compiled, data: %{calc: %{x: 3, y: 4}})

      assert {:ok, 7} = Oi.Result.reify(result, "calc|sum")
      assert {:ok, 12} = Oi.Result.reify(result, "calc|product")
    end

    test "fanin_and_fanout via :data" do
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{
            step1: %{in: "Hello"},
            step2: %{in: "World"}
          }
        )

      # step4|out1 and step4|out2 are the final outputs
      assert {:ok, _} = Oi.Result.reify(result, "step4|out1")
      assert {:ok, _} = Oi.Result.reify(result, "step4|out2")
    end

    test "data with tuple keys format A" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :greeter,
          container: OiTest.DummyOiStep.Greet,
          inputs: [:name],
          outputs: [:greeting]
        })

      {:ok, compiled} = Oi.compile(graph)
      {:ok, result} = Oi.execute(compiled, data: %{{:greeter, :name} => "TupleKey"})

      assert {:ok, "Hello, TupleKey"} = Oi.Result.reify(result, "greeter|greeting")
    end
  end
end
