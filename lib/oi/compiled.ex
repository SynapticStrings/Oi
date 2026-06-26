defmodule Oi.Compiled do
  @moduledoc """
  Static compilation product: bundles + execution plan.

  Built once from `Oi.compile/2`, reusable across multiple `Oi.execute/2`
  calls with different inputs/interventions.
  """

  alias Oi.Compile.{Bundle, Planning}
  alias Oi.Topology.Graph.Edge

  @type t :: %__MODULE__{
          bundles: [Bundle.t()],
          plan: Planning.Plan.t(),
          edges: MapSet.t(Edge.t())
        }

  defstruct [:bundles, :plan, edges: MapSet.new()]
end
