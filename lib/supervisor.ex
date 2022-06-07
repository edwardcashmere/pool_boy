defmodule Pooly.Supervisor do
  use Supervisor

  def start_link(pool_config) do
    Supervisor.start_link(__MODULE__, pool_config, name: __MODULE__)
  end

  def init(pool_config) do
    children = [
      {Pooly.Server, [pool_config]},
      {Pooly.PoolsSupervisor, []}
    ]
    Supervisor.init(children, strategy: :one_for_all)
  end
end
