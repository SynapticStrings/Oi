defmodule Oi.Workspace.Planning do
  @moduledoc """
  Execution plan built from compiled RecipeBundles.

  Bundles sharing the same topological depth are grouped into stages.
  Tasks within a stage run in parallel; stages execute sequentially
  (barrier synchronization).
  """

  alias Oi.Compiler.RecipeBundle

  defmodule Stage do
    @moduledoc """
    A single execution barrier.

    Contains all RecipeBundle tasks at the same topological depth.
    """
    @type task :: RecipeBundle.t()
    @type t :: %__MODULE__{
            index: non_neg_integer(),
            tasks: [task()]
          }
    defstruct [:index, tasks: []]
  end

  defmodule Plan do
    @moduledoc "Ordered sequence of stages."
    @type t :: %__MODULE__{
            stages: [Stage.t()],
            total_tasks: non_neg_integer()
          }
    defstruct [:stages, total_tasks: 0]

    @spec new([Stage.t()]) :: t()
    def new(stages) do
      %__MODULE__{
        stages: stages,
        total_tasks: Enum.reduce(stages, 0, &(&2 + length(&1.tasks)))
      }
    end
  end

  @doc """
  Build a Plan from a flat list of RecipeBundles.

  Bundles are grouped by their position in the compiled output.
  Within a single workspace, all bundles form a linear sequence
  (one bundle per cluster). Bundles at the same index across
  different compilations would run in the same stage.

  For a single workspace (one graph → one compile call), each
  bundle is its own stage — they execute sequentially in topo order.
  """
  @spec build([RecipeBundle.t()]) :: {:ok, Plan.t()} | {:error, :cycle_detected}
  def build(bundles) do
    # producer_key => bundle.name
    # producer means its io_key
    producers =
      for b <- bundles, key <- b.exports, into: %{}, do: {key, b.node_ids}

    # bundle.name => [upstream bundle.name]
    deps =
      Map.new(bundles, fn b ->
        upstream =
          b.requires
          |> Enum.flat_map(fn key ->
            case producers[key] do
              # external dependency
              nil -> []

              ids -> [ids]
            end
          end)
          |> Enum.uniq()

        {b.node_ids, upstream}
      end)

    case assign_levels(bundles, deps) do
      {:ok, level_of} -> {:ok, Plan.new(to_stages(bundles, level_of))}
      :error -> {:error, :cycle_detected}
    end
  end

  defp assign_levels(bundles, deps) do
    ids = Enum.map(bundles, & &1.node_ids)
    do_assign(ids, deps, %{}, length(ids))
  end

  # max(fuel) <- num(bundle)
  # fuel < 0 -> has cycle
  defp do_assign(_ids, _deps, _levels, fuel) when fuel < 0, do: :error

  defp do_assign(ids, deps, levels, fuel) do
    {resolved, pending} =
      Enum.split_with(ids, fn id ->
        Enum.all?(deps[id], &Map.has_key?(levels, &1))
      end)

    cond do
      resolved == [] and pending != [] -> :error
      pending == [] -> {:ok, merge_levels(resolved, deps, levels)}
      true -> do_assign(pending, deps, merge_levels(resolved, deps, levels), fuel - 1)
    end
  end

  defp merge_levels(resolved, deps, levels) do
    Enum.reduce(resolved, levels, fn id, acc ->
      level =
        deps[id]
        |> Enum.map(&Map.fetch!(acc, &1))
        |> Enum.max(fn -> -1 end)
        |> Kernel.+(1)

      Map.put(acc, id, level)
    end)
  end

  defp to_stages(bundles, level_of) do
    bundles
    |> Enum.group_by(fn b -> level_of[b.node_ids] end)
    |> Enum.sort_by(fn {level, _} -> level end)
    |> Enum.map(fn {level, bs} -> %Stage{index: level, tasks: bs} end)
  end
end
