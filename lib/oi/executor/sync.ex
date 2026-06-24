defmodule Oi.Executor.Sync do
  @moduledoc "Serial executor — runs all tasks in the calling process."
  @behaviour Oi.Executor

  @impl true
  def run(tasks, worker, _opts) do
    Enum.map(tasks, worker)
  end
end
