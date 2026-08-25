defmodule Oi.Dispatch.Config do
  @moduledoc """
  Immutable dispatch configuration.

  Built once at the dispatch boundary, threaded to Worker and the plugin
  chain. Controls executor selection, concurrency, timeout, and Orchid
  plugin pipeline.

  ## Options

    * `:executor`       — module implementing `Oi.Executor` (default: `Oi.Executor.Sync`)
    * `:executor_opts`  — keyword opts passed to executor's `run/3`
    * `:orchid_adapters`        — ordered list of adapters; each is a 1-arity `fn {recipe, opts} -> {recipe, opts}` or 2-arity `fn {recipe, opts}, conf -> {recipe, opts}`
    * `:orchid_baggage` — map merged into every Orchid run's baggage
    * `:orchid_opts`    — extra keyword opts forwarded to `Orchid.run/3`
    * `:concurrency`    — fallback for executor if `:executor_opts` has none (default: `System.schedulers_online()`)
    * `:timeout`        — fallback for executor if `:executor_opts` has none (default: `:infinity`)
    * `:name`           — optional scope name, merged into baggage as `:scope_id`
    * `:checkpoint`     — optional function called before each stage; see "Checkpoint" below

  ## Checkpoint

  A checkpoint is a function `fn event, drafting -> :cont | :halt end` invoked by the
  orchestrator before each stage runs. `event` is a map with `:stage_index`, `:stage_count`,
  `:clusters` (cluster names of the stage's bundles) and `:node_ids`. The passed `drafting`'s
  memory holds everything produced so far — inspect it, then return `:cont` to run the stage
  or `:halt` to stop the whole dispatch with the current memory as a partial result.
  """

  alias Oi.Dispatch.{Drafting, Options}

  @typedoc """
  Unified user-facing data for `Oi.execute/2`.

  See `Oi.Dispatch` module docs for the full data format specification.
  Two shapes supported:

    - Nested: `%{step: %{port: value}}`
    - Tuple keys: `%{{:step, :port} => value}`
  """
  @type data :: map()

  @typedoc """
  Event map passed to a `:checkpoint` function before a stage runs.
  """
  @type checkpoint_event :: %{
          stage_index: non_neg_integer(),
          stage_count: non_neg_integer(),
          clusters: [Oi.Topology.Cluster.cluster_name()],
          node_ids: [Oi.Topology.Graph.Node.id()]
        }

  @type checkpoint_action :: :cont | :halt

  @type checkpoint :: (checkpoint_event(), Drafting.t() -> checkpoint_action())

  @type t :: %__MODULE__{
          executor: module(),
          executor_opts: keyword(),
          orchid_adapters: [
            ({Orchid.Recipe.t(), keyword()}, __MODULE__.t() ->
               {Orchid.Recipe.t(), keyword()})
            | ({Orchid.Recipe.t(), keyword()} -> {Orchid.Recipe.t(), keyword()})
          ],
          orchid_baggage: map(),
          orchid_opts: keyword(),
          concurrency: pos_integer(),
          timeout: timeout(),
          name: Oi.name() | nil,
          checkpoint: checkpoint() | nil
        }

  defstruct executor: Oi.Executor.Sync,
            executor_opts: [],
            orchid_adapters: [],
            orchid_baggage: %{},
            orchid_opts: [],
            concurrency: System.schedulers_online(),
            timeout: :infinity,
            name: nil,
            checkpoint: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    name = Keyword.get(opts, :name)

    executor = Keyword.get(opts, :executor, Oi.Executor.Sync)
    executor_opts = Keyword.get(opts, :executor_opts, [])

    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())

    executor_opts =
      Keyword.put_new(executor_opts, :concurrency, concurrency)

    timeout = Keyword.get(opts, :timeout, :infinity)
    executor_opts = Keyword.put_new(executor_opts, :timeout, timeout)

    %__MODULE__{
      name: name,
      executor: executor,
      executor_opts: executor_opts,
      orchid_adapters: Keyword.get(opts, :orchid_adapters, []),
      orchid_baggage: opts |> Keyword.get(:orchid_baggage, []) |> Enum.into(%{}),
      orchid_opts: Keyword.get(opts, :orchid_opts, []),
      concurrency: concurrency,
      timeout: timeout,
      checkpoint: Keyword.get(opts, :checkpoint)
    }
  end

  @doc """
  Build a `Drafting` from user `:data` and compiled graph topology.
  Delegates to `Options.build_drafting_inputs/2`.
  """
  @spec build_drafting(data(), Oi.Compiled.t()) ::
          {:ok, Drafting.t()} | {:error, term()}
  def build_drafting(data, %Oi.Compiled{} = compiled) do
    with {:ok, {memory_io, interventions_io}} <- Options.build_drafting_inputs(compiled, data) do
      {:ok, Drafting.new(memory_io, interventions_io)}
    end
  end

  @doc """
  Assemble keyword opts for `Orchid.run/3`.
  Delegates to `Options.assemble_run_opts/3`.
  """
  @spec assemble_run_opts(t(), Drafting.t()) :: keyword()
  def assemble_run_opts(%__MODULE__{} = conf, %Drafting{} = drafting) do
    Options.assemble_run_opts(conf.orchid_opts, conf, drafting)
  end

  @doc """
  Run every plugin in order over the `{recipe, run_opts}` tuple.
  Each plugin may rewrite the recipe or append to run_opts.
  """
  @spec apply_orchid_adapters(t(), {Orchid.Recipe.t(), keyword()}) ::
          {Orchid.Recipe.t(), keyword()}
  def apply_orchid_adapters(%__MODULE__{orchid_adapters: orchid_adapters} = conf, orchid_tuple) do
    Enum.reduce(orchid_adapters, orchid_tuple, fn plugin, acc ->
      case plugin do
        plugin_func when is_function(plugin_func, 2) ->
          plugin_func.(acc, conf)

        plugin_func when is_function(plugin_func, 1) ->
          plugin_func.(acc)
      end
    end)
  end
end
