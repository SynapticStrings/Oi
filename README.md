# Oi

Oi means Orchid integration — lightweight glue layer between
[Orchid](https://github.com/SynapticStrings/Orchid) workflows and
[OrchidSymbiont](https://github.com/SynapticStrings/orchid_symbiont) runtimes.

<!-- MDOC -->

## Core concepts

- **Graph → Compile → Execute** — three-phase pipeline:
  1. Build a `Graph` of step nodes and edges
  2. `Oi.compile(graph)` — topology → static `Compiled` (bundles + plan, reusable)
  3. `Oi.execute(compiled, opts)` — resolve inputs, apply orchid_adapters, run via pluggable executor

- **Compiled** — immutable compilation product. Compile once, dispatch many times
  with different inputs / interventions / executors.

- **Inputs vs Interventions** — two kinds of external data:
  - `inputs:` — `%{"io_key" => payload}` seeded into drafting memory before dispatch
  - `interventions:` — `%{{:port, node, port} => {type, payload}}` merged into
    Orchid baggage, consumed by `Orchid.Hook.ApplyInterventions` per-step

- **Executor** — pluggable task fan-out per stage. Built-in: `Sync` (serial),
  `TaskSup` (Task.Supervisor). `Pool` (NimblePool) planned.

- **Session** — optional multi-tenant isolation via `Oi.Runtime.Session`,
  wrapping per-tenant `OrchidSymbiont.Runtime` + `Task.Supervisor`.

- **Extension model** — Oi intentionally does not implement its own workflow
  plugin system. Use Orchid hooks through `:orchid_opts` for step-level
  concerns such as auth, logging, metrics, retry, and caching.

## Quick start

### Define a step

```elixir
defmodule MyApp.Steps.Upcase do
  use Oi.Step, name: :upcase

  manifest(
    inputs: [:text],
    outputs: [result: :string]
  )

  routine text, _opts do
    text |> String.upcase() |> ok()
  end
end
```

### Build and run

```elixir
alias Oi.Topology.Graph
alias Oi.Topology.Graph.Node

graph =
  Graph.new()
  |> Graph.add_node(%Node{
    id: :up,
    container: MyApp.Steps.Upcase,
    inputs: [:text],
    outputs: [:result]
  })

{:ok, compiled} = Oi.compile(graph)

{:ok, result} = Oi.execute(compiled,
  inputs: %{"up|text" => "hello"}
)

Oi.Result.reify(result, "up|result")
# => {:ok, "HELLO"}
```

### With interventions

```elixir
# Use vanilla orchid with custom opts(without orchid_adapters)
{:ok, result} = Oi.execute(compiled,
  inputs: %{"step1|in" => "hello"},
  interventions: %{
    {:port, :step2, :in} => {:override, "forced_value"}
  },
  orchid_opts: [
    global_hooks_stack: [Orchid.Hook.ApplyInterventions]
  ]
)
```

### Multi-tenant with Session

```elixir
Oi.Runtime.Session.start("tenant-1")

graph = build_graph()
{:ok, compiled} = Oi.compile(graph)

{:ok, result} = Oi.execute(compiled,
  inputs: %{"step|in" => "data"},
  executor: Oi.Executor.TaskSup,
  executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("tenant-1")],
  orchid_baggage: %{scope_id: "tenant-1"},
  orchid_opts: [global_hooks_stack: [OrchidSymbiont.Hooks.Injector]]
)

Oi.Runtime.Session.stop("tenant-1")
```

### Symbiont step

```elixir
defmodule MyApp.Steps.Predict do
  use Oi.Step, name: :predict, symbiont?: true

  manifest(
    inputs: [:features],
    outputs: [prediction: :string],
    models: [:model]
  )

  routine features, models, _opts do
    {:ok, result} = OrchidSymbiont.call(models.model, {:predict, features})
    ok(result)
  end
end
```

<!-- MDOC -->

## Roadmap

- [x] Graph compilation + staged dispatch
- [x] Pluggable Executor (Sync / TaskSup)
- [x] Multi-tenant Session
- [x] Oi.Step macro DSL
- [x] Interventions (via Orchid baggage)
- [ ] Executor.Pool (NimblePool for GPU-intensive tasks)

## License

MIT
