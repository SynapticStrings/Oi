defmodule Oi.Dispatch.Config do
  @moduledoc """
  Immutable dispatch configuration.

  Built once at the dispatch boundary, threaded to Worker and the plugin
  chain. Controls executor selection, concurrency, timeout, and Orchid
  plugin pipeline.

  ## Options

    * `:executor`       — module implementing `Oi.Executor` (default: `Oi.Executor.Sync`)
    * `:executor_opts`  — keyword opts passed to executor's `run/3`
    * `:orchid_adapters`        — ordered list of `fn {recipe, opts}, conf -> {recipe, opts}` adapters
    * `:orchid_baggage` — map merged into every Orchid run's baggage
    * `:orchid_opts`    — extra keyword opts forwarded to `Orchid.run/3`
    * `:concurrency`    — fallback for executor if `:executor_opts` has none
    * `:timeout`        — fallback for executor if `:executor_opts` has none
  """

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
          name: Oi.name() | nil
        }

  defstruct executor: Oi.Executor.Sync,
            executor_opts: [],
            orchid_adapters: [],
            orchid_baggage: %{},
            orchid_opts: [],
            concurrency: System.schedulers_online(),
            timeout: :infinity,
            name: nil

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
      timeout: timeout
    }
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
