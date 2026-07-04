defmodule Oi.Runtime.Session.Storage do
  @moduledoc false
  # Per-session storage Agent — owns ETS-backed Meta/Blob stores so
  # cached results survive across execute calls within a session.

  use Agent

  @compile {:no_warn_undefined, OrchidStratum.MetaStorage.EtsAdapter}
  @compile {:no_warn_undefined, OrchidStratum.BlobStorage.EtsAdapter}

  alias Oi.Runtime.Session

  @doc false
  def start_link({oi_name, opts}) do
    Agent.start_link(fn -> init_stores(oi_name, opts) end,
      name: Session.storage_tuple(oi_name)
    )
  end

  @doc """
  Returns the session's storage map suitable for merging into
  `orchid_baggage`:

      %{
        meta_store: {OrchidStratum.MetaStorage.EtsAdapter, ref},
        blob_store: {OrchidStratum.BlobStorage.EtsAdapter, ref}
      }
  """
  def get(oi_name) do
    Agent.get(Session.storage_tuple(oi_name), & &1)
  end

  # ---- Helpers ----

  defp init_stores(_oi_name, opts) do
    %{
      meta_store: Keyword.get(opts, :meta_store, default_meta_store()),
      blob_store: Keyword.get(opts, :blob_store, default_blob_store())
    }
  end

  defp default_meta_store do
    {OrchidStratum.MetaStorage.EtsAdapter, OrchidStratum.MetaStorage.EtsAdapter.init()}
  end

  defp default_blob_store do
    {OrchidStratum.BlobStorage.EtsAdapter, OrchidStratum.BlobStorage.EtsAdapter.init()}
  end
end
