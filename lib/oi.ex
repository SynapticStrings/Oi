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

  alias Oi.{Compiler, Dispatcher, Configurator, Compiled, Result}
  alias Oi.{Planning, Drafting}

  @doc """
  Phase 1: Compile graph into static bundles + plan.

  Pure topology — no interventions. Reusable across different
  intervention sets and inputs.
  """
  @spec compile(Graph.t(), Cluster.t()) :: {:ok, Compiled.t()} | {:error, :cycle_detected}
  def compile(graph, cluster \\ %Oi.Topology.Cluster{}) do
    case Compiler.compile_graph(graph, cluster) do
      {:ok, bundles} ->
        {:ok, plan} = Planning.build(bundles)
        {:ok, %Compiled{bundles: bundles, plan: plan}}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Phase 2: Execute compiled plan with inputs and interventions.

  ## Options

    * `:inputs` — map of external io_key => payload, seeded into drafting memory
    * `:interventions` — map of `{:port, node, port} => {type, payload}`
    * `:executor` — `Oi.Executor.Sync` (default), `Oi.Executor.TaskSup`, or `Oi.Executor.Pool`
    * `:executor_opts` — passed to the executor (e.g. `[sup: MyTaskSup]`)
    * `:plugins` — OrchidPlugin pipeline
    * `:orchid_baggage` — merged into Orchid run baggage

  ## Examples

      # Compile once
      {:ok, compiled} = Oi.compile(graph, cluster)

      # Execute with inputs + interventions
      {:ok, result} = Oi.execute(compiled,
        inputs: %{"step1|in" => "foo"},
        interventions: %{{:port, :step1, :in} => {:override, "Bar"}}
      )

      # Same compiled plan, different inputs
      {:ok, result_b} = Oi.execute(compiled, inputs: %{"step1|in" => "baz"})

      # With Task.Supervisor
      {:ok, result} = Oi.execute(compiled,
        executor: Oi.Executor.TaskSup,
        executor_opts: [sup: Oi.Session.tasks_tuple("svs-1")]
      )
  """
  @spec execute(Compiled.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute(%Compiled{} = compiled, opts \\ []) do
    inputs = Keyword.get(opts, :inputs, %{})
    interventions = Keyword.get(opts, :interventions, %{})

    conf = Configurator.new(opts ++ [interventions: interventions])

    initial_memory =
      Map.new(inputs, fn {k, v} -> {k, Orchid.Param.new(k, :any, v)} end)

    drafting = Drafting.new(initial_memory)

    case Dispatcher.dispatch(compiled.plan, drafting, conf) do
      {:ok, final_drafting} ->
        {:ok, Result.new(final_drafting.memory)}

      {:error, _} = err ->
        err
    end
  end
end
