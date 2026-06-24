defmodule OiTest.DummySymbiontWorker do
  @moduledoc """
  Minimal GenServer worker for symbiont testing.
  Responds to `{:predict, input}` with `{:ok, "predicted(\#{input})"}`.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(_opts), do: {:ok, nil}

  @impl true
  def handle_call({:predict, input}, _from, state) do
    {:reply, {:ok, input}, state}
  end

  def handle_call(request, _from, state) do
    {:reply, {:ok, request}, state}
  end
end
