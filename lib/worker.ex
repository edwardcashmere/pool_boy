defmodule Pooly.Worker do
  use GenServer, restart: :transient

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  @impl true
  def init(:ok) do
    {:ok, []}
  end

  def info(pid) do
    GenServer.call(pid, :info)
  end

  def work_for(pid, duration) do
    GenServer.cast(pid, {:work_for, duration})
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, Process.info(self(), :links), state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end
  @impl true
  def handle_cast({:work_for, duration}, state) do
    IO.inspect(Process.info(self(), :links), label: "links")
    IO.inspect(self(), label: "worker process pid")
    :timer.sleep(duration)
    IO.inspect("I have exited")
    {:stop, :normal, state}
  end

end
