# [WIP]Oi

Oi means Orchid integration — lightweight glue layer between
[Orchid](https://github.com/SynapticStrings/Orchid) workflows and
[OrchidSymbiont](https://github.com/SynapticStrings/orchid_symbiont) runtimes.

<!-- MDOC -->

## Core concepts

- **Workspace** — pure data struct holding graph, cluster, interventions.
  No process, no GenServer. Compiled and dispatched via pure functions.

- **Compile + Dispatch** — two-phase pipeline:
  1. `Oi.compile/1` — topology → static bundles (reusable)
  2. `Oi.dispatch/2` — bind interventions → plan → execute via pluggable executor

- **Executor** — pluggable task execution strategy.
  Built-in: `Sync` (serial), `TaskSup` (Task.Supervisor), `Pool` (NimblePool)(in future).

- **Session** — optional process tree per tenant, wrapping `OrchidSymbiont.Runtime`
  for multi-tenant isolation.

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
alias Oi.Topology.Graph.{Node, Edge}

graph =
  Graph.new()
  |> Graph.add_node(%Node{
    id: :up, container: MyApp.Steps.Upcase,
    inputs: [:text], outputs: [:result]
  })

ws = Oi.Workspace.new("demo", graph)
{:ok, ws} = Oi.compile(ws)
{:ok, ws} = Oi.dispatch(ws,
  interventions: %{{:port, :up, :text} => {:input, "hello"}}
)

ws.drafting.memory  # => %{"up|result" => "HELLO"}
```

### Multi-tenant with Session

```elixir
Oi.Session.start("tenant-1")
Oi.Session.start("tenant-2")

ws = Oi.Workspace.new("tenant-1", graph)
{:ok, ws} = Oi.compile(ws)
{:ok, ws} = Oi.dispatch(ws,
  executor: Oi.Executor.TaskSup,
  executor_opts: [sup: Oi.Session.tasks_tuple("tenant-1")]
)
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

- [x] Scaffold
- [ ] Exclipit inputs

## License

MIT
