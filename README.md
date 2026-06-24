# [WIP]Oi

Oi means Orchid integration, it provides simple API to cover heavy Orchid Step code.

<!-- MDOC -->

## Example

Demo.

```elixir
defmodule FooStep do
  use Oi.StepBuilder

  # meinfest()

  routine name, _ do
    IO.puts "Hello #{name}!"

    ok(nil)
  end
end

orchid_recipe = Oi.build([FooStep])
inputs = "Foo"

```

<!-- MDOC -->

## Roadmap

* [ ] [Quincunx](https://github.com/SynapticStrings/Quincunx)-like arch
    * integrate Orchid with OrchidSymbiont, OrchidStratum and OrchidIntervention
    * Node-based declarate interface
* [ ] `Oi.Step` macro

