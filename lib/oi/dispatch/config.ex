defmodule Oi.Dispatch.Config do
  @moduledoc """
  Immutable dispatch configuration.

  Built once at the dispatch boundary, threaded to Worker and the plugin
  chain. Controls executor selection, concurrency, timeout, and Orchid
  plugin pipeline.

  ## Options

    * `:executor`       — module implementing `Oi.Executor` (default: `Oi.Executor.Sync`)
    * `:executor_opts`  — keyword opts passed to executor's `run/3`
    * `:plugins`        — ordered list of `{plugin, context}` tuples
    * `:orchid_baggage` — map merged into every Orchid run's baggage
    * `:orchid_opts`    — extra keyword opts forwarded to `Orchid.run/3`
    * `:concurrency`    — fallback for executor if `:executor_opts` has none
    * `:timeout`        — fallback for executor if `:executor_opts` has none
  """

  @type t :: %__MODULE__{
          executor: module(),
          executor_opts: keyword(),
          plugins: [
            {module(), context :: any()}
            | module()
            | {({Orchid.Recipe.t(), keyword(), context :: any()} ->
                  {Orchid.Recipe.t(), keyword()})}
            | ({Orchid.Recipe.t(), keyword()} -> {Orchid.Recipe.t(), keyword()})
          ],
          orchid_baggage: map(),
          orchid_opts: keyword(),
          concurrency: pos_integer(),
          timeout: timeout()
        }

  defstruct executor: Oi.Executor.Sync,
            executor_opts: [],
            plugins: [],
            orchid_baggage: %{},
            orchid_opts: [],
            concurrency: System.schedulers_online(),
            timeout: :infinity

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    executor = Keyword.get(opts, :executor, Oi.Executor.Sync)
    executor_opts = Keyword.get(opts, :executor_opts, [])

    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())

    executor_opts =
      Keyword.put_new(executor_opts, :concurrency, concurrency)

    timeout = Keyword.get(opts, :timeout, :infinity)
    executor_opts = Keyword.put_new(executor_opts, :timeout, timeout)

    %__MODULE__{
      executor: executor,
      executor_opts: executor_opts,
      plugins: Keyword.get(opts, :plugins, []),
      orchid_baggage: opts |> Keyword.get(:orchid_baggage, []) |> Enum.into(%{}),
      orchid_opts: Keyword.get(opts, :orchid_opts, []),
      concurrency: concurrency,
      timeout: timeout
    }
  end

  @doc """
  Run every plugin in order over the `{recipe, run_opts}` tuple.
  Each plugin may rewrite the recipe or append to run_opts.
  """
  @spec apply_plugins(t(), {Orchid.Recipe.t(), keyword()}) :: {Orchid.Recipe.t(), keyword()}
  def apply_plugins(%__MODULE__{plugins: plugins}, orchid_tuple) do
    Enum.reduce(plugins, orchid_tuple, fn plugin, acc ->
      case plugin do
        {plugin_module, context} when is_atom(plugin_module) ->
          plugin_module.apply_plugin(acc, context)

        plugin_module when is_atom(plugin_module) ->
          plugin_module.apply_plugin(acc, nil)

        {plugin_func, context} when is_function(plugin_func, 2) ->
          plugin_func.(acc, context)

        plugin_func when is_function(plugin_func, 1) ->
          plugin_func.(acc)
      end
    end)
  end
end
