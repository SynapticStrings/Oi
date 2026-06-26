defmodule Oi.Dispatch.Orchestrator do
  @moduledoc """
  Orchestrates barrier-synchronized execution of plan stages.

  Fans out tasks per stage via the configured executor, collects results,
  enforces barrier before next stage. Results are merged into the drafting.
  """

  alias Oi.{Compile.Planning, Dispatch.Drafting}
  alias Oi.Dispatch.Config

  @spec dispatch(Planning.Plan.t(), Drafting.t(), Config.t()) ::
          {:ok, Drafting.t()} | {:error, term()}
  def dispatch(%Planning.Plan{} = plan, %Drafting{} = drafting, %Config{} = conf) do
    Enum.reduce_while(plan.stages, {:ok, drafting}, fn stage, {:ok, current_drafting} ->
      case run_stage(stage, current_drafting, conf) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp run_stage(%Planning.Stage{} = stage, drafting, %Config{} = conf) do
    worker_fn = fn bundle ->
      Oi.Dispatch.Worker.run(bundle, drafting, conf)
    end

    case conf.executor.run(stage.tasks, worker_fn, conf.executor_opts) do
      {:error, _} = err ->
        err

      results when is_list(results) ->
        Enum.reduce_while(results, {:ok, drafting}, fn
          {:ok, outputs}, {:ok, acc} ->
            {:cont, {:ok, merge_results(acc, outputs)}}

          {:error, _} = err, _acc ->
            {:halt, err}
        end)

      other ->
        {:error, {:bad_executor_return, conf.executor, other}}
    end
  end

  defp merge_results(%Drafting{} = drafting, outputs) do
    outputs
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> then(&Drafting.put(drafting, &1))
  end
end
