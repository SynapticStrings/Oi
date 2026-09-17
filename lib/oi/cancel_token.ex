defmodule Oi.CancelToken do
  @moduledoc """
  Cooperative cancellation token for `Oi.execute/2`.

  An atomics-backed flag: no process lifecycle, shareable across processes
  and nodes' local callers. Create one per dispatch, keep it, and call
  `cancel/1` from any process to request cancellation.

  The Orchestrator checks the token **before each stage** (the barrier
  points — same granularity as `:checkpoint`). A cancelled dispatch stops
  before the next stage and returns normally:

      {:ok, %Oi.Result{status: :cancelled, halted_at: stage_index}}

  In-flight steps of the current stage run to completion — this is
  cooperative cancellation, not preemption. Steps that want finer
  granularity can receive the token (e.g. via `:data` or step opts) and
  poll `cancelled?/1` between internal work units.

  ## Example

      token = Oi.CancelToken.new()

      task = Task.async(fn -> Oi.execute(compiled, data: data, cancel_token: token) end)

      # ...later, from any process:
      Oi.CancelToken.cancel(token)

      {:ok, result} = Task.await(task)
      result.status in [:complete, :cancelled]
  """

  @type t :: %__MODULE__{ref: :atomics.atomics_ref()}

  defstruct [:ref]

  @doc "Create a fresh, non-cancelled token."
  @spec new() :: t()
  def new, do: %__MODULE__{ref: :atomics.new(1, [])}

  @doc "Request cancellation. Idempotent."
  @spec cancel(t()) :: :ok
  def cancel(%__MODULE__{ref: ref}) do
    :atomics.put(ref, 1, 1)
    :ok
  end

  @doc "Whether cancellation has been requested."
  @spec cancelled?(t()) :: boolean()
  def cancelled?(%__MODULE__{ref: ref}), do: :atomics.get(ref, 1) == 1
end
