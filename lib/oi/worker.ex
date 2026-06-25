defmodule Oi.Worker do
  @moduledoc """
  Executes a single RecipeBundle in isolation.

  Resolves dependencies from the Drafting, applies the plugin pipeline
  via Configurator, then delegates to `Orchid.run/3`.
  """

  alias Oi.Topology.Graph.PortRef
  alias Oi.Compiler.RecipeBundle
  alias Oi.Drafting
  alias Oi.Configurator

  @type delta :: %{Drafting.io_key() => Orchid.Param.t()}

  @spec run(RecipeBundle.t(), Drafting.t(), Configurator.t()) ::
          {:ok, delta()} | {:error, term()}
  def run(%RecipeBundle{} = bundle, %Drafting{} = drafting, %Configurator{} = conf) do
    intervention_by_orchid_key =
      conf.interventions
      |> Enum.filter(fn {{:port, node, _}, _} -> node in bundle.node_ids end)
      |> Map.new(fn {k, v} -> {PortRef.to_orchid_key(k), v} end)

    with {:ok, dynamic_inputs} <-
           resolve_dependencies(bundle, drafting, intervention_by_orchid_key) do
      baggage =
        conf.orchid_baggage
        |> Map.merge(%{interventions: intervention_by_orchid_key})

      base_opts = Keyword.merge(conf.orchid_opts, baggage: baggage)

      {recipe, final_opts} = Configurator.apply_plugins(conf, {bundle.recipe, base_opts})
      run_orchid(recipe, dynamic_inputs, final_opts)
    end
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
         %RecipeBundle{inputs: inputs},
         %Drafting{memory: mem},
         interventions
       ) do
    inputs
    |> Enum.reduce_while({:ok, []}, fn orchid_key, {:ok, acc} ->
      cond do
        Map.has_key?(mem, orchid_key) ->
          {:cont, {:ok, [Map.fetch!(mem, orchid_key) | acc]}}

        param = resolve_from_intervention(orchid_key, interventions) ->
          {:cont, {:ok, [param | acc]}}

        true ->
          {:halt, {:error, {:missing_input, orchid_key}}}
      end
    end)
    |> case do
      {:ok, params} -> {:ok, Enum.reverse(params)}
      {:error, _} = err -> err
    end
  end

  defp resolve_from_intervention(orchid_key, interventions) do
    case Map.get(interventions, orchid_key) do
      {:input, %Orchid.Param{} = param} ->
        %{param | name: orchid_key}

      {:input, payload} ->
        Orchid.Param.new(orchid_key, :any, payload)

      nil ->
        nil
    end
  end
end
