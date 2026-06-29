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
  Prepends `OrchidStratum.BypassHook` to `:global_hooks_stack` and
  auto-initialises ETS-backed Meta/Blob stores in baggage when
  `:orchid_stratum` is available at runtime.

  ## Storage auto-init

  If `:meta_store` / `:blob_store` are already present in baggage they
  are left untouched (user-supplied adapters win). Otherwise ETS-backed
  defaults (`MetaStorage.EtsAdapter` / `BlobStorage.EtsAdapter`) are
  created and inserted.

  No-op when `orchid_stratum` is not available.
  """
  @spec orchid_stratum({Orchid.Recipe.t(), keyword()}) :: {Orchid.Recipe.t(), keyword()}
  def orchid_stratum(acc) do
    if Code.ensure_loaded?(OrchidStratum.BypassHook) do
      acc
      |> ensure_stratum_storage()
      |> ensure_hook_prepended(OrchidStratum.BypassHook)
    else
      acc
    end
  end

  # ---- OrchidSymbiont ----

  @doc """
  Prepends `OrchidSymbiont.Hooks.Injector` to `:global_hooks_stack`
  when `:orchid_symbiont` is available at runtime.

  No-op otherwise.

  Use this when your graph contains symbiont steps that need model
  handler injection:

      orchid_adapters: [&Oi.Adapters.orchid_symbiont/1]
  """
  @spec orchid_symbiont({Orchid.Recipe.t(), keyword()}) :: {Orchid.Recipe.t(), keyword()}
  def orchid_symbiont(acc) do
    if Code.ensure_loaded?(OrchidSymbiont.Hooks.Injector) do
      ensure_hook_prepended(acc, OrchidSymbiont.Hooks.Injector)
    else
      acc
    end
  end

  # ---- Combined: OrchidIntervention + OrchidStratum ----

  @doc """
  Prepends both hooks when available, respecting the layering order:

      OrchidStratum => OrchidIntervention => ... => Core

  Includes auto-init of ETS-backed Meta/Blob stores (same as
  `orchid_stratum/1`).

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

  # Auto-initialises ETS-backed Meta/Blob stores in baggage unless
  # the user has already supplied their own adapters.
  # Uses `put_new_lazy` so we don't init tables unnecessarily.
  defp ensure_stratum_storage({recipe, opts}) do
    baggage = Keyword.get(opts, :baggage, %{}) || %{}

    baggage =
      baggage
      |> Map.put_new_lazy(:meta_store, fn ->
        {OrchidStratum.MetaStorage.EtsAdapter, OrchidStratum.MetaStorage.EtsAdapter.init()}
      end)
      |> Map.put_new_lazy(:blob_store, fn ->
        {OrchidStratum.BlobStorage.EtsAdapter, OrchidStratum.BlobStorage.EtsAdapter.init()}
      end)

    {recipe, Keyword.put(opts, :baggage, baggage)}
  end
end
