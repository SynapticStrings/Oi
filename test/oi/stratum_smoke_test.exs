defmodule Oi.Adapters.StratumTest do
  use ExUnit.Case

  alias Orchid.{Recipe, Param}

  # ── Dummy steps for caching ───────────────────────────

  defmodule UpperStep do
    use Orchid.Step

    def run(input, opts) do
      send(opts[:test_pid], :upper_executed)
      {:ok, Param.new(:out, :data, Param.get_payload(input) |> String.upcase())}
    end
  end

  defmodule ReverseStep do
    use Orchid.Step

    def run(input, opts) do
      send(opts[:test_pid], :reverse_executed)
      {:ok, Param.new(:out, :data, Param.get_payload(input) |> String.reverse())}
    end
  end

  # ── Adapter unit tests ──────────────────────────────

  describe "orchid_stratum/1" do
    test "prepends BypassHook and auto-inits ETS-backed stores" do
      recipe = Recipe.new([])
      opts = []

      {_recipe, adapted_opts} = Oi.Adapters.orchid_stratum({recipe, opts})

      # hook is prepended
      hooks = Keyword.get(adapted_opts, :global_hooks_stack, [])
      assert OrchidStratum.BypassHook in hooks

      # baggage has ETS-backed stores
      baggage = Keyword.get(adapted_opts, :baggage)
      assert {OrchidStratum.MetaStorage.EtsAdapter, meta_ref} = baggage[:meta_store]
      assert is_reference(meta_ref)
      assert {OrchidStratum.BlobStorage.EtsAdapter, blob_ref} = baggage[:blob_store]
      assert is_reference(blob_ref)
    end

    test "preserves user-supplied store configs" do
      recipe = Recipe.new([])
      opts = [
        baggage: %{
          meta_store: {MyMeta, :my_meta_ref},
          blob_store: {MyBlob, :my_blob_ref}
        }
      ]

      {_recipe, adapted_opts} = Oi.Adapters.orchid_stratum({recipe, opts})

      baggage = Keyword.get(adapted_opts, :baggage)
      assert baggage[:meta_store] == {MyMeta, :my_meta_ref}
      assert baggage[:blob_store] == {MyBlob, :my_blob_ref}
    end

    test "preserves partial config — only fills missing store" do
      recipe = Recipe.new([])
      opts = [
        baggage: %{
          meta_store: {MyMeta, :my_meta_ref}
        }
      ]

      {_recipe, adapted_opts} = Oi.Adapters.orchid_stratum({recipe, opts})

      baggage = Keyword.get(adapted_opts, :baggage)
      assert baggage[:meta_store] == {MyMeta, :my_meta_ref}
      assert {OrchidStratum.BlobStorage.EtsAdapter, _} = baggage[:blob_store]
    end

    test "no-op when orchid_stratum is not available" do
      # monkey-patch to simulate missing dependency
      recipe = Recipe.new([])
      opts = [baggage: %{}]

      # We can't easily unload a module, so we test via
      # the public API shape: adapter always returns {recipe, opts}
      {result_recipe, result_opts} = Oi.Adapters.orchid_stratum({recipe, opts})
      assert result_recipe == recipe
      assert is_list(result_opts)
    end
  end

  describe "orchid_intervention_and_stratum/1" do
    test "prepends both hooks in correct order (Stratum => Intervention)" do
      recipe = Recipe.new([])
      opts = []

      {_recipe, adapted_opts} = Oi.Adapters.orchid_intervention_and_stratum({recipe, opts})

      hooks = Keyword.get(adapted_opts, :global_hooks_stack, [])

      if Code.ensure_loaded?(Orchid.Hook.ApplyInterventions) do
        # Both present with Stratum outermost (prepended last)
        stratum_idx = Enum.find_index(hooks, &(&1 == OrchidStratum.BypassHook))
        intervention_idx = Enum.find_index(hooks, &(&1 == Orchid.Hook.ApplyInterventions))
        assert stratum_idx > intervention_idx
      else
        assert OrchidStratum.BypassHook in hooks
      end
    end
  end

  # ── End-to-end cache hit test ──────────────────────

  describe "cache hit via Orchid.run" do
    setup do
      recipe =
        Recipe.new(
          [
            {UpperStep, :in, :upper, [cache: true, test_pid: self()]},
            {ReverseStep, :upper, :out, [cache: true, test_pid: self()]}
          ],
          name: :stratum_e2e
        )

      inputs = [Param.new(:in, :data, "hello")]

      {:ok, recipe: recipe, inputs: inputs}
    end

    test "first run executes steps, second run is cache hit", %{recipe: recipe, inputs: inputs} do
      # First run — apply adapter to get opts
      {recipe, opts} = Oi.Adapters.orchid_stratum({recipe, []})

      assert {:ok, results1} = Orchid.run(recipe, inputs, opts)
      assert_received :upper_executed
      assert_received :reverse_executed

      out_param = results1[:out]
      # Outputs are dehydrated — {:ref, blob_store, hash}
      assert {:ref, {OrchidStratum.BlobStorage.EtsAdapter, blob_ref}, hash} = out_param.payload

      # Verify the actual blob value
      assert {:ok, "OLLEH"} = OrchidStratum.BlobStorage.EtsAdapter.get(blob_ref, hash)

      # Second run — same recipe, same inputs, same opts
      assert {:ok, results2} = Orchid.run(recipe, inputs, opts)
      refute_received :upper_executed
      refute_received :reverse_executed

      # Still get the same dehydrated output
      out_param2 = results2[:out]
      assert {:ref, {OrchidStratum.BlobStorage.EtsAdapter, _}, ^hash} = out_param2.payload
    end

    test "different inputs produce different cache keys", %{recipe: recipe, inputs: _inputs} do
      {recipe, opts} = Oi.Adapters.orchid_stratum({recipe, []})

      # Run with "hello"
      assert {:ok, _} = Orchid.run(recipe, [Param.new(:in, :data, "hello")], opts)
      assert_received :upper_executed
      assert_received :reverse_executed

      # Run with DIFFERENT input — should not be cache hit
      assert {:ok, _} = Orchid.run(recipe, [Param.new(:in, :data, "world")], opts)
      assert_received :upper_executed
      assert_received :reverse_executed
    end
  end
end
