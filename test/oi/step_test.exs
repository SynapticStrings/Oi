defmodule Oi.StepTest do
  use ExUnit.Case, async: true

  # ══════ 夹具模块 ═══════════════════════════════════════

  # ── 纯 step，单输入单输出 ──
  defmodule Upcase do
    use Oi.Step, name: :upcase

    manifest(inputs: [:text], outputs: [result: :string])

    routine text, _opts do
      text |> String.upcase() |> ok()
    end
  end

  # ── 多输入 list + 多输出 ──
  defmodule MultiList do
    use Oi.Step, name: :multi_list

    manifest(inputs: [:a, :b], outputs: [sum: :int, diff: :int])

    routine [a, b], _opts do
      ok([a + b, a - b])
    end
  end

  # ── 多输入 tuple ──
  defmodule MultiTuple do
    use Oi.Step, name: :multi_tuple

    manifest(inputs: [:a, :b], outputs: [product: :int])

    routine {a, b}, _opts do
      ok(a * b)
    end
  end

  # ── 无输入纯输入（manifest inputs 为空） ──
  defmodule Constant do
    use Oi.Step, name: :constant

    manifest(inputs: [], outputs: [answer: :int])

    routine _inputs, _opts do
      ok(42)
    end
  end

  # ── 标记 heavy ──
  defmodule HeavyStep do
    use Oi.Step, name: :heavy

    manifest(inputs: [:x], outputs: [y: :int], heavy?: true)

    routine x, _opts do
      ok(x * 2)
    end
  end

  # ── symbiont step（闭包注入，不依赖真实 OrchidSymbiont） ──
  defmodule Predicter do
    use Oi.Step, name: :predict, symbiont?: true

    manifest(inputs: [:features], outputs: [prediction: :float], models: [:encoder, :decoder])

    routine features, models, _opts do
      result = models.encoder.(features) |> models.decoder.()
      ok(result)
    end
  end

  # ══════ 纯 step：run/2 ═════════════════════════════════

  describe "pure step run/2" do
    test "单输入解包 payload，产出单个 Param" do
      input = %Orchid.Param{payload: "hello"}
      assert {:ok, %Orchid.Param{} = p} = Upcase.run(input, [])
      assert p.name == :result
      assert p.type == :string
      assert p.payload == "HELLO"
    end

    test "多输入 list 解包 + 多输出 wrap" do
      ins = [%Orchid.Param{payload: 10}, %Orchid.Param{payload: 3}]
      assert {:ok, [s, d]} = MultiList.run(ins, [])
      assert s.name == :sum
      assert s.payload == 13
      assert d.name == :diff
      assert d.payload == 7
    end

    test "多输入 tuple 解包" do
      ins = {%Orchid.Param{payload: 4}, %Orchid.Param{payload: 5}}
      assert {:ok, %Orchid.Param{payload: 20, name: :product}} = MultiTuple.run(ins, [])
    end

  end

  # ══════ __node_spec__ ═══════════════════════════════════

  describe "__node_spec__/0" do
    test "pure step" do
      spec = Upcase.__node_spec__()
      assert spec.id == :upcase
      assert spec.container == Upcase
      assert spec.inputs == [:text]
      assert spec.outputs == [:result]
      assert spec.extra.type == :pure
      assert spec.extra.models == []
      assert spec.extra.heavy? == false
    end

    test "symbiont step" do
      spec = Predicter.__node_spec__()
      assert spec.id == :predict
      assert spec.extra.type == :symbiont
      assert spec.extra.models == [:encoder, :decoder]
    end

    test "heavy? flag" do
      spec = HeavyStep.__node_spec__()
      assert spec.extra.heavy? == true
    end
  end

  # ══════ pure 专属回调 ══════════════════════════════════

  describe "pure step injected callbacks" do
    test "nested?/0" do
      assert Upcase.nested?() == false
    end

    test "validate_options/1" do
      assert Upcase.validate_options([]) == :ok
    end
  end

  # ══════ symbiont ════════════════════════════════════════

  describe "symbiont step" do
    test "run_with_model/3" do
      models = %{encoder: fn x -> x * 2 end, decoder: fn x -> x + 1 end}
      input = %Orchid.Param{payload: 10}
      assert {:ok, %Orchid.Param{payload: 21}} = Predicter.run_with_model(input, models, [])
    end

    test "required/0" do
      assert Predicter.required() == [:encoder, :decoder]
    end
  end

  # ══════ 运行时 helper（纯函数） ═════════════════════════

  describe "runtime helpers" do
    test "unwrap_list/1" do
      result = Oi.Step.unwrap_list([
        %Orchid.Param{payload: 1},
        %Orchid.Param{payload: 2}
      ])
      assert result == [1, 2]
    end

    test "unwrap_tuple/1" do
      result = Oi.Step.unwrap_tuple({
        %Orchid.Param{payload: :a},
        %Orchid.Param{payload: :b}
      })
      assert result == {:a, :b}
    end

    test "wrap_multi/2 数量匹配" do
      result = Oi.Step.wrap_multi([10, 3], [sum: :int, diff: :int])
      assert is_list(result)
      assert length(result) == 2
      assert Enum.at(result, 0).name == :sum
      assert Enum.at(result, 0).payload == 10
      assert Enum.at(result, 1).name == :diff
      assert Enum.at(result, 1).payload == 3
    end

    test "wrap_multi/2 数量不匹配报错" do
      assert_raise ArgumentError, ~r/期望 2 个输出值/, fn ->
        Oi.Step.wrap_multi([1], [a: :int, b: :int])
      end
    end

    test "wrap_multi/2 支持 tuple 输入" do
      result = Oi.Step.wrap_multi({10, 3}, [sum: :int, diff: :int])
      assert length(result) == 2
    end

    test "err/1" do
      assert Oi.Step.err(:boom) == {:error, :boom}
    end
  end

  # ══════ 编译期错误检测 ═════════════════════════════════

  describe "compile-time validation" do
    test "缺少 :name" do
      assert_raise RuntimeError, ~r/缺少 :name/, fn ->
        Code.eval_string("""
        defmodule OiStepTest.NoName do
          use Oi.Step, []
          manifest(inputs: [], outputs: [r: :int])
        end
        """)
      end
    end

    test "symbiont 未声明 models" do
      assert_raise RuntimeError, ~r/必须.*声明非空的 :models/, fn ->
        Code.eval_string("""
        defmodule OiStepTest.NoModels do
          use Oi.Step, name: :s, symbiont?: true
          manifest(inputs: [:x], outputs: [r: :int])
        end
        """)
      end
    end

    test "manifest 非字面 keyword list" do
      assert_raise ArgumentError, ~r/literal keyword list/, fn ->
        Code.eval_string("""
        defmodule OiStepTest.BadManifest do
          use Oi.Step, name: :s
          manifest(:not_a_keyword_list)
        end
        """)
      end
    end

    test "ok/1 在未声明 outputs 时报错" do
      assert_raise RuntimeError, ~r/manifest 中声明 :outputs/, fn ->
        Code.eval_string("""
        defmodule OiStepTest.BadOk do
          use Oi.Step, name: :s
          manifest(inputs: [:x])
          routine x, opts do
            ok(x)
          end
        end
        """)
      end
    end
  end
end
