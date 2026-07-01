# Oi

> *Oi means Orchid integration.*

Lightweight glue layer between
[Orchid](https://hex.pm/packages/orchid) workflows and
[OrchidSymbiont](https://hex.pm/packages/orchid_symbiont) runtimes.

## Quick start

Same example with [orchid](https://github.com/SynapticStrings/Orchid).

### Define a step

```elixir
defmodule Barista.Grind do
  use Oi.Step, name: :grind

  manifest(inputs: [:beans], outputs: [powder: :solid])

  routine beans_amount, opts do
    IO.puts("⚙️ Grinding #{beans_amount}g beans...")
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

{:ok, compiled} = 
  graph do
    step(Barista.Grind)
    step(Barista.Brew, opts: [style: :latte])
    grind.powder ~> brew.powder
  end |> Oi.compile()

{:ok, result} = Oi.execute(compiled,
  data: %{grind: %{beans: 20}, brew: %{water: 200}}
)
# ⚙️ Grinding 20g beans...
# 💧 Brewing latte coffee with 20g powder and 200ml water...

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
  orchid_adapters: [&Oi.Adapters.orchid_intervention/1]
)

# Tuple payload — use %Orchid.Param{} to preserve type info
{:ok, result} = Oi.execute(compiled,
  data: %{
    src: %{in: "hello"},
    tgt: %{in: {:override, %Orchid.Param{name: :key, type: {:tuple, 2}, payload: {1, 2}}}}
  },
  orchid_adapters: [&Oi.Adapters.orchid_intervention/1]
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

## License

MIT
