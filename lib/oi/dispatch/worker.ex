defmodule Oi.Dispatch.Worker do
  @moduledoc """
  Executes a single Bundle in isolation.

  Resolves dependencies from the Drafting, applies the plugin pipeline
  via Config, then delegates to `Orchid.run/3`.
  """

  alias Oi.Compile.Bundle
  alias Oi.Dispatch.Drafting
  alias Oi.Dispatch.Config

  @type delta :: %{Oi.Dispatch.Drafting.io_key() => Orchid.Param.t()}

  @spec run(Bundle.t(), Drafting.t(), Config.t()) ::
          {:ok, delta()} | {:error, term()}
  def run(%Bundle{} = bundle, %Drafting{} = drafting, %Config{} = conf) do
    with {:ok, dynamic_inputs} <-
           resolve_dependencies(bundle, drafting) do
      base_opts =
        conf.orchid_opts
        |> Keyword.update(:baggage, %{interventions: drafting.interventions}, fn baggage ->
          baggage
          |> Enum.into(%{})
          |> Map.put(:interventions, drafting.interventions)
        end)

      {recipe, final_opts} = Config.apply_orchid_adapters(conf, {bundle.recipe, base_opts})
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
         %Bundle{inputs: inputs},
         %Drafting{memory: mem}
       ) do
    inputs
    |> Enum.reduce_while({:ok, []}, fn orchid_key, {:ok, acc} ->
      if Map.has_key?(mem, orchid_key) do
        {:cont, {:ok, [Map.fetch!(mem, orchid_key) | acc]}}
      else
        {:halt, {:error, {:missing_input, orchid_key}}}
      end
    end)
    |> case do
      {:ok, params} -> {:ok, Enum.reverse(params)}
      {:error, _} = err -> err
    end
  end
end
