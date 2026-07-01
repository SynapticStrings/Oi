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

  # TODO
  # 确定要 resolve 谁
  @spec resolve(Oi.name()) :: {:error, :session_not_found} | {:ok, pid()}
  def resolve(oi_name) do
    case Registry.lookup(Oi.Runtime.Registry, instances(oi_name)) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :session_not_found}
    end
  end

  # list/0

  # info/1

  # with_session/3
  # Oi.Session.with_session("tenant-1", fn session ->
  #   Oi.run(graph,
  #     ...
  #     )
  # end, opts
  # )

  # ---- Helpers ----

  @spec instances(Oi.name()) :: Oi.Runtime.Registry.key()
  def instances(oi), do: key(oi, :instances)
  @spec instances_tuple(Oi.name()) :: Oi.Runtime.Registry.via_tuple()
  def instances_tuple(oi), do: via(oi, :instances)

  # @spec server(Oi.name()) :: Oi.Runtime.Registry.key()
  # def server(oi), do: key(oi, :server)
  # @spec server_tuple(Oi.name()) :: Oi.Runtime.Registry.via_tuple()
  # def server_tuple(oi), do: via(oi, :server)

  @spec tasks_tuple(Oi.name()) :: Oi.Runtime.Registry.via_tuple()
  def tasks_tuple(oi), do: via(oi, :task_sup)

  # ---- Symbiont related ----

  # def register_symbiont(oi_name, ...)

  # ---- Oi dispatch config related ----
end
