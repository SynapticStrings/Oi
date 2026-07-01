defmodule Oi do
  @moduledoc """
  Oi means Orchid integration.

  Oi provides a simple API for [Orchid](https://hex.pm/packages/orchid)
  and ready-to-use functions for bind [OrchidSymbiont](https://hex.pm/packages/orchid_symbiont), [OrchidStratum](https://hex.pm/packages/orchid_stratum)
  and [OrchidIntervention](https://hex.pm/packages/orchid_intervention).

  The purpose is building a front-end-friendly interface(exclipit nodes&edges).

  ## Core Concepts

  ### Oi pipeline

  There're three phases in Oi's lifecycle:

  1. Build a `Oi.Topology.Graph` of step nodes and edges
      * By macros in `Oi.Flowgraph`
      * By functions in `Oi.Topology.Graph`
  2. `Oi.compile/2`(*topology level*) generate static `Oi.Compiled` struct (bundles + plan, reusable)
  3. `Oi.execute/2` can resolve data, apply orchid_adapters, run via pluggable executor

  ### Compiled

  immutable compilation product. Compile once, dispatch many times
  with different data / executors.

  See `Oi.Compiled`.

  ### Data format during `Oi.execute/2`

  Oi provides unified `data:` replaces the separate `inputs:` / `interventions:`.

  * Ports with **no incoming edge** → memory (external inputs).
  * Ports with **an incoming edge** → interventions (data originates inside the graph,
    user is overriding it). Intervention values use the format `{type, value}`
    where `type` is an atom naming the intervention strategy (`:override`, `:offset`,
    or a custom module like `MyApp.MergeStrategy`). Plain values default to
    `{:override, value}`.

  When the payload is a tuple, wrap it explicitly in `%Orchid.Param{}` to
  preserve type information:
      {:override, %Orchid.Param{name: :key, type: {:tuple, 2}, payload: {1, 2}}}

  Two formats supported:

  ```elixir
  # Nested (recommended)
  data: %{step1: %{in: "foo"}, step2: %{result: {:override, "bar"}}}

  # Tuple keys
  data: %{{:step1, :in} => "foo", {:step2, :result} => {:override, "bar"}}
  ```

  ### Pluggable Executor

  Pluggable task fan-out per stage. Built-in: `Oi.Executor.Sync` (serial),
  `Oi.Executor.TaskSup` (Task.Supervisor within per session).

  Custom executors implement the `Oi.Executor` behaviour.

  ### Session / Multiple Oi instances

  Optional multi-tenant isolation via `Oi.Runtime.Session`,
  wrapping per-tenant `OrchidSymbiont.Runtime` + `Task.Supervisor`.

  ### Orchid Extension

  Oi intentionally does not implement its own workflow plugin system.
  Use Orchid hooks through `:orchid_opts` for step-level concerns such as logging,
  metrics, retry, and caching.

  Oi also support some ready-to-use functions to load/modify orchid's recipe and
  options via `Oi.Adapters`.
  """

  @typedoc "Oi's name, split several scopes."
  @type name :: String.t()

  alias Oi.{Compile, Compiled, Result}
  alias Oi.Dispatch.{Config, Orchestrator}
  alias Oi.Topology.{Cluster, Graph}

  @doc """
  Compile graph into static bundles + plan.

  Pure topology — no interventions. Reusable across different
  intervention sets and inputs.
  """
  @spec compile(Graph.t(), Cluster.t()) :: {:ok, Compiled.t()} | {:error, :cycle_detected}
  def compile(graph, cluster \\ %Oi.Topology.Cluster{}) do
    with {:ok, bundles} <- Compile.Bundle.compile_graph(graph, cluster),
         {:ok, plan} <- Compile.Planning.build(bundles) do
      {:ok, %Compiled{bundles: bundles, plan: plan, edges: graph.edges}}
    else
      {:error, _} = err ->
        err
    end
  end

  @doc """
  Execute compiled plan with inputs and interventions.

  ## Unified `:data` format (recommended)

      Oi.execute(compiled, data: %{
        step1: %{in: "foo"},
        step2: %{result: {:override, "bar"}}
      })

  Supports tuple-key format as well: `%{{:step, :port} => value}`.

  Ports with incoming edges → intervention; ports without → memory.
  Intervention values use `{type, value}` where `type` is an atom naming the
  intervention strategy (`:override`, `:offset`, or a custom module).
  Plain values default to `{:override, value}`.
  For tuple payloads, wrap in `%Orchid.Param{}` to preserve type info.

  ## Other options

    * `:executor` — `Oi.Executor.Sync` (default), `Oi.Executor.TaskSup`, or custom module implementing `Oi.Executor`
    * `:executor_opts` — passed to the executor (e.g. `[sup: MyTaskSup]`)
    * `:orchid_adapters` — adapter pipeline; each is a 1-arity or 2-arity function over `{recipe, opts}`
    * `:orchid_baggage` — merged into Orchid run baggage
    * `:orchid_opts` — extra keyword opts forwarded to `Orchid.run/3`
    * `:concurrency` — fallback for executor if `:executor_opts` has none (default: `System.schedulers_online()`)
    * `:timeout` — fallback for executor (default: `:infinity`)
    * `:name` — optional scope name, merged into baggage as `:scope_id`
  """
  @spec execute(Compiled.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute(%Compiled{} = compiled, opts \\ []) do
    conf = Config.new(opts)

    with {:ok, drafting} <- Config.build_drafting(Keyword.get(opts, :data, %{}), compiled),
         {:ok, final_drafting} <- Orchestrator.dispatch(compiled.plan, drafting, conf) do
      {:ok, Result.new(final_drafting.memory)}
    else
      {:error, _} = err ->
        err
    end
  end

  # All-in-one
  #
  # 1. extract cluster via key `:cluster`
  # 2. other options same as execute/2
  @spec run(Compiled.t() | Graph.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run(graph_or_compiled, opts \\ [])

  def run(%Compiled{} = compiled, opts) do
    execute(compiled, opts)
  end

  def run(%Graph{} = graph, opts) do
    cluster = Keyword.get(opts, :cluster, %Cluster{})
    execute_opts = Keyword.delete(opts, :cluster)

    with {:ok, compiled} <- compile(graph, cluster) do
      execute(compiled, execute_opts)
    end
  end
end
