defmodule Oi.Result do
  @moduledoc """
  Execution result: the final drafting memory.

  `memory` is keyed by Orchid io_key, values are `Orchid.Param.t()`.
  """

  alias Oi.Topology.Graph.PortRef

  @type t :: %__MODULE__{
          memory: %{Orchid.Step.io_key() => Orchid.Param.t()}
        }

  defstruct [:memory]

  @spec new(%{Orchid.Step.io_key() => Orchid.Param.t()}) :: t()
  def new(memory) when is_map(memory), do: %__MODULE__{memory: memory}

  @spec fetch(t(), Orchid.Step.io_key()) :: {:ok, Orchid.Param.t()} | {:error, :not_found}
  def fetch(%__MODULE__{memory: mem}, key) do
    case Map.fetch(mem, key) do
      {:ok, val} -> {:ok, val}
      :error -> {:error, :not_found}
    end
  end

  @spec reify(t(), Orchid.Step.io_key()) :: {:ok, term()} | {:error, :not_found}
  def reify(%__MODULE__{} = res, key) when is_binary(key) or is_atom(key) do
    case fetch(res, key) do
      {:ok, %Orchid.Param{payload: payload}} -> {:ok, payload}
      err -> err
    end
  end

  def reify(res, {node, port}) do
    reify(res, PortRef.to_orchid_key({:port, node, port}))
  end
end
