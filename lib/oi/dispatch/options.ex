defmodule Oi.Dispatch.Options do
  # 负责 dispatch 时的选项
  alias Oi.Compiled
  alias Oi.Topology.Graph.{Edge, PortRef, Node}

  # 1. ---- opts when Oi.execute ----

  @typedoc """
  Unified user-facing data for Oi.execute/2.

  Replaces the separate `:inputs` / `:interventions` opts.

  ## Format A — tuple keys
      %{{:step1, :in} => "foo", {:step2, :result} => {:override, "bar"}}

  ## Format B — nested
      %{step1: %{in: "foo"}, step2: %{result: {:override, "bar"}}}
  """
  @type data ::
          %{
            optional({Node.id(), Node.node_port()}) => term()
          }
          | %{
              optional(Node.id()) => %{
                optional(Node.node_port()) => term()
              }
            }

  @doc """
  Splits unified `data` into `{memory, interventions}` by topology.

  For each `{node, port}`:
    * has incoming edge → intervention (data originates inside the graph)
    * no incoming edge  → memory (external input, no upstream producer)

  Values pass through as-is — no wrapping, no io_key conversion.
  """
  @spec resolve_data(data(), MapSet.t(Edge.t())) ::
          {%{{Node.id(), Node.node_port()} => term()}, %{{Node.id(), Node.node_port()} => term()}}
  def resolve_data(data, edges) when is_map(data) do
    flat = flatten_data(data)

    Enum.reduce(flat, {%{}, %{}}, fn {{node_id, port} = key, value}, {mem, intv} ->
      if has_upstream?(edges, node_id, port) do
        {mem, Map.put(intv, key, value)}
      else
        {Map.put(mem, key, value), intv}
      end
    end)
  end

  def build_drafting_inputs(%Compiled{edges: edges}, opts) do
    data = Keyword.get(opts, :data, %{})

    {memory_raw, interventions_raw} = resolve_data(data, edges)

    memory_io =
      Map.new(memory_raw, fn {{n, p}, v} ->
        {PortRef.to_orchid_key({:port, n, p}),
         wrap_orchid_param(PortRef.to_orchid_key({:port, n, p}), v)}
      end)

    interventions_io =
      Map.new(interventions_raw, fn {{n, p}, v} ->
        {PortRef.to_orchid_key({:port, n, p}),
         wrap_orchid_param(PortRef.to_orchid_key({:port, n, p}), v)}
      end)

    {memory_io, interventions_io}
  end

  # 2. ---- Orchid options management ----

  @doc """
  Assemble the keyword list passed to `Orchid.run/3`.

  Merges interventions from Drafting, user baggage from Config, computes
  `scope_id`, and ensures `OrchidSymbiont.Hooks.Injector` is in the hook
  stack (exactly once).
  """
  @spec assemble_run_opts(keyword(), Oi.Dispatch.Config.t(), Oi.Dispatch.Drafting.t()) ::
          keyword()
  def assemble_run_opts(opts, conf, drafting) do
    {old_hooks, opts_no_hooks} = Keyword.pop(opts, :global_hooks_stack, [])
    {old_baggage, opts_clean} = Keyword.pop(opts_no_hooks, :baggage, %{})

    hooks_stack =
      old_hooks
      |> Kernel.++([OrchidSymbiont.Hooks.Injector])
      |> Enum.uniq()

    merged_baggage =
      old_baggage
      |> case do
        nil -> %{}
        m when is_map(m) -> m
        k when is_list(k) -> Enum.into(k, %{})
      end
      |> Map.merge(conf.orchid_baggage)
      |> Map.put(:interventions, drafting.interventions)
      |> Map.put_new(:symbiont_mapper, Map.get(conf.orchid_baggage, :symbiont_mapper, %{}))
      |> maybe_put_scope_id(conf)

    opts_clean ++
      [baggage: merged_baggage, global_hooks_stack: hooks_stack]
  end

  defp maybe_put_scope_id(baggage, conf) do
    scope_id = conf.name || Map.get(baggage, :scope_id)
    if scope_id, do: Map.put(baggage, :scope_id, scope_id), else: baggage
  end

  # ---- Helpers ----

  defp flatten_data(data) do
    cond do
      Enum.all?(data, fn
        {{_node, _port}, _value} -> true
        _ -> false
      end) ->
        data

      true ->
        for {node, ports} <- data,
            is_map(ports),
            {port, val} <- ports,
            into: %{} do
          {{node, port}, val}
        end
    end
  end

  defp has_upstream?(edges, node_id, port) do
    Enum.any?(edges, fn e -> e.to_node == node_id and e.to_port == port end)
  end

  defp wrap_orchid_param(name, %Orchid.Param{} = p), do: %{p | name: name}
  defp wrap_orchid_param(name, val), do: Orchid.Param.new(name, :any, val)
end
