defmodule Oi.SmokeTest do
  use ExUnit.Case

  import OiTest.GraphFactory
  alias Oi.{Workspace, Compiler}
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
    test "fills static_bundles and plan" do
      graph = build_finin_and_fanout_dag()
      ws = Workspace.new("test-session", graph)

      {:ok, ws} = Oi.compile(ws)

      assert ws.static_bundles != nil
      assert length(ws.static_bundles) == 1
      assert ws.plan != nil
      assert ws.plan.total_tasks == 1
    end
  end

  describe "Oi.dispatch (end-to-end)" do
    test "sync executor runs the full pipeline" do
      graph = build_finin_and_fanout_dag()
      ws = Workspace.new("test-session", graph)

      {:ok, ws} = Oi.compile(ws)

      interventions = %{
        {:port, :step1, :in} => {:input, "Foo"},
        {:port, :step2, :in} => {:input, "Bar"}
      }

      {:ok, ws} = Oi.dispatch(ws, interventions: interventions, executor: Oi.Executor.Sync)

      assert ws.drafting != nil
      # Drafting should have outputs from step4
      assert map_size(ws.drafting.memory) > 0
    end

    test "dispatch without compile returns error" do
      ws = Workspace.new("test-session", build_finin_and_fanout_dag())

      assert {:error, :not_compiled} = Oi.dispatch(ws)
    end
  end

  describe "interventions A/B (reuse compiled plan)" do
    test "same compiled workspace with different interventions" do
      graph = build_finin_and_fanout_dag()
      ws = Workspace.new("ab-test", graph)

      {:ok, ws} = Oi.compile(ws)

      interventions_a = %{
        {:port, :step1, :in} => {:input, "A1"},
        {:port, :step2, :in} => {:input, "A2"}
      }

      interventions_b = %{
        {:port, :step1, :in} => {:input, "B1"},
        {:port, :step2, :in} => {:input, "B2"}
      }

      {:ok, ws_a} = Oi.dispatch(ws, interventions: interventions_a)
      {:ok, ws_b} = Oi.dispatch(ws, interventions: interventions_b)

      # Both should produce results
      assert ws_a.drafting != nil
      assert ws_b.drafting != nil

      # The static_bundles should be unchanged (reused)
      assert ws.static_bundles == ws_a.static_bundles
      assert ws.static_bundles == ws_b.static_bundles
    end
  end
end
