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

    stage.tasks
    |> conf.executor.run(worker_fn, conf.executor_opts)
    |> Enum.reduce_while({:ok, drafting}, fn
      {:ok, outputs}, {:ok, acc} ->
        {:cont, {:ok, merge_results(acc, outputs)}}

      {:error, _} = err, _acc ->
        {:halt, err}
    end)
  end

  defp merge_results(%Drafting{} = drafting, outputs) do
    entries =
      outputs
      |> Enum.map(fn
        %Orchid.Param{} = p -> {p.name, p}
        {port_name, p} -> {port_name, p}
      end)
      # TODO: reconsider nil filtering after restructure
      # |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Drafting.put(drafting, entries)
  end
end
