defmodule Oi.Workspace.Drafting do
  @moduledoc """
  Temporary result store for a single dispatch pass.

  Replaces Quincunx's Blackboard. Holds computed outputs keyed by
  `{node_or_cluster_id, orchid_io_key}`. Workers read dependencies
  from here; Dispatcher merges results back after each stage.

  Lifecycle: created fresh per `Oi.dispatch/2`, discarded after results
  are collected by the caller.
  """

  @type addr :: {term(), Orchid.Step.io_key()}
  @type t :: %__MODULE__{
          memory: %{addr() => Orchid.Param.t() | any()}
        }

  defstruct memory: %{}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec put(t(), %{addr() => Orchid.Param.t() | any()}) :: t()
  def put(%__MODULE__{} = drafting, new_data) when is_map(new_data) do
    %{drafting | memory: Map.merge(drafting.memory, new_data)}
  end

  @spec fetch(t(), addr()) :: {:ok, any()} | :error
  def fetch(%__MODULE__{memory: mem}, addr) do
    Map.fetch(mem, addr)
  end

  @spec fetch_many(t(), [addr()]) :: %{addr() => any()}
  def fetch_many(%__MODULE__{memory: mem}, addrs) do
    Map.new(addrs, fn addr -> {addr, Map.get(mem, addr)} end)
  end
end
