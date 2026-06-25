defmodule Oi.Result do
  @moduledoc """
  Execution result: the final drafting memory.

  `memory` is keyed by Orchid io_key, values are `Orchid.Param.t()`.
  """

  @type t :: %__MODULE__{
          memory: %{String.t() => Orchid.Param.t()}
        }

  defstruct [:memory]

  @spec new(%{String.t() => Orchid.Param.t()}) :: t()
  def new(memory), do: %__MODULE__{memory: memory}

  @spec fetch(t(), String.t()) :: {:ok, Orchid.Param.t()} | :error
  def fetch(%__MODULE__{memory: mem}, key), do: Map.fetch(mem, key)
end
