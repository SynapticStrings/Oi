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
  Compile a workspace's graph into a plan.

  Pure function: fills `workspace.plan` with a `Planning.Plan`.
  Does not touch `drafting`.
  """
  @spec compile(Workspace.t()) :: {:ok, Workspace.t()} | {:error, :cycle_detected}
  def compile(%Workspace{} = ws) do
    case Compiler.compile(ws.graph, ws.cluster, ws.interventions) do
      {:ok, bundles} ->
        {:ok, plan} = Planning.build(bundles)
        {:ok, %{ws | plan: plan}}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Execute a workspace's plan, filling `drafting` with results.

  ## Options

  See `Oi.Configurator.new/1`. Key options:

    * `:executor` — `Oi.Executor.Sync` (default), `Oi.Executor.TaskSup`, or `Oi.Executor.Pool`
    * `:executor_opts` — passed to the executor (e.g. `[sup: MyTaskSup]`)
    * `:plugins` — OrchidPlugin pipeline
    * `:orchid_baggage` — merged into Orchid run baggage

  ## Examples

      # Pure function (sync, no processes)
      {:ok, ws} = Oi.compile(ws)
      {:ok, ws} = Oi.dispatch(ws)

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

      %Planning.Plan{} = plan ->
        conf = Configurator.new(opts)
        drafting = Drafting.new()

        case Dispatcher.dispatch(plan, drafting, conf) do
          {:ok, final_drafting} ->
            {:ok, %{ws | drafting: final_drafting}}

          {:error, _} = err ->
            err
        end
    end
  end
end
