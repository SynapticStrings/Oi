defmodule Oi.Executor do
  @moduledoc """
  Pluggable task execution strategy for stage fan-out.

  Each implementation controls how tasks within a single stage are
  dispatched and collected. The Dispatch calls `run/3` once per stage.

  ## Built-in implementations

    * `Oi.Executor.Sync`       — serial `Enum.map`, zero processes
    * `Oi.Executor.TaskSup`    — `Task.Supervisor.async_stream_nolink`
  """

  @type task :: Oi.Compile.Bundle.t()
  @type result :: {:ok, map()} | {:error, term()}
  @type worker :: (task() -> result())

  @callback run(tasks :: [task()], worker :: worker(), opts :: keyword()) ::
              [result()] | {:error, term()}
end
