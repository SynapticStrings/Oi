defmodule Oi.Session.Instances do
  use Supervisor

  @impl true
  def init({oi_name, opts}) do
    children = [
      {OrchidSymbiont.Runtime,
       scope_id: oi_name, strict_mode: Keyword.get(opts, :orchid_symbiont_strict, false)},
      {Task.Supervisor, name: Oi.Session.tasks_tuple(oi_name)},
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
