defmodule Oi.Compiled do
  @moduledoc """
  Static compilation product: bundles + execution plan.

  Built once from `Oi.compile/2`, reusable across multiple `Oi.execute/2`
  calls with different inputs/interventions.
  """

  alias Oi.Compiler.RecipeBundle
  alias Oi.Planning

  @type t :: %__MODULE__{
          bundles: [RecipeBundle.t()],
          plan: Planning.Plan.t()
        }

  defstruct [:bundles, :plan]
end
