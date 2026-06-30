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
          | {:error, :invalid_data_format}
  def resolve_data(data, edges) when is_map(data) do
    with {:ok, flat} <- flatten_data(data) do
      Enum.reduce(flat, {%{}, %{}}, fn {{node_id, port} = key, value}, {mem, intv} ->
        case find_producer(edges, node_id, port) do
          nil ->
            {Map.put(mem, key, value), intv}

          {producer_node, producer_port} ->
            {mem, Map.put(intv, {producer_node, producer_port}, value)}
        end
      end)
    end
  end

  def build_drafting_inputs(%Compiled{edges: edges}, opts) do
    data = Keyword.get(opts, :data, %{})

    with {memory_raw, interventions_raw} when is_map(memory_raw) <- resolve_data(data, edges) do
      memory_io =
        Map.new(memory_raw, fn {{n, p}, v} ->
          {PortRef.to_orchid_key({:port, n, p}),
           wrap_orchid_param(PortRef.to_orchid_key({:port, n, p}), v)}
        end)

      # Interventions stay raw — no Param wrapping here.
      # Wrapping happens once in assemble_run_opts/3 when building the
      # final {type, %Orchid.Param{}} tuple for Orchid's ApplyInterventions hook.
      interventions_io =
        Map.new(interventions_raw, fn {{n, p}, v} ->
          {PortRef.to_orchid_key({:port, n, p}), v}
        end)

      {memory_io, interventions_io}
    end
  end

  # 2. ---- Orchid options management ----

  @doc """
  Assemble the keyword list passed to `Orchid.run/3`.

  Merges interventions from Drafting, user baggage from Config, and resolves
  `scope_id`.  Does NOT inject OrchidSymbiont.Hooks.Injector — use
  `Oi.Adapters.orchid_symbiont/1` in the `:orchid_adapters` chain instead.
  """
  @spec assemble_run_opts(keyword(), Oi.Dispatch.Config.t(), Oi.Dispatch.Drafting.t()) ::
          keyword()
  def assemble_run_opts(opts, conf, drafting) do
    {old_hooks, opts_no_hooks} = Keyword.pop(opts, :global_hooks_stack, [])
    {old_baggage, opts_clean} = Keyword.pop(opts_no_hooks, :baggage, %{})

    merged_baggage =
      old_baggage
      |> case do
        nil -> %{}
        m when is_map(m) -> m
        k when is_list(k) -> Enum.into(k, %{})
      end
      |> Map.merge(conf.orchid_baggage)
      |> Map.put(:interventions, wrap_interventions_for_orchid(drafting.interventions))
      |> Map.put_new(:symbiont_mapper, Map.get(conf.orchid_baggage, :symbiont_mapper, %{}))
      |> maybe_put_scope_id(conf)

    opts_clean ++
      [baggage: merged_baggage, global_hooks_stack: old_hooks]
  end

  defp maybe_put_scope_id(baggage, conf) do
    scope_id = conf.name || Map.get(baggage, :scope_id)
    if scope_id, do: Map.put(baggage, :scope_id, scope_id), else: baggage
  end

  # Takes raw interventions from Drafting (as produced by build_drafting_inputs/2)
  # and wraps them once into {type, %Orchid.Param{}} tuples for Orchid's
  # ApplyInterventions hook.
  defp wrap_interventions_for_orchid(interventions) do
    Map.new(interventions, fn {key, value} ->
      {type, val} =
        case value do
          {t, v} -> {t, v}
          plain -> {:override, plain}
        end

      {key, {type, ensure_orchid_param(key, val)}}
    end)
  end

  defp ensure_orchid_param(key, %Orchid.Param{} = p), do: %{p | name: key}
  defp ensure_orchid_param(key, val), do: Orchid.Param.new(key, :any, val)

  # ---- Helpers ----

  # Allow mixed data like
  # %{{:a, :x} => 1, b: %{y: 2}}
  defp flatten_data(data) do
    tuple_format? =
      Enum.all?(data, fn
        {{_node, _port}, _value} -> true
        _ -> false
      end)

    nested_format? =
      Enum.all?(data, fn
        {node, ports} when (is_atom(node) or is_binary(node)) and is_map(ports) -> true
        _ -> false
      end)

    cond do
      tuple_format? ->
        {:ok, data}

      nested_format? ->
        {:ok,
         for {node, ports} <- data,
             {port, val} <- ports,
             into: %{} do
           {{node, port}, val}
         end}

      true ->
        {:error, :invalid_data_format}
    end
  end

  defp find_producer(edges, node_id, port) do
    case Enum.find(edges, fn e -> e.to_node == node_id and e.to_port == port end) do
      nil -> nil
      edge -> {edge.from_node, edge.from_port}
    end
  end

  defp wrap_orchid_param(name, %Orchid.Param{} = p), do: %{p | name: name}
  defp wrap_orchid_param(name, val), do: Orchid.Param.new(name, :any, val)
end
