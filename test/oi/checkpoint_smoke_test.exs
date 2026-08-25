defmodule Oi.CheckpointSmokeTest do
  use ExUnit.Case

  import OiTest.GraphFactory

  alias Oi.Topology.Cluster

  # step4 单独染成 :blue,编译出两个 stage:
  #   stage 0 → :default_cluster (step1, step2, step3)
  #   stage 1 → :blue (step4)
  defp compile_two_stages do
    graph = build_finin_and_fanout_dag()
    Oi.compile(graph, %Cluster{node_colors: %{step4: :blue}})
  end

  defp input_data, do: %{step1: %{in: "Foo"}, step2: %{in: "Bar"}}

  describe "checkpoint" do
    test "halt at stage 0 returns partial result with only inputs" do
      {:ok, compiled} = compile_two_stages()

      {:ok, result} =
        Oi.execute(compiled,
          data: input_data(),
          checkpoint: fn _event, _drafting -> :halt end
        )

      assert result.status == :halted
      assert result.halted_at == 0
      # 只有外部输入,没有任何 step 产出
      assert Map.has_key?(result.memory, "step1|in")
      refute Map.has_key?(result.memory, "step1|out")
    end

    test "halt before a given cluster keeps earlier stages' outputs" do
      {:ok, compiled} = compile_two_stages()
      test_pid = self()

      {:ok, result} =
        Oi.execute(compiled,
          data: input_data(),
          checkpoint: fn event, drafting ->
            send(test_pid, {:checkpoint, event, Map.keys(drafting.memory)})
            if :blue in event.clusters, do: :halt, else: :cont
          end
        )

      assert result.status == :halted
      assert result.halted_at == 1
      # stage 0 已经跑完,产出都在
      assert Map.has_key?(result.memory, "step3|out")
      # :blue cluster 的 step4 没有执行
      refute Map.has_key?(result.memory, "step4|out1")

      # checkpoint 事件内容:stage 序号、cluster 名、节点列表、当时的 memory
      assert_received {:checkpoint,
                       %{stage_index: 0, stage_count: 2, clusters: [:default_cluster]} = event0,
                       _keys0}

      assert Enum.sort(event0.node_ids) == [:step1, :step2, :step3]

      assert_received {:checkpoint,
                       %{stage_index: 1, stage_count: 2, clusters: [:blue], node_ids: [:step4]},
                       keys1}

      assert "step3|out" in keys1
    end

    test "cont everywhere completes as usual" do
      {:ok, compiled} = compile_two_stages()

      {:ok, result} =
        Oi.execute(compiled,
          data: input_data(),
          checkpoint: fn _event, _drafting -> :cont end
        )

      assert result.status == :complete
      assert result.halted_at == nil
      assert Map.has_key?(result.memory, "step4|out1")
    end
  end
end
