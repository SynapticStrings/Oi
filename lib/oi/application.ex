defmodule Oi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Storage processes.
      Oi.Runtime.Registry,

      # Manage sessions.
      {DynamicSupervisor, name: Oi.Runtime.SessionSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Oi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
