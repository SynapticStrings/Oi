defmodule Oi.Registry do
  @moduledoc "Local process storage for Oi sessions."
  # Inspired by Oban's Registry design.

  @type role :: nil | atom()
  @type key :: Oi.name() | {Oi.name(), role()}
  @type via_tuple :: {:via, Registry, {__MODULE__, key()}}

  def child_spec(_init_arg) do
    [keys: :unique, name: __MODULE__]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: __MODULE__)
  end

  @doc "Build a via tuple."
  @spec via(Oi.name(), role()) :: via_tuple()
  def via(oi_name, role \\ nil), do: {:via, Registry, {__MODULE__, key(oi_name, role)}}

  @spec key(Oi.name(), role()) :: key()
  def key(oi_name, nil), do: oi_name
  def key(oi_name, role), do: {oi_name, role}
end
