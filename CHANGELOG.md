# Changelog

## v0.6.3 (unreleased)

### Changed

- `resolve_data/2` now validates input format explicitly. Returns
  `{:error, :invalid_data_format}` for unrecognised shapes instead of
  silently producing empty maps.  `build_drafting_inputs/2` propagates
  the error tuple.
- `Oi.Adapters.orchid_stratum/1` → `orchid_stratum/2` — accepts
  `%Oi.Dispatch.Config{}` as second argument.  Same for
  `orchid_intervention_and_stratum`.  Callers in tests updated.
- `unwrap_tuple/1` now handles list input — resolves `list param map ↔
  tuple data` mismatch.
- `flatten_data/1` detects format per-entry instead of requiring
  homogeneous maps.
- Intervention value format documented: `{type, value}` where `type` is
  an atom (`:override`, `:offset`, or a custom module). Plain values
  default to `:override`.  Tuple payloads should use `%Orchid.Param{}`
  to preserve type info.
- `Oi.Step` docs translated from Chinese to English.

### Fixed

- README: broken hex.pm URLs (`packges` → `packages`).


## v0.6.2 (2026-06-29)

### Added

- `Oi.Flowgraph.many_step/1` — batch-add steps that share no options.
  Expands to a block of `step/1` calls.

      graph do
        many_step [LoadPosts, LoadPages, LoadImages]
        step Markdown, as: :md, opts: [...]
        ...
      end

### Changed

- `orchid_symbiont` is now an **optional** dependency.  Session auto-detects
  whether `OrchidSymbiont.Runtime` is available at runtime and omits the
  child spec when the dep is not installed.  `Oi.Step` raises a clear error
  at compile time if `symbiont?: true` is used without the dep.
- `step` macro: removed compile-time `function_exported?` validation
  (unreliable across files during macro expansion).  Validation is deferred
  to `add_step/3` at runtime.  For compile-time enforcement, add
  `Code.ensure_compiled!(Module)` at module level in your graph file.

### Fixed

- `step` macro: `unquote(module)` → `unquote(resolved)` so that
  `add_step/3` receives the expanded module atom instead of the alias AST,
  fixing graphs that were silently producing zero nodes.
- `many_step` expansion: fully-qualified `Oi.Flowgraph.step/1` calls to
  guarantee resolution regardless of import context.
- `Oi.Adapters.ensure_stratum_storage/1`: uses `Module.concat` + `apply/3`
  to avoid compile-time warnings about undefined `OrchidStratum.*` modules
  when `orchid_stratum` is not installed (optional dep).

## v0.6.0 (2026-06-29)

### Added

- `Oi.Flowgraph` DSL macros — `graph/1`, `step/2`, `~>/2` for declarative graph building.
  Supports both `node.port` dot-notation and `{node, port}` tuple form.
  `step` validates at compile time that the module implements `__node_spec__/0`.
- `Oi.Adapters.orchid_symbiont/1` — opt-in adapter that prepends
  `OrchidSymbiont.Hooks.Injector` at runtime when `orchid_symbiont` is available.

### Changed

- `Oi.Result.fetch/2` and `reify/2` now return `{:error, :not_found}` instead of bare
  `:error` — consistent with the rest of the codebase.
- `Oi.Dispatch.Drafting.fetch/2` — same `{:error, :not_found}` change.
- `Oi.Dispatch.Orchestrator.merge_results/2` no longer silently drops `nil` values from
  step outputs.
- `Oi.Compile.Bundle.compile_graph/2` now sorts bundles deterministically by cluster name.
- `Oi.Runtime.Session.Instances` supervisor strategy changed from `one_for_all` to
  `one_for_one` — Task.Supervisor and OrchidSymbiont.Runtime no longer cascade-kill
  each other.

### Removed

- `Oi.Dispatch.Options.assemble_run_opts/3` no longer auto-injects
  `OrchidSymbiont.Hooks.Injector` into the hooks stack. Use
  `Oi.Adapters.orchid_symbiont/1` in the `:orchid_adapters` chain instead.
- `unwrap_interventions/1` in Options — replaced by `wrap_interventions_for_orchid/1`
  that does a single wrap instead of unwrap-then-rewrap.

### Fixed

- Intervention data no longer goes through an unnecessary `wrap → unwrap → wrap` cycle —
  raw values are stored in Drafting and wrapped once in `assemble_run_opts/3`.

## v0.5.0 & v0.4.0 (2026-06-26)

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

- `Oi.Dispatch.Options.resolve_data/2` — splits unified data into memory/intervention
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
