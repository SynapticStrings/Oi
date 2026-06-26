defmodule Oi.Runtime.SessionSmokeTest do
  use ExUnit.Case

  alias Oi.Runtime.Session

  import OiTest.GraphFactory

  describe "Session process isolation" do
    test "two sessions start and resolve independently" do
      {:ok, pid_a} = Session.start("tenant-a")
      {:ok, pid_b} = Session.start("tenant-b")

      assert pid_a != pid_b

      {:ok, resolved_a} = Session.resolve("tenant-a")
      {:ok, resolved_b} = Session.resolve("tenant-b")

      assert resolved_a != resolved_b
      assert Process.alive?(resolved_a)
      assert Process.alive?(resolved_b)

      Session.stop("tenant-a")
      Session.stop("tenant-b")
    end

    test "duplicate session returns error" do
      {:ok, pid} = Session.start("dup-test")

      assert {:error, {:already_started, ^pid}} = Session.start("dup-test")

      Session.stop("dup-test")
    end

    test "each session has isolated Task.Supervisor" do
      {:ok, _} = Session.start("tenant-x")
      {:ok, _} = Session.start("tenant-y")

      sup_x = Session.tasks_tuple("tenant-x")
      sup_y = Session.tasks_tuple("tenant-y")

      # Different via tuples
      refute sup_x == sup_y

      # Both are alive (via tuples need Registry.lookup)
      assert [{_pid_x, _}] = Registry.lookup(Oi.Runtime.Registry, Session.instances("tenant-x"))
      assert [{_pid_y, _}] = Registry.lookup(Oi.Runtime.Registry, Session.instances("tenant-y"))

      Session.stop("tenant-x")
      Session.stop("tenant-y")
    end
  end

  describe "Session with dispatch" do
    test "execute via per-session TaskSup" do
      {:ok, _} = Session.start("dispatch-tenant")
      graph = build_finin_and_fanout_dag()

      {:ok, compiled} = Oi.compile(graph)

      {:ok, result} =
        Oi.execute(compiled,
          data: %{step1: %{in: "Foo"}, step2: %{in: "Bar"}},
          executor: Oi.Executor.TaskSup,
          executor_opts: [sup: Session.tasks_tuple("dispatch-tenant")]
        )

      assert is_struct(result, Oi.Result)
      assert map_size(result.memory) > 0

      Session.stop("dispatch-tenant")
    end
  end
end
