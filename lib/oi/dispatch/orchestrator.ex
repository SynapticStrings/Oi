defmodule Oi.Dispatch.Orchestrator do
  @moduledoc """
  Orchestrates barrier-synchronized execution of plan stages.

  Fans out tasks per stage via the configured executor, collects results,
  enforces barrier before next stage. Results are merged into the drafting.

  When `conf.checkpoint` is set, it is invoked before each stage with a
  `Config.checkpoint_event()` and the current drafting. Returning `:halt`
  stops the dispatch; the memory accumulated so far is returned as a
  `{:halted, drafting, stage_index}` partial result.

  When `conf.cancel_token` is set, it is checked before each stage (before
  the checkpoint). A cancelled token stops the dispatch with the current
  memory as a `{:cancelled, drafting, stage_index}` partial result —
  cooperative, not preemptive: in-flight steps of the current stage run
  to completion.
  """

  alias Oi.{Compile.Planning, Dispatch.Drafting}
  alias Oi.Dispatch.{Config, Worker}

  @spec dispatch(Planning.Plan.t(), Drafting.t(), Config.t()) ::
          {:ok, Drafting.t()}
          | {:halted, Drafting.t(), non_neg_integer()}
          | {:cancelled, Drafting.t(), non_neg_integer()}
          | {:error, term()}
  def dispatch(%Planning.Plan{} = plan, %Drafting{} = drafting, %Config{} = conf) do
    stage_count = length(plan.stages)

    {final, _} =
      Enum.reduce(plan.stages, {{:ok, drafting}, 0}, fn
        stage, {{:ok, current_drafting}, idx} ->
          stage_meta = %{stage_index: idx, stage_count: stage_count}

          case stage_gate(stage, current_drafting, conf, stage_meta) do
            :cancel ->
              {{:cancelled, current_drafting, idx}, idx}

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

  # 取消优先于 checkpoint：token 已取消时该 stage 的 checkpoint 不再调用。
  defp stage_gate(stage, drafting, %Config{cancel_token: token} = conf, stage_meta) do
    if not is_nil(token) and Oi.CancelToken.cancelled?(token) do
      :cancel
    else
      checkpoint_decision(stage, drafting, conf, stage_meta)
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
