defmodule Oi.Runtime.Session.Instances do
  @moduledoc "Instance Supervisor."
  use Supervisor

  def start_link(oi_name, opts) do
    Supervisor.start_link(__MODULE__, {oi_name, opts},
      name: Oi.Runtime.Session.instances_tuple(oi_name)
    )
  end

  @impl true
  def init({oi_name, opts}) do
    children = [
      {Task.Supervisor, name: Oi.Runtime.Session.tasks_tuple(oi_name)}
    ]

    children =
      if Code.ensure_loaded?(OrchidSymbiont.Runtime) do
        [
          {OrchidSymbiont.Runtime,
           scope_id: oi_name, strict_mode: Keyword.get(opts, :orchid_symbiont_strict, false)}
          | children
        ]
      else
        children
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
