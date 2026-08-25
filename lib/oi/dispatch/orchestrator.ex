defmodule Oi.Dispatch.Orchestrator do
  @moduledoc """
  Orchestrates barrier-synchronized execution of plan stages.

  Fans out tasks per stage via the configured executor, collects results,
  enforces barrier before next stage. Results are merged into the drafting.

  When `conf.checkpoint` is set, it is invoked before each stage with a
  `Config.checkpoint_event()` and the current drafting. Returning `:halt`
  stops the dispatch; the memory accumulated so far is returned as a
  `{:halted, drafting, stage_index}` partial result.
  """

  alias Oi.{Compile.Planning, Dispatch.Drafting}
  alias Oi.Dispatch.{Config, Worker}

  @spec dispatch(Planning.Plan.t(), Drafting.t(), Config.t()) ::
          {:ok, Drafting.t()} | {:halted, Drafting.t(), non_neg_integer()} | {:error, term()}
  def dispatch(%Planning.Plan{} = plan, %Drafting{} = drafting, %Config{} = conf) do
    stage_count = length(plan.stages)

    {final, _} =
      Enum.reduce(plan.stages, {{:ok, drafting}, 0}, fn
        stage, {{:ok, current_drafting}, idx} ->
          stage_meta = %{stage_index: idx, stage_count: stage_count}

          case checkpoint_decision(stage, current_drafting, conf, stage_meta) do
            :halt ->
              {{:halted, current_drafting, idx}, idx}

            :cont ->
              dispatch_stage(stage, current_drafting, conf, stage_meta, idx)
          end

        _stage, {err, idx} ->
          {err, idx}
      end)

    final
  end

  defp dispatch_stage(stage, drafting, conf, stage_meta, idx) do
    :telemetry.execute(
      [:oi, :stage, :start],
      %{system_time: System.system_time()},
      stage_meta
    )

    case run_stage(stage, drafting, conf) do
      {:ok, updated} ->
        :telemetry.execute([:oi, :stage, :stop], %{}, stage_meta)
        {{:ok, updated}, idx + 1}

      {:error, _} = err ->
        :telemetry.execute([:oi, :stage, :stop], %{}, Map.put(stage_meta, :error, err))
        {err, idx}
    end
  end

  defp checkpoint_decision(_stage, _drafting, %Config{checkpoint: nil}, _stage_meta), do: :cont

  defp checkpoint_decision(stage, drafting, %Config{checkpoint: checkpoint}, stage_meta) do
    checkpoint.(checkpoint_event(stage, stage_meta), drafting)
  end

  defp checkpoint_event(%Planning.Stage{} = stage, stage_meta) do
    Map.merge(stage_meta, %{
      clusters: Enum.map(stage.tasks, & &1.cluster),
      node_ids: Enum.flat_map(stage.tasks, & &1.node_ids)
    })
  end

  defp run_stage(%Planning.Stage{} = stage, drafting, %Config{} = conf) do
    worker_fn = fn bundle ->
      Worker.run(bundle, drafting, conf)
    end

    case conf.executor.run(stage.tasks, worker_fn, conf.executor_opts) do
      {:error, _} = err ->
        err

      {:ok, results} ->
        Enum.reduce_while(results, {:ok, drafting}, fn
          {:ok, outputs}, {:ok, acc} ->
            {:cont, {:ok, merge_results(acc, outputs)}}

          {:error, _} = err, _acc ->
            {:halt, err}
        end)
    end
  end

  defp merge_results(%Drafting{} = drafting, outputs) do
    outputs
    |> Map.new()
    |> then(&Drafting.put(drafting, &1))
  end
end
