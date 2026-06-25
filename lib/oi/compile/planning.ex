defmodule Oi.Compiler.Planning do
  @moduledoc """
  Execution plan built from compiled RecipeBundles.

  Bundles sharing the same topological depth are grouped into stages.
  Tasks within a stage run in parallel; stages execute sequentially
  (barrier synchronization).
  """

  defmodule Stage do
    @moduledoc """
    A single execution barrier.

    Contains all RecipeBundle tasks at the same topological depth.
    """
    alias Oi.Compiler.RecipeBundle

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
end
