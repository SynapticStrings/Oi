defmodule Oi.CancelSmokeTest do
  use ExUnit.Case

  import OiTest.GraphFactory

  alias Oi.Topology.Cluster

  # 与 checkpoint 测试同一张图：step4 单独染成 :blue,编译出两个 stage:
  #   stage 0 → :default_cluster (step1, step2, step3)
  #   stage 1 → :blue (step4)
  defp compile_two_stages do
    graph = build_finin_and_fanout_dag()
    Oi.compile(graph, %Cluster{node_colors: %{step4: :blue}})
  end

  defp input_data, do: %{step1: %{in: "Foo"}, step2: %{in: "Bar"}}

  describe "CancelToken" do
    test "new token is not cancelled; cancel is idempotent" do
      token = Oi.CancelToken.new()
      refute Oi.CancelToken.cancelled?(token)

      assert :ok = Oi.CancelToken.cancel(token)
      assert Oi.CancelToken.cancelled?(token)
      assert :ok = Oi.CancelToken.cancel(token)
      assert Oi.CancelToken.cancelled?(token)
    end

    test "token survives cross-process use" do
      token = Oi.CancelToken.new()
      assert Task.async(fn -> Oi.CancelToken.cancel(token) end) |> Task.await() == :ok
      assert Oi.CancelToken.cancelled?(token)
    end
  end

  describe "execute cancellation" do
    test "cancelled token before start halts at stage 0 with only inputs" do
      {:ok, compiled} = compile_two_stages()
      token = Oi.CancelToken.new()
      Oi.CancelToken.cancel(token)

      {:ok, result} = Oi.execute(compiled, data: input_data(), cancel_token: token)

      assert result.status == :cancelled
      assert result.halted_at == 0
      # 只有外部输入,没有任何 step 产出
      assert Map.has_key?(result.memory, "step1|in")
      refute Map.has_key?(result.memory, "step1|out")
    end

    test "cancel during stage 0 keeps stage 0 outputs and skips later stages" do
      {:ok, compiled} = compile_two_stages()
      token = Oi.CancelToken.new()
      test_pid = self()

      # checkpoint 在 stage 0 放行并触发取消,模拟"运行中按下取消"
      {:ok, result} =
        Oi.execute(compiled,
          data: input_data(),
          cancel_token: token,
          checkpoint: fn _event, _drafting ->
            send(test_pid, :checkpoint_called)
            Oi.CancelToken.cancel(token)
            :cont
          end
        )

      assert result.status == :cancelled
      assert result.halted_at == 1
      # stage 0 已经跑完,产出都在
      assert Map.has_key?(result.memory, "step3|out")
      # :blue cluster 的 step4 没有执行
      refute Map.has_key?(result.memory, "step4|out1")

      # 取消优先于 checkpoint:stage 1 的 checkpoint 没有被调用
      assert_received :checkpoint_called
      refute_received :checkpoint_called
    end

    test "non-cancelled token completes as usual" do
      {:ok, compiled} = compile_two_stages()

      {:ok, result} =
        Oi.execute(compiled, data: input_data(), cancel_token: Oi.CancelToken.new())

      assert result.status == :complete
      assert result.halted_at == nil
      assert Map.has_key?(result.memory, "step4|out1")
    end

    test "works with the TaskSup executor too" do
      {:ok, sup} = Task.Supervisor.start_link()
      {:ok, compiled} = compile_two_stages()
      token = Oi.CancelToken.new()
      Oi.CancelToken.cancel(token)

      {:ok, result} =
        Oi.execute(compiled,
          data: input_data(),
          executor: Oi.Executor.TaskSup,
          executor_opts: [sup: sup],
          cancel_token: token
        )

      assert result.status == :cancelled
      assert result.halted_at == 0

      Supervisor.stop(sup)
    end
  end
end
