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

    session_opts = [
      executor: Oi.Executor.TaskSup,
      executor_opts: [sup: tasks_tuple(oi_name)],
      orchid_baggage: %{scope_id: oi_name},
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
end
