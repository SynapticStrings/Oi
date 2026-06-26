# Oi

Oi means Orchid integration — lightweight glue layer between
[Orchid](https://hex.pm/packges/orchid) workflows and
[OrchidSymbiont](https://hex.pm/packges/orchid_symbiont) runtimes.

<!-- MDOC -->

## Core concepts

- **Graph → Compile → Execute** — three-phase pipeline:
  1. Build a `Graph` of step nodes and edges
  2. `Oi.compile(graph)` — topology → static `Compiled` (bundles + plan, reusable)
  3. `Oi.execute(compiled, opts)` — resolve data, apply orchid_adapters, run via pluggable executor

- **Compiled** — immutable compilation product. Compile once, dispatch many times
  with different data / executors.

- **Data** — unified `data:` replaces the separate `inputs:` / `interventions:`.
  Ports with **no incoming edge** → memory (external inputs).
  Ports with **an incoming edge** → interventions (data originates inside the graph,
  user is overriding it). Intervention types are declared via value wrappers
  (`{:override, v}`, `{:offset, v}`, `{:custom, v}`). Plain values on intervention
  ports are preserved as-is for downstream interpretation.

  Two formats supported:

  ```elixir
  # Nested (recommended)
  data: %{step1: %{in: "foo"}, step2: %{result: {:override, "bar"}}}

  # Tuple keys
  data: %{{:step1, :in} => "foo", {:step2, :result} => {:override, "bar"}}
  ```

- **Executor** — pluggable task fan-out per stage. Built-in: `Sync` (serial),
  `TaskSup` (Task.Supervisor). `Pool` (NimblePool) planned.

- **Session** — optional multi-tenant isolation via `Oi.Runtime.Session`,
  wrapping per-tenant `OrchidSymbiont.Runtime` + `Task.Supervisor`.

- **Extension model** — Oi intentionally does not implement its own workflow
  plugin system. Use Orchid hooks through `:orchid_opts` for step-level
  concerns such as auth, logging, metrics, retry, and caching.

## Quick start

Same example with [orchid](https://github.com/SynapticStrings/Orchid).

### Define a step

```elixir
defmodule Barista.Grind do
  use Oi.Step, name: :grind

  manifest(inputs: [:beans], outputs: [powder: :solid])

  routine beans_amount, opts do
    IO.puts("⚙️  Grinding #{beans_amount}g beans...")
    beans_amount * Keyword.get(opts, :ratio, 1) |> ok()
  end
end

defmodule Barista.Brew do
  use Oi.Step, name: :brew

  manifest(inputs: [:powder, :water], outputs: [coffee: :liquid])

  routine [powder_amount, water_amount], opts do
    style = Keyword.get(opts, :style, :espresso)

    IO.puts("💧 Brewing #{style} coffee with #{powder_amount}g powder and #{water_amount}ml water...")
    ok("Cup of #{style}")
  end
end
```

### Build and run

```elixir
import Oi.Flowgraph

graph =
  new_flowchart()
  |> add_step(Barista.Grind)
  |> add_step(Barista.Brew, opts: [style: :latte])
  |> connect({:grind, :powder}, {:brew, :powder})

{:ok, compiled} = Oi.compile(graph)

{:ok, result} = Oi.execute(compiled,
  data: %{grind: %{beans: 20}, brew: %{water: 200}}
)

{:ok, coffee} = Oi.Result.reify(result, {:brew, :coffee})
IO.inspect(coffee)
# => "Cup of latte"
```

### With interventions

```elixir
# Override an intermediate port — wrap the value with intervention type
{:ok, result} = Oi.execute(compiled,
  data: %{
    step1: %{in: "hello"},
    step2: %{in: {:override, "forced_value"}}   # step2.in has upstream edge → intervention
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
  data: %{step: %{in: "data"}},
  executor: Oi.Executor.TaskSup,
  executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("tenant-1")],
  orchid_baggage: %{scope_id: "tenant-1"}
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

- [x] Basic
- [x] Basic multi-tenant Session runtime
- [ ] Executor.Pool (NimblePool for GPU-intensive tasks)
- [ ] Telemetry

## License

MIT
