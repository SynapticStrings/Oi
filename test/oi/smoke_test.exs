defmodule Oi.SmokeTest do
  use ExUnit.Case

  import OiTest.GraphFactory
  alias Oi.{Compiler, Compiled}
  alias Oi.Compiler.RecipeBundle
  alias Oi.Topology.{Graph, Cluster}
  alias Oi.Topology.Graph.{Node, Edge}

  describe "compile (phase 1)" do
    test "compile_graph without cluster produces single bundle" do
      graph = build_finin_and_fanout_dag()

      {:ok, [bundle]} = Compiler.compile_graph(graph)

      assert is_struct(bundle, RecipeBundle)
      assert "step1|in" in bundle.requires
      assert "step2|in" in bundle.requires
      assert "step4|out1" in bundle.exports
      assert "step4|out2" in bundle.exports
    end

    test "compile_graph with cluster splits into multiple bundles" do
      graph = build_finin_and_fanout_dag()
      cluster = %Cluster{node_colors: %{step3: :red}}

      {:ok, bundles} = Compiler.compile_graph(graph, cluster)

      assert length(bundles) == 2
      [bundle_red, bundle_default] = bundles

      # bundle_red contains step3
      assert :step3 in bundle_red.node_ids
      # bundle_default contains step1, step2, step4
      assert :step1 in bundle_default.node_ids
    end

    test "cycle detected returns error" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{id: :a, container: OiTest.DummyOrchidStep.DummyStep1, inputs: [:in], outputs: [:out]})
        |> Graph.add_node(%Node{id: :b, container: OiTest.DummyOrchidStep.DummyStep1, inputs: [:in], outputs: [:out]})
        |> Graph.add_edge(Edge.new(:a, :out, :b, :in))
        |> Graph.add_edge(Edge.new(:b, :out, :a, :in))

      assert {:error, :cycle_detected} = Compiler.compile_graph(graph)
    end
  end

  describe "Oi.compile (facade)" do
    test "produces Compiled with bundles and plan" do
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      assert is_struct(compiled, Compiled)
      assert length(compiled.bundles) == 1
      assert compiled.plan != nil
      assert compiled.plan.total_tasks == 1
    end
  end

  describe "Oi.execute (end-to-end)" do
    test "sync executor runs the full pipeline" do
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      interventions = %{
        {:port, :step1, :in} => {:input, "Foo"},
        {:port, :step2, :in} => {:input, "Bar"}
      }

      {:ok, result} = Oi.execute(compiled, interventions: interventions, executor: Oi.Executor.Sync)

      assert is_struct(result, Oi.Result)
      assert map_size(result.memory) > 0
    end

    test "execute with inputs instead of interventions" do
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      inputs = %{"step1|in" => "Foo", "step2|in" => "Bar"}

      {:ok, result} = Oi.execute(compiled, inputs: inputs, executor: Oi.Executor.Sync)

      assert is_struct(result, Oi.Result)
      assert map_size(result.memory) > 0
    end
  end

  describe "reuse compiled plan with different interventions" do
    test "same compiled with different interventions" do
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      interventions_a = %{
        {:port, :step1, :in} => {:input, "A1"},
        {:port, :step2, :in} => {:input, "A2"}
      }

      interventions_b = %{
        {:port, :step1, :in} => {:input, "B1"},
        {:port, :step2, :in} => {:input, "B2"}
      }

      {:ok, result_a} = Oi.execute(compiled, interventions: interventions_a)
      {:ok, result_b} = Oi.execute(compiled, interventions: interventions_b)

      assert map_size(result_a.memory) > 0
      assert map_size(result_b.memory) > 0
    end
  end
end
