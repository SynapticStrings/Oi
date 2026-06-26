# Changelog

## v0.4.0 (2026-06-26)

### Update

- **Unified `:data` option** — replaces separate `:inputs`/`:interventions` with a single
  `data:` map. Ports are auto-split by topology: no incoming edge → memory, has incoming
  edge → intervention. Legacy `:inputs` / `:interventions` options deprecated. Now two
  formats supported:

  ```elixir
  # Nested (recommended)
  Oi.execute(compiled, data: %{step1: %{in: "foo"}, step2: %{result: {:override, "bar"}}})

  # Tuple keys
  Oi.execute(compiled, data: %{{:step1, :in} => "foo"})
  ```

- `Oi.resolve_data/2` — public function for splitting unified data into memory/intervention
  maps based on graph topology (edge presence).
- `Compiled` struct now carries `edges: MapSet.t(Edge.t())` for downstream port resolution.
- Intervention type wrappers (`{:override, v}`, `{:offset, v}`, `{:custom, v}`) preserved
  as-is through the pipeline.

### Fixed

- `Oi.Executor.TaskSup`: `Keyword.fetch!` → `Keyword.fetch` (via-tuple pattern match was
  always failing, causing all TaskSup-backed sessions to crash).

## v0.3.0 (2026-06-25)

### Changed

- Renamed `:plugins` option to `:orchid_adapters`, simplified to function-only form.
  Module-based adapter dispatch removed — use Orchid hooks for step-level concerns.
- Moved `:interventions` from Config to Drafting. Config is now purely immutable
  dispatch configuration; Drafting holds per-dispatch mutable state.
- `:interventions` keys now accept both `{:port, node, port}` tuples (auto-converted
  via `PortRef.to_orchid_key/1`) and raw orchid_key strings.
- `merge_results/2` simplified — dead `%Orchid.Param{}` branch removed.

### Removed

- `:hooks` lifecycle callbacks from Config. Oi intentionally defers step-level
  concerns to Orchid's hook system via `:orchid_opts`.
- `resolve_from_intervention/2` in Worker. Intervention injection now happens at
  Drafting construction time, not per-bundle.

### Fixed

- Intervention priority: interventions now override drafting memory (were previously
  ignored when a drafting key already existed).

## v0.2.0

### Breaking

- `Oi.compile/1` (taking `Workspace`) replaced by `Oi.compile/2` (taking `graph, cluster`)
- `Oi.dispatch/2` replaced by `Oi.execute/2` (taking `Compiled.t()`)
- `Oi.Workspace` struct removed
- `Oi.Compiler.RecipeBundle` renamed to `Oi.Compile.Bundle`
- `Oi.Workspace.Planning` renamed to `Oi.Compile.Planning`
- `Oi.Configurator` renamed to `Oi.Dispatch.Config`
- `Oi.Dispatcher` renamed to `Oi.Dispatch.Orchestrator`
- `Oi.Drafting` renamed to `Oi.Dispatch.Drafting`
- `Oi.Worker` renamed to `Oi.Dispatch.Worker`
- `Oi.Session` / `Oi.Registry` moved to `Oi.Runtime.*`

### Added

- `Oi.Compiled` struct — static compilation product (bundles + plan)
- `Oi.Result` struct — execution result with `memory` and `reify/2`
- `:inputs` option for `Oi.execute/2` — external inputs seeded into drafting memory
- `Oi.run/2` convenience — compiles + executes in one call
- `Worker.resolve_dependencies` returns explicit `{:error, {:missing_input, key}}`

### Changed

- `RecipeBundle.interventions` field removed — interventions moved to `Dispatch.Config`
- `Compiler.bind/2` removed — Worker filters interventions from config at runtime
- `Drafting.memory` unified to store `Orchid.Param.t()` throughout (no payload extraction)
- `Planning.build` no longer called twice (compile once, reuse plan in execute)
- Drafting nil filtering commented out (pending review)

### Internal

- Namespace reorganized: `Oi.Compile.*`, `Oi.Dispatch.*`, `Oi.Runtime.*`
