defmodule Oi.Worker do
  @moduledoc """
  Executes a single RecipeBundle in isolation.

  Resolves dependencies from the Drafting, applies the plugin pipeline
  via Configurator, then delegates to `Orchid.run/3`.
  """

  alias Oi.Topology.Graph.PortRef
  alias Oi.Compiler.RecipeBundle
  alias Oi.Workspace.Drafting
  alias Oi.Configurator

  @spec run(RecipeBundle.t(), Drafting.t(), Configurator.t()) ::
          {:ok, map()} | {:error, term()}
  def run(%RecipeBundle{} = bundle, %Drafting{} = drafting, %Configurator{} = conf) do
    intervention_by_orchid_key =
      Map.new(bundle.interventions, fn {k, v} -> {PortRef.to_orchid_key(k), v} end)

    dynamic_inputs = resolve_dependencies(bundle, drafting, intervention_by_orchid_key)

    baggage =
      conf.orchid_baggage
      |> Map.merge(%{interventions: intervention_by_orchid_key})

    base_opts = Keyword.merge(conf.orchid_opts, baggage: baggage)

    {recipe, final_opts} = Configurator.apply_plugins(conf, {bundle.recipe, base_opts})

    case Orchid.run(recipe, dynamic_inputs, final_opts) do
      {:ok, results} -> {:ok, results}
      {:error, reason} -> {:error, {:orchid_run_failed, reason}}
    end
  end

  defp resolve_dependencies(%RecipeBundle{requires: requires}, %Drafting{memory: mem}, interventions) do
    Enum.map(requires, fn orchid_key ->
      case Map.fetch(mem, orchid_key) do
        {:ok, val} ->
          Orchid.Param.new(orchid_key, :any, val)

        :error ->
          resolve_from_intervention(orchid_key, interventions)
      end
    end)
  end

  defp resolve_from_intervention(orchid_key, interventions) do
    case Map.get(interventions, orchid_key) do
      %{input: %Orchid.Param{} = param} -> %{param | name: orchid_key}
      %{input: raw} when not is_nil(raw) -> Orchid.Param.new(orchid_key, :any, raw)
      _ -> Orchid.Param.new(orchid_key, :void, nil)
    end
  end
end
