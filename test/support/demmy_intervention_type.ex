defmodule OiTest.DummyInterventionType do
  @moduledoc false

  @behaviour OrchidIntervention.Operate

  @impl true
  def data_enable, do: {true, true}

  @impl true
  def merge(inner_data, intervention_data) do
    {:ok, "#{intervention_data}[#{inner_data}]"}
  end
end
