defmodule Oi.SymbiontSmokeTest do
  use ExUnit.Case

  alias Oi.Session
  alias Oi.Topology.Graph
  alias Oi.Topology.Graph.Node

  # ── Helpers ────────────────────────────────────────────

  defp register_predicter(scope_id) do
    OrchidSymbiont.register(scope_id, :predicter, {OiTest.DummySymbiontWorker, []})
  end

  defp build_predict_dag do
    Graph.new()
    |> Graph.add_node(%Node{
      id: :pred_step,
      container: OiTest.DummySymbiontStep,
      inputs: [:text],
      outputs: [:result]
    })
  end

  describe "Symbiont isolation across sessions" do
    test "different sessions get isolated catalog registrations" do
      {:ok, _} = Session.start("sym-tenant-a")
      {:ok, _} = Session.start("sym-tenant-b")

      register_predicter("sym-tenant-a")
      register_predicter("sym-tenant-b")

      # Both should be able to resolve their own
      {:ok, _} = OrchidSymbiont.Resolver.resolve("sym-tenant-a", :predicter)
      {:ok, _} = OrchidSymbiont.Resolver.resolve("sym-tenant-b", :predicter)

      Session.stop("sym-tenant-a")
      Session.stop("sym-tenant-b")
    end

    # @tag :symbiont_dispatch
    test "end-to-end symbiont execute in single session" do
      {:ok, _} = Session.start("sym-e2e")

      register_predicter("sym-e2e")

      graph = build_predict_dag()

      {:ok, compiled} = Oi.compile(graph)

      interventions = %{
        {:port, :pred_step, :text} => {:input, "hello"}
      }

      {:ok, result} =
        Oi.execute(compiled,
          interventions: interventions,
          executor: Oi.Executor.Sync,
          orchid_baggage: %{scope_id: "sym-e2e"},
          orchid_opts: [
            global_hooks_stack: [OrchidSymbiont.Hooks.Injector]
          ]
        )

      assert is_struct(result, Oi.Result)
      assert map_size(result.memory) > 0

      Session.stop("sym-e2e")
    end
  end
end
