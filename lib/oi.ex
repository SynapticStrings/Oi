defmodule Oi do
  @doc_header """
  Oi means Orchid integration.
  """

  @external_resource readme = Path.join([__DIR__, "../README.md"])
  @doc_main readme
            |> File.read!()
            |> String.split("<!-- MDOC -->")
            |> Enum.fetch!(1)

  @moduledoc @doc_header <> @doc_main

  @type name :: String.t()

  alias Oi.Workspace
  alias Oi.{Compiler, Dispatcher, Configurator}
  alias Oi.Workspace.{Planning, Drafting}

  @doc """
  Phase 1: Compile graph into static bundles + plan.

  Pure topology — no interventions. Result stored in `workspace.static_bundles`
  and `workspace.plan`. Reusable across different intervention sets.
  """
  @spec compile(Workspace.t()) :: {:ok, Workspace.t()} | {:error, :cycle_detected}
  def compile(%Workspace{} = ws) do
    case Compiler.compile_graph(ws.graph, ws.cluster) do
      {:ok, bundles} ->
        {:ok, plan} = Planning.build(bundles)
        {:ok, %{ws | static_bundles: bundles, plan: plan}}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Phase 2: Dispatch plan with interventions, filling `drafting`.

  Interventions can be overridden via the `:interventions` option —
  useful for A/B testing with the same compiled plan.

  ## Options

    * `:interventions` — overrides `workspace.interventions` (default)
    * `:inputs` — map of external io_key => payload, seeded into drafting memory
    * `:executor` — `Oi.Executor.Sync` (default), `Oi.Executor.TaskSup`, or `Oi.Executor.Pool`
    * `:executor_opts` — passed to the executor (e.g. `[sup: MyTaskSup]`)
    * `:plugins` — OrchidPlugin pipeline
    * `:orchid_baggage` — merged into Orchid run baggage

  ## Examples

      # Compile once
      {:ok, ws} = Oi.compile(ws)

      # Dispatch with default interventions
      {:ok, ws} = Oi.dispatch(ws)

      # Dispatch with swapped interventions (reuses compiled plan)
      {:ok, ws_b} = Oi.dispatch(ws, interventions: other_interventions)

      # With Task.Supervisor
      {:ok, ws} = Oi.dispatch(ws,
        executor: Oi.Executor.TaskSup,
        executor_opts: [sup: Oi.Session.tasks_tuple("svs-1")]
      )
  """
  @spec dispatch(Workspace.t(), keyword()) :: {:ok, Workspace.t()} | {:error, term()}
  def dispatch(%Workspace{} = ws, opts \\ []) do
    case ws.plan do
      nil ->
        {:error, :not_compiled}

      %Planning.Plan{} ->
        inputs = Keyword.get(opts, :inputs, %{})
        interventions = Keyword.get(opts, :interventions, ws.interventions)

        conf = Configurator.new(opts ++ [interventions: interventions])

        initial_memory =
          Map.new(inputs, fn {k, v} -> {k, Orchid.Param.new(k, :any, v)} end)

        drafting = Drafting.new(initial_memory)

        case Dispatcher.dispatch(ws.plan, drafting, conf) do
          {:ok, final_drafting} ->
            {:ok, %{ws | drafting: final_drafting}}

          {:error, _} = err ->
            err
        end
    end
  end
end
