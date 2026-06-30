defmodule Oi.ComprehensiveSmokeTest do
  use ExUnit.Case

  alias Oi.Dispatch.Drafting
  alias Oi.Topology.Graph
  alias Oi.Topology.Graph.{Node, Edge}

  import OiTest.GraphFactory

  # ── Oi.Step DSL ──────────────────────────────────────────

  describe "Oi.Step DSL" do
    test "pure step with single input/output" do
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

    test "two-step pipeline using Oi.Step" do
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

    test "multi-output step" do
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

    test "oi_step error propagates" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :bad,
          container: OiTest.DummyOiStep.Failer,
          inputs: [:in],
          outputs: [:out]
        })

      {:ok, compiled} = Oi.compile(graph)
      {:error, {:orchid_error, _, _}} = Oi.execute(compiled, data: %{bad: %{in: "whatever"}})
    end
  end

  # ── Oi.Result ────────────────────────────────────────────

  describe "Oi.Result" do
    test "fetch returns {:ok, param} for existing key" do
      graph = build_finin_and_fanout_dag()
      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{
            step1: %{in: "A"},
            step2: %{in: "B"}
          }
        )

      assert {:ok, %Orchid.Param{}} = Oi.Result.fetch(result, "step4|out1")
    end

    test "fetch returns :error for missing key" do
      graph = build_finin_and_fanout_dag()
      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{
            step1: %{in: "A"},
            step2: %{in: "B"}
          }
        )

      assert {:error, :not_found} = Oi.Result.fetch(result, "nonexistent|key")
    end

    test "reify returns :error for missing key" do
      graph = build_finin_and_fanout_dag()
      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{
            step1: %{in: "A"},
            step2: %{in: "B"}
          }
        )

      assert {:error, :not_found} = Oi.Result.reify(result, "nonexistent|key")
    end
  end

  # ── Drafting ─────────────────────────────────────────────

  describe "Drafting" do
    test "new/1 seeds initial memory" do
      param = Orchid.Param.new("key", :string, "value")
      d = Drafting.new(%{"key" => param})

      assert {:ok, ^param} = Drafting.fetch(d, "key")
      assert {:error, :not_found} = Drafting.fetch(d, "missing")
    end

    test "new/2 seeds memory and interventions" do
      d =
        Drafting.new(
          %{"step|in" => Orchid.Param.new("step|in", :string, "data")},
          %{"step|in" => {:override, "forced"}}
        )

      assert {:ok, %Orchid.Param{payload: "data"}} = Drafting.fetch(d, "step|in")
      assert d.interventions == %{"step|in" => {:override, "forced"}}
    end

    test "put merges new entries" do
      d = Drafting.new()
      d = Drafting.put(d, %{"a" => Orchid.Param.new("a", :string, "x")})
      d = Drafting.put(d, %{"b" => Orchid.Param.new("b", :string, "y")})

      assert {:ok, %Orchid.Param{payload: "x"}} = Drafting.fetch(d, "a")
      assert {:ok, %Orchid.Param{payload: "y"}} = Drafting.fetch(d, "b")
    end

    test "put overwrites existing entries" do
      d = Drafting.new(%{"a" => Orchid.Param.new("a", :string, "old")})
      d = Drafting.put(d, %{"a" => Orchid.Param.new("a", :string, "new")})

      assert {:ok, %Orchid.Param{payload: "new"}} = Drafting.fetch(d, "a")
    end

    test "take returns subset of keys" do
      d =
        Drafting.new(%{
          "a" => Orchid.Param.new("a", :string, "1"),
          "b" => Orchid.Param.new("b", :string, "2"),
          "c" => Orchid.Param.new("c", :string, "3")
        })

      subset = Drafting.take(d, ["a", "c", "missing"])
      assert map_size(subset) == 2
      assert %{"a" => %Orchid.Param{payload: "1"}} = Map.take(subset, ["a"])
      assert %{"c" => %Orchid.Param{payload: "3"}} = Map.take(subset, ["c"])
    end

    test "resolve_many succeeds when all keys present" do
      d =
        Drafting.new(%{
          "a" => Orchid.Param.new("a", :string, "1"),
          "b" => Orchid.Param.new("b", :string, "2")
        })

      assert {:ok, resolved} = Drafting.resolve_many(d, ["a", "b"])
      assert map_size(resolved) == 2
    end

    test "resolve_many returns error when key missing" do
      d = Drafting.new(%{"a" => Orchid.Param.new("a", :string, "1")})

      assert {:error, {:unresolved, ["b"]}} = Drafting.resolve_many(d, ["a", "b"])
    end
  end

  # ── Config (orchid_adapters) ─────────────────────────────

  describe "Config orchid_adapters" do
    test "passes through without adapters" do
      graph = build_finin_and_fanout_dag()
      {:ok, compiled} = Oi.compile(graph)

      {:ok, _} =
        Oi.execute(compiled,
          data: %{
            step1: %{in: "A"},
            step2: %{in: "B"}
          }
        )
    end

    test "adapter can transform recipe before orchid run" do
      caller = self()

      adapter = fn {recipe, opts}, _ctx ->
        send(caller, {:adapter_ran, recipe.name})
        {recipe, Keyword.put(opts, :adapted, true)}
      end

      graph = build_finin_and_fanout_dag()
      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{step1: %{in: "A"}, step2: %{in: "B"}},
          orchid_adapters: [adapter]
        )

      assert map_size(result.memory) > 0
      assert_received {:adapter_ran, _name}
    end

    @tag :orchid_intervention
    test "orchid_intervention adapter enables output override" do
      alias OiTest.DummyOrchidStep, as: S

      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :step1,
          container: S.DummyStep1,
          inputs: [:in],
          outputs: [:mid]
        })
        |> Graph.add_node(%Node{
          id: :step2,
          container: S.DummyStep2,
          inputs: [:mid],
          outputs: [:out]
        })
        |> Graph.add_edge(Edge.new(:step1, :mid, :step2, :mid))

      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{
            step1: %{in: "ORIGINAL"},
            step2: %{mid: {:override, "INTERVENED"}}
          },
          orchid_adapters: [&Oi.Adapters.orchid_intervention/1]
        )

      # Without intervention:  "ORIGINAL -> DummyStep1 -> DummyStep2"
      # With override on mid:   step2 receives "INTERVENED"
      assert {:ok, "INTERVENED -> DummyStep2"} = Oi.Result.reify(result, "step2|out")
    end

    @tag :orchid_intervention
    test "orchid_intervention custom type post-execution merge" do
      alias OiTest.DummyOrchidStep, as: S

      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :step1,
          container: S.DummyStep1,
          inputs: [:in],
          outputs: [:mid]
        })
        |> Graph.add_node(%Node{
          id: :step2,
          container: S.DummyStep2,
          inputs: [:mid],
          outputs: [:out]
        })
        |> Graph.add_edge(Edge.new(:step1, :mid, :step2, :mid))

      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{
            step1: %{in: "ORIGINAL"},
            step2: %{mid: {OiTest.DummyInterventionType, "WRAPPED"}}
          },
          orchid_adapters: [&Oi.Adapters.orchid_intervention/1]
        )

      # DummyInterventionType.merge(inner, intervention) = "#{intervention}[#{inner}]"
      # step1 produces "ORIGINAL -> DummyStep1"
      # merge("ORIGINAL -> DummyStep1", "WRAPPED") = "WRAPPED[ORIGINAL -> DummyStep1]"
      # step2 appends " -> DummyStep2"
      assert {:ok, "WRAPPED[ORIGINAL -> DummyStep1] -> DummyStep2"} =
               Oi.Result.reify(result, "step2|out")
    end
  end

  # ── Multi-session isolation ──────────────────────────────

  describe "multi-tenant" do
    test "two sessions with independent symbiont registrations" do
      {:ok, _} = Oi.Runtime.Session.start("alpha")
      {:ok, _} = Oi.Runtime.Session.start("beta")

      # Register different handlers per session
      OrchidSymbiont.register("alpha", :demo_model, {OiTest.DummySymbiontWorker, []})
      OrchidSymbiont.register("beta", :demo_model, {OiTest.DummySymbiontWorker, []})

      # Build graph with symbiont step
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :pred,
          container: OiTest.DummyOiStep.Predicter,
          inputs: [:feature],
          outputs: [:prediction]
        })

      {:ok, compiled} = Oi.compile(graph)

      # Run in alpha session
      {:ok, result_a} =
        Oi.execute(compiled,
          data: %{pred: %{feature: "hello"}},
          executor: Oi.Executor.TaskSup,
          executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("alpha")],
          orchid_baggage: %{scope_id: "alpha"},
          orchid_opts: [global_hooks_stack: [OrchidSymbiont.Hooks.Injector]]
        )

      assert map_size(result_a.memory) > 0

      # Run in beta session
      {:ok, result_b} =
        Oi.execute(compiled,
          data: %{pred: %{feature: "world"}},
          executor: Oi.Executor.TaskSup,
          executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("beta")],
          orchid_baggage: %{scope_id: "beta"},
          orchid_opts: [global_hooks_stack: [OrchidSymbiont.Hooks.Injector]]
        )

      assert map_size(result_b.memory) > 0

      Oi.Runtime.Session.stop("alpha")
      Oi.Runtime.Session.stop("beta")
    end

    test "missing scope_id in multi-tenant mode" do
      {:ok, _} = Oi.Runtime.Session.start("isolated")

      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :pred,
          container: OiTest.DummyOiStep.Predicter,
          inputs: [:feature],
          outputs: [:prediction]
        })

      {:ok, compiled} = Oi.compile(graph)

      # Forgot to register model — should fail at Orchid level
      {:error, {:orchid_error, _, %Orchid.Error{}}} =
        Oi.execute(compiled,
          data: %{pred: %{feature: "data"}},
          executor: Oi.Executor.TaskSup,
          executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("isolated")],
          orchid_baggage: %{scope_id: "isolated"},
          orchid_opts: [global_hooks_stack: [OrchidSymbiont.Hooks.Injector]]
        )

      Oi.Runtime.Session.stop("isolated")
    end
  end

  # ── Compiled reuse ───────────────────────────────────────

  describe "Compiled reuse" do
    test "compiled plan reused with different inputs and executors" do
      graph = build_finin_and_fanout_dag()
      {:ok, compiled} = Oi.compile(graph)

      # Sync executor with input set A
      {:ok, r1} =
        Oi.execute(compiled,
          data: %{step1: %{in: "X"}, step2: %{in: "Y"}},
          executor: Oi.Executor.Sync
        )

      assert map_size(r1.memory) > 0

      # TaskSup executor with input set B
      {:ok, _} = Oi.Runtime.Session.start("reuse")

      {:ok, r2} =
        Oi.execute(compiled,
          data: %{step1: %{in: "P"}, step2: %{in: "Q"}},
          executor: Oi.Executor.TaskSup,
          executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("reuse")]
        )

      assert map_size(r2.memory) > 0

      Oi.Runtime.Session.stop("reuse")
    end
  end

  # ── Error: missing input ─────────────────────────────────

  describe "error handling" do
    test "missing external input returns error" do
      graph =
        Graph.new()
        |> Graph.add_node(%Node{
          id: :step,
          container: OiTest.DummyOiStep.Greet,
          inputs: [:name],
          outputs: [:greeting]
        })

      {:ok, compiled} = Oi.compile(graph)
      assert {:error, {:missing_input, "step|name"}} = Oi.execute(compiled)
    end
  end
end
