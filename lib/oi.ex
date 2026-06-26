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
  alias Oi.Dispatch.Options

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
  Values pass through as-is. Wrapped values ({:override, v}, {:offset, v}, {:custom, v})
  are preserved for downstream intervention handling.

  ## Legacy `:inputs` / `:interventions` (still supported)

      Oi.execute(compiled,
        inputs: %{"step1|in" => "foo"},
        interventions: %{{:port, :step1, :in} => {:override, "Bar"}}
      )

  ## Other options

    * `:executor` — `Oi.Executor.Sync` (default), `Oi.Executor.TaskSup`, or `Oi.Executor.Pool`
    * `:executor_opts` — passed to the executor (e.g. `[sup: MyTaskSup]`)
    * `:orchid_adapters` — OrchidPlugin pipeline
    * `:orchid_baggage` — merged into Orchid run baggage
  """
  @spec execute(Compiled.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute(%Compiled{} = compiled, opts \\ []) do
    {initial_memory_io, interventions_io} = Options.build_drafting_inputs(compiled, opts)

    drafting = Drafting.new(initial_memory_io, interventions_io)
    conf = prepare_config(opts)

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
      |> Keyword.drop([:interventions, :orchid_baggage, :data])
      |> Keyword.put(:orchid_baggage, baggage)
    )
  end
end
