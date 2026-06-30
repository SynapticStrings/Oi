defmodule Oi.SmokeTest do
  use ExUnit.Case
  import OiTest.GraphFactory

  alias Oi.Compiled
  alias Oi.Compile.Bundle
  alias Oi.Topology.{Graph, Cluster}
  alias Oi.Topology.Graph.{Node, Edge}

  describe "compile (phase 1)" do
    test "compile_graph without cluster produces single bundle" do
      graph = build_finin_and_fanout_dag()

      {:ok, [bundle]} = Bundle.compile_graph(graph)

      assert is_struct(bundle, Bundle)
      assert "step1|in" in bundle.requires
      assert "step2|in" in bundle.requires
      assert "step4|out1" in bundle.exports
      assert "step4|out2" in bundle.exports
    end

    test "compile_graph with cluster splits into multiple bundles" do
      graph = build_finin_and_fanout_dag()
      cluster = %Cluster{node_colors: %{step3: :red}}

      {:ok, bundles} = Bundle.compile_graph(graph, cluster)

      assert length(bundles) == 2

      bundle_red = Enum.find(bundles, &(:step3 in &1.node_ids))
      bundle_default = Enum.find(bundles, &(:step1 in &1.node_ids))

      # bundle_red contains step3
      assert bundle_red != nil
      assert :step3 in bundle_red.node_ids
      # bundle_default contains step1, step2, step4
      assert bundle_default != nil
      assert :step1 in bundle_default.node_ids
    end

    test "cycle detected returns error" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :a,
          container: OiTest.DummyOrchidStep.DummyStep1,
          inputs: [:in],
          outputs: [:out]
        })
        |> Graph.add_node(%Node{
          id: :b,
          container: OiTest.DummyOrchidStep.DummyStep1,
          inputs: [:in],
          outputs: [:out]
        })
        |> Graph.add_edge(Edge.new(:a, :out, :b, :in))
        |> Graph.add_edge(Edge.new(:b, :out, :a, :in))

      assert {:error, :cycle_detected} = Bundle.compile_graph(graph)
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

      {:ok, result} =
        Oi.execute(compiled,
          data: %{step1: %{in: "Foo"}, step2: %{in: "Bar"}},
          executor: Oi.Executor.Sync
        )

      assert is_struct(result, Oi.Result)
      assert map_size(result.memory) > 0
    end

    test "execute with data instead of inputs" do
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{step1: %{in: "Foo"}, step2: %{in: "Bar"}},
          executor: Oi.Executor.Sync
        )

      assert is_struct(result, Oi.Result)
      assert map_size(result.memory) > 0
    end
  end

  describe "reuse compiled plan with different interventions" do
    test "same compiled with different data" do
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      {:ok, result_a} = Oi.execute(compiled, data: %{step1: %{in: "A1"}, step2: %{in: "A2"}})
      {:ok, result_b} = Oi.execute(compiled, data: %{step1: %{in: "B1"}, step2: %{in: "B2"}})

      assert map_size(result_a.memory) > 0
      assert map_size(result_b.memory) > 0
    end
  end
end
