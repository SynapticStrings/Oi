defmodule Oi.Step do
  @moduledoc """
  轻量级声明式语法层，在 `Orchid.Step` / `OrchidSymbiont.Step` 之上提供简易
  API，并产出 `__node_spec__/0` 供 topology 集成。

  ## Pure step

      defmodule MyApp.Steps.Upcase do
        use Oi.Step, name: :upcase

        manifest(
          inputs: [:text],
          outputs: [result: :string]
        )

        routine text, opts do
          report(opts, 100, "Reached!")
          text |> String.upcase() |> ok()
        end
      end

  ## Symbiont step

      defmodule MyApp.Steps.Predict do
        use Oi.Step, name: :predict, symbiont?: true

        manifest(
          inputs: [:features],
          outputs: [prediction: :tensor],
          models: [:encoder, :predictor],
          heavy?: true
        )

        routine features, models, opts do
          {:ok, {enc}} = OrchidSymbiont.call(models.encoder, {:infer, features})
          ok(enc)
        end
      end

  ## ok / err — Rust 风格结果构造器

      routine text, opts do
        case validate(text) do
          {:ok, v}    -> ok(v)
          {:error, e} -> err(e)
        end
      end

  - 单输出：`ok(value)` → `{:ok, %Orchid.Param{}}`
  - 多输出：`ok({a, b})` / `ok([a, b])` → `{:ok, [%Param{}, %Param{}]}`
  """

  #  __using__ : name + symbiont?
  defmacro __using__(opts) do
    name = Keyword.get(opts, :name)
    symbiont? = Keyword.get(opts, :symbiont?)
    type = if symbiont?, do: :symbiont, else: :pure

    behaviour =
      case type do
        :pure -> Orchid.Step
        :symbiont -> OrchidSymbiont.Step
      end

    # 属性在宏展开期直接设置，确保后续宏（manifest/routine/ok）
    # 在展开时能读到。
    m = __CALLER__.module

    Module.put_attribute(m, :oi_name, name)
    Module.put_attribute(m, :oi_type, type)
    Module.put_attribute(m, :oi_symbiont, symbiont?)

    # manifest 默认值（manifest/1 会覆盖）
    Module.put_attribute(m, :oi_inputs, [])
    Module.put_attribute(m, :oi_outputs, [])
    Module.put_attribute(m, :oi_models, [])
    Module.put_attribute(m, :oi_heavy?, false)

    quote do
      import Orchid.Step, only: [report: 2, report: 3]

      import Oi.Step,
        only: [manifest: 1, routine: 3, routine: 4, ok: 1, err: 1]

      @behaviour unquote(behaviour)
      @before_compile Oi.Step
    end
  end

  # ─────────────────────────────────────────────────────────
  #  manifest/1
  # ─────────────────────────────────────────────────────────

  @doc """
  声明 step 元数据，必须在 `routine` 之前调用。

  - `:inputs`  — 输入端口名列表 (atoms)
  - `:outputs` — keyword list，`port_name => param_type`
  - `:models`  — symbiont step 的 model 名列表（symbiont? 时必填）
  - `:heavy?`  — boolean，默认 false
  """
  defmacro manifest(opts) do
    unless is_list(opts) and Keyword.keyword?(opts) do
      raise ArgumentError,
            "manifest/1 expects a literal keyword list, got: #{Macro.to_string(opts)}"
    end

    m = __CALLER__.module
    Module.put_attribute(m, :oi_inputs, Keyword.get(opts, :inputs, []))
    Module.put_attribute(m, :oi_outputs, Keyword.get(opts, :outputs, []))
    Module.put_attribute(m, :oi_models, Keyword.get(opts, :models, []))
    Module.put_attribute(m, :oi_heavy?, Keyword.get(opts, :heavy?, false))

    :ok
  end

  # ─────────────────────────────────────────────────────────
  #  routine — pure (arity 3) / symbiont (arity 4)
  # ─────────────────────────────────────────────────────────

  @doc """
  定义执行逻辑，展开为 `run/2` (pure) 或 `run_with_model/3` (symbiont)。

  自动解包输入 Param：
  - 单输入 `routine text, opts`     → payload 直接绑定
  - 多输入 `routine [a, b], opts`   → list 解包
  - 多输入 `routine {a, b}, opts`   → tuple 解包

  symbiont 的 `models` 绑定到 handler map（`models.encoder` 等）。
  """
  defmacro routine(input, opts_var, do: body) do
    ensure_type!(__CALLER__.module, :pure, 3)
    build_routine(:run, [], input, opts_var, body)
  end

  defmacro routine(input, models_var, opts_var, do: body) do
    ensure_type!(__CALLER__.module, :symbiont, 4)
    build_routine(:run_with_model, [models_var], input, opts_var, body)
  end

  # ─────────────────────────────────────────────────────────
  #  ok / err
  # ─────────────────────────────────────────────────────────

  @doc "将值包装为 `{:ok, Param | [Param]}`。"
  defmacro ok(value) do
    case Module.get_attribute(__CALLER__.module, :oi_outputs) || [] do
      [] ->
        raise "ok/1 调用前必须先在 manifest 中声明 :outputs"

      [{name, type}] ->
        quote do
          {:ok, Orchid.Param.new(unquote(name), unquote(type), unquote(value))}
        end

      multi ->
        pairs = Macro.escape(multi)

        quote do
          {:ok, Oi.Step.wrap_multi(unquote(value), unquote(pairs))}
        end
    end
  end

  @doc "将 reason 包装为 `{:error, reason}`。"
  # 不依赖编译期信息，做成普通函数即可（与 ok 对称地导出）。
  def err(reason), do: {:error, reason}

  # ─────────────────────────────────────────────────────────
  #  __before_compile__ : 剩余回调 + node spec
  # ─────────────────────────────────────────────────────────

  defmacro __before_compile__(env) do
    m = env.module
    name = Module.get_attribute(m, :oi_name)
    type = Module.get_attribute(m, :oi_type) || :pure
    inputs = Module.get_attribute(m, :oi_inputs) || []
    outputs = Module.get_attribute(m, :oi_outputs) || []
    models = Module.get_attribute(m, :oi_models) || []
    heavy? = Module.get_attribute(m, :oi_heavy?) || false

    unless name do
      raise "use Oi.Step 缺少 :name 选项"
    end

    if type == :symbiont and models == [] do
      raise "symbiont? step 必须在 manifest 中声明非空的 :models"
    end

    node_spec =
      Macro.escape(%{
        id: name,
        container: m,
        inputs: inputs,
        outputs: Keyword.keys(outputs),
        options: [],
        extra: %{heavy?: heavy?, type: type, models: models}
      })

    type_specific =
      case type do
        :pure ->
          quote do
            @impl true
            def nested?, do: false

            @impl true
            def validate_options(_opts), do: :ok
          end

        :symbiont ->
          quote do
            @impl true
            def required, do: unquote(models)
          end
      end

    quote do
      unquote(type_specific)

      @doc false
      def __node_spec__, do: unquote(node_spec)
    end
  end

  # ─────────────────────────────────────────────────────────
  #  Private: codegen
  # ─────────────────────────────────────────────────────────

  # fun       : 目标函数名 (:run / :run_with_model)
  # mid_args   : 介于输入 Param 与 opts 之间的参数 (symbiont 的 models_var)
  defp build_routine(fun, mid_args, input, opts_var, body) do
    case classify_input(input) do
      {:single, var} ->
        param = quote(do: %Orchid.Param{payload: unquote(var)})
        args = [param | mid_args] ++ [opts_var]

        quote do
          @impl true
          def unquote(fun)(unquote_splicing(args)), do: unquote(body)
        end

      {:list, vars} ->
        in_var = Macro.unique_var(:oi_inputs, __MODULE__)
        args = [in_var | mid_args] ++ [opts_var]

        quote do
          @impl true
          def unquote(fun)(unquote_splicing(args)) do
            unquote(vars) = Oi.Step.unwrap_list(unquote(in_var))
            unquote(body)
          end
        end

      {:tuple, vars} ->
        in_var = Macro.unique_var(:oi_inputs, __MODULE__)
        tuple_pattern = {:{}, [], vars}
        args = [in_var | mid_args] ++ [opts_var]

        quote do
          @impl true
          def unquote(fun)(unquote_splicing(args)) do
            unquote(tuple_pattern) = Oi.Step.unwrap_tuple(unquote(in_var))
            unquote(body)
          end
        end
    end
  end

  defp ensure_type!(module, expected, arity) do
    case Module.get_attribute(module, :oi_type) do
      ^expected ->
        :ok

      nil ->
        raise "routine 必须在 `use Oi.Step` 之后使用"

      other ->
        raise ArgumentError,
              "routine/#{arity} 用于 #{expected} step，但当前类型为 #{other}" <>
                "（由 use 的 symbiont? 决定）"
    end
  end

  # AST 形态判别。
  # 注意：Elixir AST 中 2-tuple 是“裸” `{a, b}`，变量是 3-tuple `{:x, m, ctx}`，
  # N-tuple 是 `{:{}, m, args}`，因此下面的顺序与 tuple_size 判断是安全的。
  defp classify_input(ast) do
    cond do
      is_list(ast) -> {:list, ast}
      match?({:{}, _, [_ | _]}, ast) -> {:tuple, elem(ast, 2)}
      is_tuple(ast) and tuple_size(ast) == 2 -> {:tuple, Tuple.to_list(ast)}
      true -> {:single, ast}
    end
  end

  # ─────────────────────────────────────────────────────────
  #  Runtime helpers
  # ─────────────────────────────────────────────────────────

  @doc false
  def unwrap_list(params) when is_list(params) do
    Enum.map(params, fn %Orchid.Param{payload: p} -> p end)
  end

  @doc false
  def unwrap_tuple(params) when is_tuple(params) do
    params
    |> Tuple.to_list()
    |> Enum.map(fn %Orchid.Param{payload: p} -> p end)
    |> List.to_tuple()
  end

  @doc false
  def wrap_multi(values, spec) when is_tuple(values),
    do: wrap_multi(Tuple.to_list(values), spec)

  def wrap_multi(values, spec) when is_list(values) do
    unless length(values) == length(spec) do
      raise ArgumentError,
            "ok/1 期望 #{length(spec)} 个输出值 " <>
              "#{inspect(Keyword.keys(spec))}，实际得到 #{length(values)} 个"
    end

    values
    |> Enum.zip(spec)
    |> Enum.map(fn {v, {name, type}} -> Orchid.Param.new(name, type, v) end)
  end
end
