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
  @spec build([RecipeBundle.t()]) :: {:ok, Plan.t()}
  def build(bundles) do
    stages =
      bundles
      |> Enum.with_index()
      |> Enum.group_by(fn {_bundle, idx} -> idx end, fn {bundle, _idx} -> bundle end)
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map(fn {index, tasks} -> %Stage{index: index, tasks: tasks} end)

    {:ok, Plan.new(stages)}
  end
end
