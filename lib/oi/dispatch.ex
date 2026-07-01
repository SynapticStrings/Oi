defmodule Oi.Dispatch do
  @moduledoc """
  Dispatch layer: takes a compiled pipeline and runs it with concrete data.

  ## Cross-module data flow

      Oi.execute(compiled, opts)
        │
        ▼
      Config.new(opts)                     immutable execution strategy
        │
        ▼
      Options.build_drafting(data, compiled) split data → memory + interventions
        │
        ▼
      Orchestrator.dispatch(plan, drafting, config)
        │
        ├─ for each Stage (barrier-synced): ──────────────────────────┐
        │     Executor.run(stage_tasks, &Worker.run/1, executor_opts) │
        │         │                                                   │
        │         └─ Worker: resolve deps → adapters → Orchid.run     │
        │                                                             │
        ├─ merge deltas back into Drafting  ◄─────────────────────────┘
        │
        ▼
      Result.new(drafting.memory)

  ## Module responsibilities

  | Module                      | Mutable? | Role |
  |-----------------------------|----------|------|
  | `Oi.Dispatch.Config`        | no       | Executor, adapters, timeouts, baggage |
  | `Oi.Dispatch.Drafting`      | yes      | Per-dispatch state: memory + interventions |
  | `Oi.Dispatch.Orchestrator`  | —        | Stage loop: fan-out → collect → barrier |
  | `Oi.Dispatch.Worker`        | —        | Single bundle: deps → adapters → Orchid.run |
  | `Options`                   | —        | Internal: data resolution + opts assembly |

  ## Data format (`:data` option)

  Unified format — no separate `:inputs` / `:interventions`.  Two shapes:

      # Nested (recommended)
      %{step_name: %{port: value, ...}, ...}

      # Tuple keys
      %{{:step, :port} => value, ...}

  Ports are auto-split by topology at dispatch time:

  * **No incoming edge** → memory (external input)
  * **Has incoming edge** → intervention (overrides upstream output)

  Intervention values use `{type, value}` where `type` is an atom
  (`:override`, `:offset`, or a custom module).  Plain values default to
  `{:override, value}`.  For tuple payloads, wrap in `%Orchid.Param{}` to
  preserve type info.
  """
end
