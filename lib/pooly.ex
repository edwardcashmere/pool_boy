defmodule Pooly do

  @timeout 5000

  use Application

  def start(_type, _args) do
    pool_config = [[name: "pool1", mfa: {Pooly.Worker, :start_link, []}, size: 2,max_overflow: 1],
                   [name: "pool2", mfa: {Pooly.Worker, :start_link, []}, size: 3, max_overflow: 0],
                   [name: "pool3", mfa: {Pooly.Worker, :start_link, []}, size: 4, max_overflow: 0]
  ]
    start_pools(pool_config)
  end

  def start_pools(pool_config) do
    Pooly.Supervisor.start_link(pool_config)
  end

  def checkout(pool_name, block \\ true, timeout \\ @timeout) do
    Pooly.PoolServer.checkout(pool_name, block, timeout)
  end

  def checkin(pool_name, worker_pid) do
    Pooly.PoolServer.checkin(pool_name ,worker_pid)
  end

  def status(pool_name) do
    Pooly.PoolServer.status(pool_name)
  end
end
