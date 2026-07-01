defmodule Oi do
  @moduledoc """
  Oi means Orchid integration.

  Oi provides a simple API for [Orchid](https://hex.pm/packages/orchid)
  and ready-to-use functions for bind [OrchidSymbiont](https://hex.pm/packages/orchid_symbiont), [OrchidStratum](https://hex.pm/packages/orchid_stratum)
  and [OrchidIntervention](https://hex.pm/packages/orchid_intervention).

  The purpose is building a front-end-friendly interface(exclipit nodes&edges).

  ## Core Concepts

  ### Oi pipeline

  ### `Oi.Compiled`

  ### Data format during `Oi.execute/2`
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

    * `:executor` — `Oi.Executor.Sync` (default), `Oi.Executor.TaskSup`, or `Oi.Executor.Pool`
    * `:executor_opts` — passed to the executor (e.g. `[sup: MyTaskSup]`)
    * `:orchid_adapters` — OrchidPlugin pipeline
    * `:orchid_baggage` — merged into Orchid run baggage
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
