defmodule Oi.Result do
  @moduledoc """
  Execution result: the final drafting memory.

  `memory` is keyed by Orchid io_key, values are `Orchid.Param.t()`.
  """
alias Oi.Topology.Graph.PortRef

  @type t :: %__MODULE__{
          memory: %{String.t() => Orchid.Param.t()}
        }

  defstruct [:memory]

  @spec new(%{String.t() => Orchid.Param.t()}) :: t()
  def new(memory), do: %__MODULE__{memory: memory}

  @spec fetch(t(), String.t()) :: {:ok, Orchid.Param.t()} | :error
  def fetch(%__MODULE__{memory: mem}, key), do: Map.fetch(mem, key)

  @spec reify(t(), String.t()) :: {:ok, term()} | :error
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
