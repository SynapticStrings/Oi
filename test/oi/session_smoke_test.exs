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

    test "with_session/3 wraps the boilerplate" do
      graph = build_finin_and_fanout_dag()

      result =
        Session.with_session("ws-test", fn session ->
          {:ok, compiled} = Oi.compile(graph)

          Oi.execute(
            compiled,
            Keyword.merge(session, data: %{step1: %{in: "A"}, step2: %{in: "B"}})
          )
        end)

      assert {:ok, %Oi.Result{}} = result
      assert map_size(elem(result, 1).memory) > 0

      Session.stop("ws-test")
    end

    test "with_session/3 is idempotent" do
      graph = build_finin_and_fanout_dag()

      run = fn ->
        Session.with_session("ws-idem", fn session ->
          {:ok, compiled} = Oi.compile(graph)

          Oi.execute(
            compiled,
            Keyword.merge(session, data: %{step1: %{in: "X"}, step2: %{in: "Y"}})
          )
        end)
      end

      assert {:ok, %Oi.Result{}} = run.()
      assert {:ok, %Oi.Result{}} = run.()

      Session.stop("ws-idem")
    end
  end

  if Code.ensure_loaded?(OrchidStratum.MetaStorage.EtsAdapter) do
    describe "Session storage" do
      test "session auto-creates storage Agent" do
        {:ok, _} = Session.start("storage-auto")

        stores = Session.storage("storage-auto")
        assert is_map(stores)
        assert {OrchidStratum.MetaStorage.EtsAdapter, meta_ref} = stores[:meta_store]
        assert is_reference(meta_ref)
        assert {OrchidStratum.BlobStorage.EtsAdapter, blob_ref} = stores[:blob_store]
        assert is_reference(blob_ref)

        Session.stop("storage-auto")
      end

      test "same session returns same ETS refs across lookups" do
        {:ok, _} = Session.start("storage-same")

        %{meta_store: {_, ref1}, blob_store: {_, bref1}} = Session.storage("storage-same")
        %{meta_store: {_, ref2}, blob_store: {_, bref2}} = Session.storage("storage-same")

        assert ref1 == ref2
        assert bref1 == bref2

        Session.stop("storage-same")
      end

      test "different sessions have isolated ETS tables" do
        {:ok, _} = Session.start("storage-a")
        {:ok, _} = Session.start("storage-b")

        %{meta_store: {_, ref_a}} = Session.storage("storage-a")
        %{meta_store: {_, ref_b}} = Session.storage("storage-b")

        refute ref_a == ref_b

        Session.stop("storage-a")
        Session.stop("storage-b")
      end

      test "storage dies with session" do
        {:ok, _} = Session.start("storage-die")

        stores = Session.storage("storage-die")
        %{meta_store: {_, ref}} = stores

        # ETS table is alive while session is
        assert :ets.info(ref) != :undefined

        Session.stop("storage-die")

        # After stop, ETS table is gone
        # (give it a moment — ETS cleanup is synchronous on owner death)
        assert :ets.info(ref) == :undefined
      end

      test "storage survives across execute calls within session" do
        {:ok, _} = Session.start("storage-persist")
        graph = build_finin_and_fanout_dag()

        stores_before = Session.storage("storage-persist")
        %{meta_store: {_, meta_before}} = stores_before

        {:ok, compiled} = Oi.compile(graph)

        # Execute with stratum caching
        {:ok, _} =
          Oi.execute(compiled,
            data: %{step1: %{in: "hello"}, step2: %{in: "world"}},
            executor: Oi.Executor.TaskSup,
            executor_opts: [sup: Session.tasks_tuple("storage-persist")],
            orchid_adapters: [&Oi.Adapters.orchid_stratum/2],
            orchid_baggage: stores_before
          )

        # Execute again — same storage refs, cache should be warm
        {:ok, _} =
          Oi.execute(compiled,
            data: %{step1: %{in: "hello"}, step2: %{in: "world"}},
            executor: Oi.Executor.TaskSup,
            executor_opts: [sup: Session.tasks_tuple("storage-persist")],
            orchid_adapters: [&Oi.Adapters.orchid_stratum/2],
            orchid_baggage: stores_before
          )

        # Storage refs unchanged after multiple execute calls
        stores_after = Session.storage("storage-persist")
        %{meta_store: {_, meta_after}} = stores_after
        assert meta_before == meta_after

        Session.stop("storage-persist")
      end

      test "with_session/3 includes storage in baggage" do
        graph = build_finin_and_fanout_dag()

        Session.with_session("storage-ws", fn session ->
          {:ok, compiled} = Oi.compile(graph)

          baggage = Keyword.get(session, :orchid_baggage)
          assert is_map_key(baggage, :meta_store)
          assert is_map_key(baggage, :blob_store)
          assert baggage[:scope_id] == "storage-ws"

          {:ok, _} =
            Oi.execute(
              compiled,
              Keyword.merge(session,
                data: %{step1: %{in: "A"}, step2: %{in: "B"}},
                orchid_adapters: [&Oi.Adapters.orchid_stratum/2]
              )
            )

          # Second call — same session, cached
          {:ok, _} =
            Oi.execute(
              compiled,
              Keyword.merge(session,
                data: %{step1: %{in: "A"}, step2: %{in: "B"}},
                orchid_adapters: [&Oi.Adapters.orchid_stratum/2]
              )
            )
        end)

        Session.stop("storage-ws")
      end
    end
  end
end
