defmodule Oi.Step do
  @moduledoc """
  Lightweight declarative syntax layer on top of `Orchid.Step` /
  `OrchidSymbiont.Step`. Provides a simple API and exposes
  `__node_spec__/0` for topology integration.

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

  ## ok / err — Rust-style result constructors

      routine text, opts do
        case validate(text) do
          {:ok, v}    -> ok(v)
          {:error, e} -> err(e)
        end
      end

  - Single output: `ok(value)` → `{:ok, %Orchid.Param{}}`
  - Multi-output: `ok({a, b})` / `ok([a, b])` → `{:ok, [%Param{}, %Param{}]}`
  """

  #  __using__ : name + symbiont?
  defmacro __using__(opts) do
    name = Keyword.get(opts, :name)
    symbiont? = Keyword.get(opts, :symbiont?)
    type = if symbiont?, do: :symbiont, else: :pure

    behaviour =
      case type do
        :pure ->
          Orchid.Step

        :symbiont ->
          unless Code.ensure_loaded?(OrchidSymbiont.Step) do
            raise """
            orchid_symbiont is not available.

            Add it to your deps:

                {:orchid_symbiont, "~> 0.2"}
            """
          end

          OrchidSymbiont.Step
      end

    # Set attributes during macro expansion so subsequent macros
    # (manifest/routine/ok) can read them during their own expansion.
    m = __CALLER__.module

    Module.put_attribute(m, :oi_name, name)
    Module.put_attribute(m, :oi_type, type)
    Module.put_attribute(m, :oi_symbiont, symbiont?)

    # manifest defaults (overridden by manifest/1)
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
  Declare step metadata. Must be called before `routine`.

  - `:inputs`  — input port names (atoms)
  - `:outputs` — keyword list, `port_name => param_type`
  - `:models`  — model names for symbiont steps (required when `symbiont?`)
  - `:heavy?`  — boolean, default `false`
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
  Define execution logic, expands to `run/2` (pure) or `run_with_model/3`
  (symbiont).

  Auto-unwraps input Params:
  - Single input `routine text, opts`     → payload bound directly
  - Multi-input `routine [a, b], opts`    → list unwrap
  - Multi-input `routine {a, b}, opts`    → tuple unwrap

  Symbiont `models` bound to handler map (e.g. `models.encoder`).
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

  @doc "Wraps value as `{:ok, Param | [Param]}`."
  defmacro ok(value) do
    case Module.get_attribute(__CALLER__.module, :oi_outputs) || [] do
      [] ->
        raise "ok/1 requires :outputs declared in manifest"

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

  @doc "Wraps reason as `{:error, reason}`."
  # Does not need compile-time info — plain function exported alongside ok.
  def err(reason), do: {:error, reason}

  # ─────────────────────────────────────────────────────────
  #  __before_compile__ : remaining callbacks + node spec
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
      raise "use Oi.Step requires :name option"
    end

    if type == :symbiont and models == [] do
      raise "symbiont? step requires non-empty :models in manifest"
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

  # fun       : target function name (:run / :run_with_model)
  # mid_args  : args between input Params and opts (symbiont's models_var)
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
        raise "routine must be called after `use Oi.Step`"

      other ->
        raise ArgumentError,
              "routine/#{arity} is for #{expected} step, got type #{other}" <>
                " (determined by `use` option `symbiont?`)"
    end
  end

  # AST shape classification.
  # Note: in Elixir AST, 2-tuples are "bare" `{a, b}`, variables are
  # 3-tuples `{:x, m, ctx}`, N-tuples are `{:{}, m, args}`.
  # The ordering + tuple_size checks below are safe because of this.
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
    |> unwrap_list()
    |> List.to_tuple()
  end

  # To resolve
  # list param map <-> tuple data inputs
  def unwrap_tuple(params) when is_list(params) do
    params
    |> unwrap_list()
    |> List.to_tuple()
  end

  @doc false
  def wrap_multi(values, spec) when is_tuple(values),
    do: wrap_multi(Tuple.to_list(values), spec)

  def wrap_multi(values, spec) when is_list(values) do
    unless length(values) == length(spec) do
      raise ArgumentError,
            "ok/1 expected #{length(spec)} outputs " <>
              "#{inspect(Keyword.keys(spec))}, got #{length(values)}"
    end

    values
    |> Enum.zip(spec)
    |> Enum.map(fn {v, {name, type}} -> Orchid.Param.new(name, type, v) end)
  end
end
