defmodule Oi.Compile.Planning do
  @moduledoc """
  Execution plan built from compiled Bundles.

  Bundles sharing the same topological depth are grouped into stages.
  Tasks within a stage run in parallel; stages execute sequentially
  (barrier synchronization).

  ## Relationship to `Bundle.compile_graph/2`

  `Bundle.compile_graph/2` already guarantees the graph is a DAG via
  topological sort.  `Planning.build/1` does NOT re-detect cycles — its
  job is to determine which bundles can run in parallel by assigning
  levels based on `requires` / `exports` cross-references.

  The `fuel` parameter in `do_assign/4` is a defensive guard: the
  iteration count is bounded by `length(bundles)`, which is always
  sufficient for any DAG (longest path ≤ node count).  If the graph
  somehow contained a cycle despite the earlier topo sort, the fuel
  guard prevents infinite recursion.
  """

  alias Oi.Compile.Bundle

  defmodule Stage do
    @moduledoc """
    A single execution barrier.

    Contains all Bundle tasks at the same topological depth.
    """

    @type task :: Bundle.t()
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
  Build a Plan from a flat list of Bundles.

  Assigns each bundle a level based on its upstream dependencies
  (via `requires` / `exports`).  Bundles at the same level have no
  cross-dependencies and can execute in parallel within a stage.

  The graph must already be a DAG — cycle detection here is defensive
  (see moduledoc).  Callers should ensure `Bundle.compile_graph/2` ran
  first to verify acyclicity.
  """
  @spec build([Bundle.t()]) :: {:ok, Plan.t()} | {:error, :cycle_detected}
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
          |> Enum.flat_map(&upstream_ids(&1, producers))
          |> Enum.uniq()

        {b.node_ids, upstream}
      end)

    case assign_levels(bundles, deps) do
      {:ok, level_of} -> {:ok, Plan.new(to_stages(bundles, level_of))}
      :error -> {:error, :cycle_detected}
    end
  end

  defp upstream_ids(key, producers) do
    # external dependency produces nothing
    case producers[key] do
      nil -> []
      ids -> [ids]
    end
  end

  defp assign_levels(bundles, deps) do
    ids = Enum.map(bundles, & &1.node_ids)
    do_assign(ids, deps, %{}, length(ids))
  end

  # Defensive guard: fuel < 0 means the iteration count exceeded the
  # bundle count, which is impossible for a DAG.  This can only be
  # reached if Bundle.compile_graph/2 failed to catch a cycle.
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
