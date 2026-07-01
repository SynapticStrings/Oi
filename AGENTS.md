# AGENTS.md — Oi (Orchid Integration)

## Quick Reference

```bash
# Dependencies
mix deps.get

# Compile (with warnings as errors for CI)
mix compile --warnings-as-errors

# Run all tests
mix test

# Run a single test file
mix test test/oi/step_test.exs

# Run a single test by line number
mix test test/oi/step_test.exs:76

# Format check (CI gate)
mix format --check-formatted

# Static analysis
mix credo --strict

# Type checking
mix dialyzer

# Generate docs
mix docs

# Publish (requires hex credentials)
mix hex.publish
```

Elixir ~> 1.17 required. No Makefile or CI config present — commands come from `mix.exs` only.

## Architecture Overview

Oi is a lightweight integration layer on top of [Orchid](https://hex.pm/packages/orchid) workflows. It adds a DAG topology layer, compile-once-execute-many semantics, pluggable executors, and optional multi-tenant sessions.

### Three-Phase Lifecycle

```
1. BUILD   → Oi.Topology.Graph  (nodes + edges)
              via Oi.Flowgraph DSL or programmatic Graph API

2. COMPILE → Oi.Compiled  (bundles + plan, immutable, reusable)
              Oi.compile(graph, cluster)

3. EXECUTE → Oi.Result  (per-run, different data/executor each time)
              Oi.execute(compiled, data: ..., executor: ...)
```

`Oi.run/2` is a convenience that combines compile + execute in one call.

### Data Flow

```
Oi.execute(compiled, opts)
  → Config.new(opts)                    # immutable dispatch config
  → Config.build_drafting(data, compiled) # split data into memory vs interventions
  → Orchestrator.dispatch(plan, drafting, conf)
      → for each Stage (barrier-synced):
          → Executor.run(stage_tasks, worker_fn, executor_opts)
              → Worker.run(bundle, drafting, conf)
                  → resolve_dependencies from drafting.memory
                  → apply_orchid_adapters pipeline
                  → Orchid.run(recipe, params, opts)
          → merge results back into drafting
  → Result.new(drafting.memory)
```

### Key Modules

| Layer | Module | Role |
|-------|--------|------|
| **DSL** | `Oi.Flowgraph` | `graph do ... end` macro DSL; `step`, `many_step`, `~>` |
| **DSL** | `Oi.Step` | `use Oi.Step` — `manifest`, `routine`, `ok`, `err` macros |
| **Topology** | `Oi.Topology.Graph` | Pure DAG: nodes, edges, topological sort |
| **Topology** | `Oi.Topology.Cluster` | Node coloring for parallel/serial grouping |
| **Compile** | `Oi.Compile.Bundle` | Graph → Orchid Recipes with boundary metadata |
| **Compile** | `Oi.Compile.Planning` | Bundles → barrier-synced execution stages |
| **Dispatch** | `Oi.Dispatch.Config` | Immutable config: executor, adapters, baggage, timeout |
| **Dispatch** | `Oi.Dispatch.Drafting` | Per-dispatch mutable state (memory + interventions) |
| **Dispatch** | `Oi.Dispatch.Orchestrator` | Stage-by-stage barrier execution loop |
| **Dispatch** | `Oi.Dispatch.Worker` | Single-bundle executor: resolve deps → adapters → Orchid.run |
| **Dispatch** | `Oi.Dispatch.Options` | Data resolution and run-opts assembly (internal) |
| **Executor** | `Oi.Executor` | Behaviour: `run(tasks, worker_fn, opts)` |
| **Executor** | `Oi.Executor.Sync` | Serial `Enum.map` |
| **Executor** | `Oi.Executor.TaskSup` | `Task.Supervisor.async_stream_nolink` — requires `:sup` opt |
| **Runtime** | `Oi.Runtime.Session` | Multi-tenant isolation via DynamicSupervisor + Registry |
| **Runtime** | `Oi.Runtime.Registry` | Local Registry for session process lookup |
| **Core** | `Oi.Compiled` | Static struct: bundles + plan + edges |
| **Core** | `Oi.Result` | Execution result; `reify/2` extracts payloads |
| **Adapters** | `Oi.Adapters` | Ready-to-use adapter functions for Orchid ecosystem |

## Code Patterns & Conventions

### Step Definition Pattern

```elixir
defmodule MyApp.StepName do
  use Oi.Step, name: :step_name           # pure step
  # use Oi.Step, name: :step_name, symbiont?: true  # symbiont step

  manifest(
    inputs: [:port_a, :port_b],           # input port names (atoms)
    outputs: [result: :type],             # keyword: port_name => param_type
    models: [:model_name],                # required for symbiont? steps
    heavy?: false                         # optional metadata flag
  )

  # Pure step: routine <inputs>, opts do ... end
  # Single input: payload unwrapped directly
  # Multi input: use list [a, b] or tuple {a, b} pattern
  routine input_value, _opts do
    transform(input_value) |> ok()
  end

  # Symbiont step: routine <inputs>, models, opts do ... end
  routine input_value, models, _opts do
    {:ok, result} = OrchidSymbiont.call(models.model_name, {:predict, input_value})
    ok(result)
  end
end
```

**Key**: `ok/1` is a macro — it reads `@oi_outputs` at compile time to wrap values as `Orchid.Param`. `err/1` is a plain function.

**Multi-output**: `ok({a, b})` or `ok([a, b])` — order must match the `outputs:` keyword list order.

### Graph Construction

**DSL (recommended)**:
```elixir
import Oi.Flowgraph

graph = graph do
  step(MyStep, as: :alias, opts: [key: val])
  many_step [StepA, StepB, StepC]        # batch add, no options
  step_alias.output_port ~> next_step.input_port
end
```

**Programmatic**:
```elixir
Oi.Topology.Graph.new()
|> Graph.add_node(%Node{id: :name, container: MyStep, inputs: [:in], outputs: [:out]})
|> Graph.add_edge(Edge.new(:src, :out_port, :tgt, :in_port))
```

### Data Format for `Oi.execute/2`

Unified `:data` option — no separate inputs/interventions:

```elixir
Oi.execute(compiled, data: %{
  # Nested (recommended)
  step1: %{port_a: "value", port_b: 42},
  # Intervention on a port with upstream edge
  step2: %{input: {:override, "forced_value"}},
  # Tuple payloads need %Orchid.Param{} wrapper
  step3: %{input: {:override, %Orchid.Param{name: :key, type: {:tuple, 2}, payload: {1, 2}}}}
})
```

**Auto-splitting logic**: ports with no incoming edge → memory (external input); ports with incoming edge → intervention. Intervention values use `{type, value}` tuples; plain values default to `{:override, value}`.

**io_key format**: `"node_name|port_name"` (string). Use `Oi.Result.reify(result, {:node, :port})` for tuple form.

### Adapters Pipeline

Adapters are functions in `:orchid_adapters` list. Each receives `{recipe, opts}` and returns `{recipe, opts}`:

```elixir
Oi.execute(compiled,
  orchid_adapters: [
    &Oi.Adapters.orchid_intervention/1,     # arity 1
    &Oi.Adapters.orchid_symbiont/1          # arity 1
  ]
)
```

`orchid_stratum` and `orchid_intervention_and_stratum` take 2 args (arity 2 — receive Config as second argument). The adapter pipeline in `Config.apply_orchid_adapters/2` handles both arities via pattern matching.

### Session / Multi-Tenancy

```elixir
Oi.Runtime.Session.start("tenant-id")
# Session creates: Task.Supervisor + optionally OrchidSymbiont.Runtime

# Use with TaskSup executor:
Oi.execute(compiled,
  executor: Oi.Executor.TaskSup,
  executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("tenant-id")],
  orchid_baggage: %{scope_id: "tenant-id"}
)

Oi.Runtime.Session.stop("tenant-id")
```

Sessions are registered via `Oi.Runtime.Registry` (local Registry). `Session.ensure_started/2` is idempotent.

## Non-Obvious Gotchas

1. **`step` macro no longer validates eagerly**: Compile-time `Code.ensure_compiled!` and `function_exported?` checks were removed from the `step` macro to avoid cross-file compilation ordering issues. Validation now happens at runtime in `add_step/3` (`Code.ensure_loaded` + `function_exported?`). If a step module isn't loaded, the graph DSL will fail at `add_step/3` with a pattern match error on `{:module, _}`. For compile-time feedback, users can add `Code.ensure_compiled!(MyStep)` at module level before the `graph` block.

2. **Intervention keying by producer port**: Interventions in the drafting are keyed by the producer's output port (`{from_node, from_port}` → io_key), not the consumer's input port. This design comes from `OrchidIntervention` — interventions short-circuit the producer step, overriding what it would have written. Keying by producer allows intercepting data at the source without needing to enumerate all downstream consumers.

3. **`ok/1` is a macro, not a function**: It reads module attributes at compile time. Calling `ok(value)` without prior `manifest(outputs: [...])` raises a compile error.

4. **Symbiont deps are optional**: `orchid_symbiont`, `orchid_intervention`, and `orchid_stratum` are all optional deps. Code uses `Code.ensure_loaded?/1` guards everywhere. Using `symbiont?: true` without the dep installed raises at compile time.

5. **PortRef key format**: `PortRef.to_orchid_key({:port, node, port})` produces `"node|port"` strings. The pipe `|` separator is a deliberate design — early versions used dynamically generated atoms (e.g. `:"node_port"`), but this risked atom table memory leaks. The string format was chosen instead. **Known limitation**: the format is not reversible if node or port names contain `|`, since there's no escape mechanism. Keep node/port names to simple atoms or strings without `|`.

6. **Config vs Drafting**: Config holds immutable execution strategy (executor, adapters, timeouts) — same across multiple `execute` calls. Drafting holds per-dispatch mutable data (memory + interventions) — unique to each execution. Interventions live in Drafting, not Config. This separation enables compile-once-execute-many: same Config, different Drafting each time.

7. **Executor contract (current, rough design)**: The `Oi.Executor` behaviour defines `run(tasks, worker_fn, opts)`. It must return a list of `{:ok, %{io_key => Orchid.Param.t()}}` or `{:error, term()}` tuples, one per task. Known rough edges: (a) the dual-level error pattern — executor-level `{:error, term()}` vs per-task `{:error, term()}` in the list — is ambiguous; (b) `TaskSup` uses `ordered: false`, so result order doesn't match task order, but this isn't part of the contract; (c) `opts` is an untyped keyword list (`:sup`, `:concurrency`, `:timeout` are implicit); (d) worker crashes in `TaskSup` are wrapped as `{:error, {:worker_crashed, reason}}`, an undocumented convention.

8. **Cluster defaults**: Without a Cluster, all nodes go to `:default_cluster` and produce a single bundle. Cluster coloring propagates upstream — a node inherits its upstream neighbor's color if not explicitly set.

9. **Self-loops silently ignored**: `Graph.add_edge/2` silently drops edges where `from_node == to_node`. No error raised.

10. **`mix.exs` test coverage**: Test modules matching `~r/.*Test.*/` are excluded from coverage reports.

11. **Dev-only observer**: `:observer` and `:wx` are loaded only in `:dev` env (`mix.exs:63`).

12. **`Oi.run/2` extracts `:cluster` from opts**: When passing a `Graph.t()` to `Oi.run/2`, it pulls `cluster` from opts and passes the rest to `execute/2`.

## Testing Approach

- **ExUnit** with `async: true` where possible
- Test support modules in `test/support/` — compiled via `elixirc_paths(:test)` in mix.exs
- **Factory pattern**: `OiTest.GraphFactory` builds reusable test DAGs (e.g., `build_finin_and_fanout_dag/0`)
- **Dummy steps**: `OiTest.DummyOiStep.*` (Oi DSL), `OiTest.DummyOrchidStep.*` (raw Orchid), `OiTest.DummySymbiontStep` (symbiont)
- **Smoke tests**: End-to-end tests for compile→execute flow, sessions, symbionts, stratum caching
- **Doctest**: `Oi.Flowgraph` has doctests via `Oi.FlowgraphDocTest`
- Comments in test files use Chinese (historical) — don't translate them

## Optional Dependencies

| Package | Purpose | Loaded via |
|---------|---------|------------|
| `orchid_symbiont` | ML model runtime | `Code.ensure_loaded?` |
| `orchid_intervention` | Intervention hooks | `Code.ensure_loaded?` |
| `orchid_stratum` | Caching layer (ETS-backed) | `Code.ensure_loaded?` |
| `ex_doc` | Docs generation | `:dev` only |
| `dialyxir` | Type checking | `:dev, :test` |
| `credo` | Linting | `:dev, :test` |

## File Organization

```
lib/
  oi.ex                    # Facade: compile/2, execute/2, run/2
  oi/
    step.ex                # Step DSL macros (use, manifest, routine, ok, err)
    flowgraph.ex           # Graph DSL macros (graph, step, ~>, many_step)
    compiled.ex            # Static compilation product struct
    result.ex              # Execution result struct + reify/2
    adapters.ex            # Ready-to-use adapter functions
    topology/
      graph.ex             # Pure DAG (Node, Edge, PortRef, topo sort)
      cluster.ex           # Node coloring for parallel grouping
    compile/
      bundle.ex            # Graph → Orchid Recipes with boundaries
      planning.ex          # Bundles → barrier-synced stages (Stage, Plan)
    dispatch/
      config.ex            # Immutable dispatch configuration
      drafting.ex          # Per-dispatch mutable state
      orchestrator.ex      # Stage-by-stage barrier loop
      worker.ex            # Single-bundle execution
      options.ex           # Data resolution + opts assembly (internal)
    executor.ex            # Executor behaviour
    executor/
      sync.ex              # Serial executor
      task_sup.ex           # Task.Supervisor executor
    runtime/
      session.ex           # Multi-tenant session management
      session/instances.ex # Per-session supervisor (Task.Supervisor + optional Symbiont)
      registry.ex          # Local Registry for session lookup
```
