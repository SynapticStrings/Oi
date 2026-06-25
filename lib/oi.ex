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

  alias Oi.{Compile, Compiled, Result}
  alias Oi.Dispatch.{Config, Drafting, Orchestrator}
  alias Oi.Topology.{Graph, Cluster}
  alias Oi.Topology.Graph.PortRef

  @doc """
  Compile graph into static bundles + plan.

  Pure topology — no interventions. Reusable across different
  intervention sets and inputs.
  """
  @spec compile(Graph.t(), Cluster.t()) :: {:ok, Compiled.t()} | {:error, :cycle_detected}
  def compile(graph, cluster \\ %Oi.Topology.Cluster{}) do
    with {:ok, bundles} <- Compile.Bundle.compile_graph(graph, cluster),
         {:ok, plan} <- Compile.Planning.build(bundles) do
      {:ok, %Compiled{bundles: bundles, plan: plan}}
    else
      {:error, _} = err ->
        err
    end
  end

  @doc """
  Execute compiled plan with inputs and interventions.

  ## Options

    * `:inputs` — map of io_key => payload, seeded into drafting as initial memory
    * `:interventions` — map of `{:port, node, port} => {type, payload}`.
      Types: `:override`, `:offset`, `:custom` etc. Resolved per-bundle by Worker.
      Note: interventions are NOT for external inputs — use `:inputs` for that.
    * `:executor` — `Oi.Executor.Sync` (default), `Oi.Executor.TaskSup`, or `Oi.Executor.Pool`
    * `:executor_opts` — passed to the executor (e.g. `[sup: MyTaskSup]`)
    * `:orchid_adapters` — OrchidPlugin pipeline
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
        executor_opts: [sup: Oi.Runtime.Session.tasks_tuple("svs-1")]
      )
  """
  @spec execute(Compiled.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute(%Compiled{} = compiled, opts \\ []) do
    inputs = Keyword.get(opts, :inputs, %{})

    interventions =
      opts
      |> Keyword.get(:interventions, %{})
      |> Map.new(fn
        {{:port, node, port}, v} -> {PortRef.to_orchid_key({:port, node, port}), v}
        {key, v} when is_binary(key) -> {key, v}
      end)

    conf = prepare_config(opts)

    initial_memory =
      Map.new(inputs, fn {k, v} -> {k, Orchid.Param.new(k, :any, v)} end)

    drafting = Drafting.new(initial_memory, interventions)

    case Orchestrator.dispatch(compiled.plan, drafting, conf) do
      {:ok, final_drafting} ->
        {:ok, Result.new(final_drafting.memory)}

      {:error, _} = err ->
        err
    end
  end

  def run(struct, opts \\ [])

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

  defp prepare_config(opts) do
    baggage = opts |> Keyword.get(:orchid_baggage, []) |> Enum.into(%{})

    Config.new(
      opts
      |> Keyword.drop([:interventions, :orchid_baggage])
      |> Keyword.put(:orchid_baggage, baggage)
    )
  end
end
