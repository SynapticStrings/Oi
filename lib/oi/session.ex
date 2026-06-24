defmodule Oi.Session do
  import Oi.Registry

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

  def stop(oi_name) do
    case Registry.lookup(Oi.SessionRegistry, instances(oi_name)) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Oi.SessionSupervisor, pid)
      [] -> {:error, :session_not_found}
    end
  end

  def resolve(oi_name) do
    case Registry.lookup(Oi.SessionRegistry, server(oi_name)) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :session_not_found}
    end
  end

  def instances(oi), do: key(oi, :instances)
  def instances_tuple(oi), do: via(oi, :instances)

  def server(oi), do: key(oi, :server)
  def server_tuple(oi), do: via(oi, :server)

  def tasks_tuple(oi), do: via(oi, :task_sup)
end
