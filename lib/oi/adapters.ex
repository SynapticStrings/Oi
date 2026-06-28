defmodule Oi.Adapters do
  @moduledoc """
  Ready-to-use orchid_adapters.

  Pass these as `orchid_adapters: [&Oi.Adapters.orchid_intervention/1]`
  in Oi.execute/2 opts or Config.new/1.
  """

  # ---- OrchidIntervention ----

  @doc """
  Prepends `Orchid.Hook.ApplyInterventions` to `:global_hooks_stack`
  when `:orchid_intervention` is available at runtime.

  No-op otherwise.
  """
  @spec orchid_intervention({Orchid.Recipe.t(), keyword()}) :: {Orchid.Recipe.t(), keyword()}
  def orchid_intervention(acc) do
    if Code.ensure_loaded?(Orchid.Hook.ApplyInterventions) do
      ensure_hook_prepended(acc, Orchid.Hook.ApplyInterventions)
    else
      acc
    end
  end

  # ---- OrchidStratum ----

  @doc """
  Prepends `OrchidStratum.BypassHook` to `:global_hooks_stack`
  when `:orchid_stratum` is available at runtime.

  No-op otherwise.
  """
  @spec orchid_stratum({Orchid.Recipe.t(), keyword()}) :: {Orchid.Recipe.t(), keyword()}
  def orchid_stratum(acc) do
    if Code.ensure_loaded?(OrchidStratum.BypassHook) do
      ensure_hook_prepended(acc, OrchidStratum.BypassHook)
    else
      acc
    end
  end

  # ---- Combined: OrchidIntervention + OrchidStratum ----

  @doc """
  Prepends both hooks when available, respecting the layering order:

      OrchidIntervention => OrchidStratum => ... => Core

  Equivalent to `orchid_adapters: [&orchid_stratum/1, &orchid_intervention/1]`
  but in a single adapter call.
  """
  @spec orchid_intervention_and_stratum({Orchid.Recipe.t(), keyword()}) :: {Orchid.Recipe.t(), keyword()}
  def orchid_intervention_and_stratum(acc) do
    acc
    |> orchid_stratum()
    |> orchid_intervention()
  end

  # ---- Helpers ----

  defp ensure_hook_prepended({recipe, opts}, hook) do
    hooks = Keyword.get(opts, :global_hooks_stack, [])

    if hook in hooks do
      {recipe, opts}
    else
      {recipe, Keyword.put(opts, :global_hooks_stack, [hook | hooks])}
    end
  end
end
