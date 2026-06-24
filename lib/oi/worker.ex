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

  @type delta :: %{Drafting.io_key() => Orchid.Param.t()}

  @spec run(RecipeBundle.t(), Drafting.t(), Configurator.t()) ::
          {:ok, delta()} | {:error, term()}
  def run(%RecipeBundle{} = bundle, %Drafting{} = drafting, %Configurator{} = conf) do
    intervention_by_orchid_key =
      Map.new(bundle.interventions, fn {k, v} -> {PortRef.to_orchid_key(k), v} end)

    IO.puts("#{inspect(intervention_by_orchid_key |> Enum.map(fn {k, _} -> k end))}  #{inspect(bundle.inputs)}")

    dynamic_inputs = resolve_dependencies(bundle, drafting, intervention_by_orchid_key)

    baggage =
      conf.orchid_baggage
      |> Map.merge(%{interventions: intervention_by_orchid_key})

    base_opts = Keyword.merge(conf.orchid_opts, baggage: baggage)

    {recipe, final_opts} = Configurator.apply_plugins(conf, {bundle.recipe, base_opts})

    run_orchid(recipe, dynamic_inputs, final_opts)
  end

  defp run_orchid(recipe, params, opts) do
    recipe
    |> Orchid.run(params, opts)
    |> normalize_payload()
    |> case do
      {:ok, param_map} ->
        {:ok, param_map}

      {:error, %Orchid.Error{} = err} ->
        {:error, {:orchid_error, recipe.name, err}}
    end
  end

  defp normalize_payload(%Orchid.Operon.Response{payload: payload}), do: payload
  defp normalize_payload(payload), do: payload

  defp resolve_dependencies(
         %RecipeBundle{requires: requires},
         %Drafting{memory: mem},
         interventions
       ) do
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
      {:input, %Orchid.Param{} = param} ->
        %{param | name: orchid_key}

      {:input, payload} when not is_nil(payload) ->
        Orchid.Param.new(orchid_key, :any, payload)

      _ ->
        Orchid.Param.new(orchid_key, :void, nil)
    end
  end
end
