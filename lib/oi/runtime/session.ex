defmodule Oi.Runtime.Session do
  @moduledoc """
  Session separates the whole application into several spaces where contains different
  steps, independent [symbionts](https://orchid-symbiont.hexdocs.pm/) and storages.
  """
  import Oi.Runtime.Registry

  @spec start(Oi.name(), keyword()) ::
          :ignore | {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  def start(oi_name, opts \\ []) do
    case Registry.lookup(Oi.Runtime.Registry, instances(oi_name)) do
      [{pid, _}] ->
        {:error, {:already_started, pid}}

      [] ->
        instances_spec = %{
          id: oi_name,
          start: {Oi.Runtime.Session.Instances, :start_link, [oi_name, opts]}
        }

        DynamicSupervisor.start_child(Oi.Runtime.SessionSupervisor, instances_spec)
    end
  end

  @spec stop(Oi.name()) :: :ok | {:error, :session_not_found}
  def stop(oi_name) do
    with [{pid, _}] <- Registry.lookup(Oi.Runtime.Registry, instances(oi_name)),
         :ok <- DynamicSupervisor.terminate_child(Oi.Runtime.SessionSupervisor, pid) do
      :ok
    else
      _ -> {:error, :session_not_found}
    end
  end

  @spec ensure_started(binary(), keyword()) ::
          :ignore | {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  def ensure_started(oi_name, opts \\ []) do
    case start(oi_name, opts) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      any -> any
    end
  end

  @spec resolve(Oi.name()) :: {:error, :session_not_found} | {:ok, pid()}
  def resolve(oi_name) do
    case Registry.lookup(Oi.Runtime.Registry, instances(oi_name)) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :session_not_found}
    end
  end

  @doc """
  Ensures a session is started and calls `fun` with session-scoped opts.

  `fun` receives a keyword list suitable for merging into `Oi.run/2` or
  `Oi.execute/2`:

    * `:executor` — `Oi.Executor.TaskSup`
    * `:executor_opts` — `[sup: Session.tasks_tuple(name)]`
    * `:orchid_baggage` — `%{scope_id: name}`
    * `:name` — the session name

  The session is **not** stopped when `fun` returns — sessions are
  designed to be long-lived. Call `stop/1` when done.

  ## Example

      Session.with_session("tenant-1", fn session ->
        Oi.run(graph, Keyword.merge(session, data: %{greeter: %{name: "Alice"}}))
      end)
  """
  @spec with_session(Oi.name(), keyword(), (keyword() -> result)) :: result when result: term()
  def with_session(oi_name, opts \\ [], fun) when is_function(fun, 1) do
    {:ok, _pid} = ensure_started(oi_name, opts)

    baggage =
      case storage(oi_name) do
        nil -> %{scope_id: oi_name}
        stores -> Map.merge(%{scope_id: oi_name}, stores)
      end

    session_opts = [
      executor: Oi.Executor.TaskSup,
      executor_opts: [sup: tasks_tuple(oi_name)],
      orchid_baggage: baggage,
      name: oi_name
    ]

    fun.(session_opts)
  end

  # ---- Helpers ----

  @spec instances(Oi.name()) :: Oi.Runtime.Registry.key()
  def instances(oi), do: key(oi, :instances)
  @spec instances_tuple(Oi.name()) :: Oi.Runtime.Registry.via_tuple()
  def instances_tuple(oi), do: via(oi, :instances)

  @spec tasks_tuple(Oi.name()) :: Oi.Runtime.Registry.via_tuple()
  def tasks_tuple(oi), do: via(oi, :task_sup)

  @doc """
  Returns the per-session storage map if `orchid_stratum` is available.

  The map can be merged into `orchid_baggage`:

      %{meta_store: {EtsAdapter, ref}, blob_store: {EtsAdapter, ref}}

  Returns `nil` when `orchid_stratum` is not loaded or the session
  was started without storage.
  """
  @spec storage(Oi.name()) :: map() | nil
  def storage(oi_name) do
    if Code.ensure_loaded?(OrchidStratum.MetaStorage.EtsAdapter) do
      Oi.Runtime.Session.Storage.get(oi_name)
    end
  end

  @doc false
  @spec storage_tuple(Oi.name()) :: Oi.Runtime.Registry.via_tuple()
  def storage_tuple(oi), do: via(oi, :storage)
end
