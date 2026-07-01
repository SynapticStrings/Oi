defmodule Oi.Flowgraph do
  @moduledoc "A higher API for building graph."

  alias Oi.Topology.Graph

  # ---- Functional API ----

  defguard belongs_port(key) when is_atom(key) or is_binary(key)

  defdelegate new_flowchart, to: Oi.Topology.Graph, as: :new

  @spec add_step(Graph.t(), module(), keyword()) :: Graph.t()
  def add_step(%Graph{} = graph, oi_step, opts \\ []) when is_atom(oi_step) do
    {:module, ^oi_step} = Code.ensure_loaded(oi_step)

    unless function_exported?(oi_step, :__node_spec__, 0) do
      raise ArgumentError,
            "#{inspect(oi_step)} does not export __node_spec__/0. " <>
              "Did it use Oi.Step?"
    end

    node = struct(Graph.Node, oi_step.__node_spec__())

    node_alias = Keyword.get(opts, :as, node.id)
    node_options = Keyword.get(opts, :opts, [])

    Graph.add_node(graph, %{node | id: node_alias, options: node_options})
  end

  def connect(%Graph{} = graph, {from_node, from_port}, {to_node, to_port})
      when belongs_port(from_node) and belongs_port(from_port) and
             belongs_port(to_node) and belongs_port(to_port) do
    Graph.add_edge(graph, Graph.Edge.new(from_node, from_port, to_node, to_port))
  end

  # ---- DSL Macros ----

  @doc """
  DSL entry point.  Initialises an empty graph and evaluates the body,
  returning the fully built graph.

  ## Example

      iex> import Oi.Flowgraph
      iex> graph = graph do
      ...>   step OiTest.DummyOiStep.Greet
      ...>   step OiTest.DummyOiStep.Exclaim
      ...>   greet.greeting ~> exclaim.text
      ...> end
      iex> map_size(graph.nodes)
      2
      iex> MapSet.size(graph.edges)
      1
  """
  defmacro graph(do: block) do
    quote do
      var!(graph_acc) = Oi.Flowgraph.new_flowchart()
      unquote(block)
      var!(graph_acc)
    end
  end

  @doc """
  Add a step to the accumulated graph.

  The module must `use Oi.Step` (i.e. expose `__node_spec__/0`).
  Validated at compile time — raises `ArgumentError` if the module
  does not implement the expected contract.

  ## Options

    * `:as`   — node alias (default: module's declared name)
    * `:opts` — keyword list forwarded as step options
  """
  defmacro step(module, opts \\ []) do
    resolved = Macro.expand(module, __CALLER__)

    Code.ensure_compiled!(resolved)

    unless function_exported?(resolved, :__node_spec__, 0) do
      raise ArgumentError,
            "#{inspect(resolved)} does not export __node_spec__/0. " <>
              "Did it use Oi.Step?"
    end

    quote do
      var!(graph_acc) =
        Oi.Flowgraph.add_step(var!(graph_acc), unquote(resolved), unquote(opts))
    end
  end

  @doc """
  Add multiple steps at once when they share no options.

  All modules are validated at compile time just like `step/1`.
  Equivalent to calling `step` for each module with no options.

  ## Example

      many_step [LoadPosts, LoadPages, LoadImages]
  """
  defmacro many_step(modules) do
    {:__block__, [], Enum.map(modules, &build_step_ast/1)}
  end

  defp build_step_ast(mod) do
    quote do
      Oi.Flowgraph.step(unquote(mod))
    end
  end

  @doc """
  Connect two node ports.

  Both sides accept two forms:

    * `node.port`   — dot-expression
    * `{node, port}` — explicit tuple
  """
  defmacro left ~> right do
    from = extract_port_pair(left, __CALLER__)
    to = extract_port_pair(right, __CALLER__)

    quote do
      var!(graph_acc) =
        Oi.Flowgraph.connect(var!(graph_acc), unquote(from), unquote(to))
    end
  end

  # ---- Port-pair extraction (compile-time) ----

  # Dot expression: node.port
  defp extract_port_pair(
         {{:., _, [{node, _, ctx}, port]}, _, []},
         _env
       )
       when is_atom(node) and is_atom(port) and is_atom(ctx) do
    {node, port}
  end

  # Aliased module: Module.Sub.step.port
  defp extract_port_pair(
         {{:., _, [{:__aliases__, _, mod_parts}, port]}, _, []},
         _env
       )
       when is_list(mod_parts) and is_atom(port) do
    {Module.concat(mod_parts), port}
  end

  # 2-tuple literal: {node, port}
  defp extract_port_pair({node, port}, _env)
       when is_atom(node) and is_atom(port) do
    {node, port}
  end

  defp extract_port_pair(other, _env) do
    raise ArgumentError,
          "~> expects node.port or {node, port}, got: #{Macro.to_string(other)}"
  end
end
