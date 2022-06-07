defmodule Pooly.PoolsSupervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_child(child_specs) do
    IO.inspect("I try to start child but fail")
    DynamicSupervisor.start_child(__MODULE__, child_specs)
  end

  def init(_) do
    opts = [strategy: :one_for_one]
    IO.inspect("PoolsSupervisor started")
    DynamicSupervisor.init(opts)
  end
end
