defmodule Oi.Workspace.Drafting do
  @moduledoc """
  Temporary result store for a single dispatch pass.
  Holds computed outputs keyed by Orchid io_key (e.g. `"pred_step|result"`),
  which is already globally unique. Workers read dependencies from here;
  the dispatcher merges per-stage deltas back after each barrier.
  """

  @type io_key :: Orchid.Step.io_key()
  @type t :: %__MODULE__{memory: %{io_key() => Orchid.Param.t()}}

  defstruct memory: %{}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec new(%{io_key() => Orchid.Param.t()}) :: t()
  def new(initial) when is_map(initial), do: %__MODULE__{memory: initial}

  @doc "merge single delta(%{io_key => Orchid.Param})."
  @spec put(t(), %{io_key() => Orchid.Param.t()}) :: t()
  def put(%__MODULE__{memory: mem} = d, delta) when is_map(delta) do
    %{d | memory: Map.merge(mem, delta)}
  end

  @spec fetch(t(), io_key()) :: {:ok, Orchid.Param.t()} | :error
  def fetch(%__MODULE__{memory: mem}, key), do: Map.fetch(mem, key)

  @spec take(t(), [io_key()]) :: %{io_key() => Orchid.Param.t()}
  def take(%__MODULE__{memory: mem}, keys) do
    for k <- keys, Map.has_key?(mem, k), into: %{}, do: {k, Map.fetch!(mem, k)}
  end

  @doc """
  按 keys 投影出一个 param_map。区分『缺失』和『值为 nil』：
  缺失返回 error，nil 是合法值照常返回。
  """
  @spec resolve_many(t(), [io_key()]) ::
          {:ok, %{io_key() => Orchid.Param.t()}} | {:error, {:unresolved, [io_key()]}}
  def resolve_many(%__MODULE__{memory: mem}, keys) do
    {found, missing} = Enum.split_with(keys, &Map.has_key?(mem, &1))

    case missing do
      [] -> {:ok, Map.new(found, &{&1, Map.fetch!(mem, &1)})}
      _ -> {:error, {:unresolved, missing}}
    end
  end
end
