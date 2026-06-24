defmodule Oi.Session do
  @moduledoc """
  Session seperates whole application into seperal spaces where contains different
  steps, independent [symbionts](https://orchid-symbiont.hexdocs.pm/) and storages.
  """
  import Oi.Registry

  @spec start(Oi.name(), keyword()) :: :ignore | {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  def start(oi_name, opts \\ []) do
    case Registry.lookup(Oi.Registry, instances(oi_name)) do
      [{pid, _}] ->
        {:error, {:already_started, pid}}

      [] ->
        instances_spec = %{
          id: oi_name,
          start: {Oi.Session.Instances, :start_link, [oi_name, opts]}
        }

        DynamicSupervisor.start_child(Oi.SessionSupervisor, instances_spec)
    end
  end

  @spec stop(Oi.name()) :: :ok | {:error, :not_found | :session_not_found}
  def stop(oi_name) do
    case Registry.lookup(Oi.Registry, instances(oi_name)) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Oi.SessionSupervisor, pid)
      [] -> {:error, :session_not_found}
    end
  end

  @spec resolve(Oi.name()) :: {:error, :session_not_found} | {:ok, pid()}
  def resolve(oi_name) do
    case Registry.lookup(Oi.Registry, server(oi_name)) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :session_not_found}
    end
  end

  @spec instances(Oi.name()) :: Oi.Registry.key()
  def instances(oi), do: key(oi, :instances)
  @spec instances_tuple(Oi.name()) :: Oi.Registry.via_tuple()
  def instances_tuple(oi), do: via(oi, :instances)

  @spec server(Oi.name()) :: Oi.Registry.key()
  def server(oi), do: key(oi, :server)
  @spec server_tuple(Oi.name()) :: Oi.Registry.via_tuple()
  def server_tuple(oi), do: via(oi, :server)

  @spec tasks_tuple(Oi.name()) :: Oi.Registry.via_tuple()
  def tasks_tuple(oi), do: via(oi, :task_sup)
end
