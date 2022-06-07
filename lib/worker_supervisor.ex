defmodule Pooly.WorkerSupervisor do
  use DynamicSupervisor

  def start_link([pool_server, args]) do
    DynamicSupervisor.start_link(__MODULE__, [pool_server, args])
  end

  @impl true
  def init([pool_server, _args]) do
    IO.inspect(pool_server, label: "pool server pid")
    IO.inspect(self(), label: "worker sup pid")
    Process.link(pool_server)

    opts = [
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 5
    ]
    DynamicSupervisor.init(opts)
  end

end
