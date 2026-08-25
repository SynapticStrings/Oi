defmodule Oi.Result do
  @moduledoc """
  Execution result: the final drafting memory.

  `memory` is keyed by Orchid io_key, values are `Orchid.Param.t()`.

  `status` is `:complete` when every stage ran, or `:halted` when a
  `:checkpoint` function stopped the dispatch early — in that case
  `halted_at` holds the index of the stage that was not executed and
  `memory` holds everything produced up to that point.
  """

  alias Oi.Topology.Graph.PortRef

  @type t :: %__MODULE__{
          memory: %{Orchid.Step.io_key() => Orchid.Param.t()},
          status: :complete | :halted,
          halted_at: non_neg_integer() | nil
        }

  defstruct [:memory, status: :complete, halted_at: nil]

  @spec new(%{Orchid.Step.io_key() => Orchid.Param.t()}, keyword()) :: t()
  def new(memory, opts \\ []) when is_map(memory) do
    %__MODULE__{
      memory: memory,
      status: Keyword.get(opts, :status, :complete),
      halted_at: Keyword.get(opts, :halted_at)
    }
  end

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
