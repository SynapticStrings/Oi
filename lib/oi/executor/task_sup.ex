defmodule Oi.Executor.TaskSup do
  @moduledoc """
  Task.Supervisor-backed executor — concurrent fan-out with crash isolation.

  Requires `:sup` option (a named Task.Supervisor pid or via tuple).
  """
  @behaviour Oi.Executor

  @impl true
  def run(tasks, worker, opts) do
    with {:ok, sup} <- Keyword.fetch(opts, :sup) do
      concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
      timeout = Keyword.get(opts, :timeout, :infinity)

      Task.Supervisor.async_stream_nolink(
        sup,
        tasks,
        worker,
        max_concurrency: concurrency,
        timeout: timeout,
        ordered: false
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:worker_crashed, reason}}
      end)
    else
      :error -> {:error, {:missing_opt, :sup}}
    end
  end
end
