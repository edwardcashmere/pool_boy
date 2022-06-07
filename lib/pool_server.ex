defmodule Pooly.PoolServer do
  use GenServer
  defmodule State do
    defstruct pool_sup: nil, size: nil, mfa: nil, worker_sup: nil, workers: nil, monitors: nil, name: nil, overflow: 0, max_overflow: nil, waiting: nil
  end

  def start_link([pool_sup, pool_config]) do
    GenServer.start_link(__MODULE__, [pool_sup, pool_config], name: name(pool_config[:name]))
  end

  def status(pool_name) do
    GenServer.call(name(pool_name), :status)
  end

  def checkout(pool_name, block, timeout) do
    IO.inspect("checking out worker")
    GenServer.call(name(pool_name), {:checkout, block}, timeout)
  end

  def info(name) do
    GenServer.call(name, {:info, name})
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  def init([pool_sup, pool_config]) when is_pid(pool_sup) do
    Process.flag(:trap_exit, true)
    IO.inspect(self(), label: "#{pool_config[:name]}")
    waiting = :queue.new()
    monitors = :ets.new(:monitors, [:private])
    init(pool_config, %State{pool_sup: pool_sup, monitors: monitors, waiting: waiting})
  end

  def init([{:size, size}|rest], state) do
    init(rest, %{state | size: size})
  end

  def init([{:max_overflow, max_overflow}|rest], state) do
    init(rest, %{state | max_overflow: max_overflow})
  end

  def init([{:name, name}|rest], state) do
    init(rest, %{state | name: name})
  end

  def init([{:mfa, mfa}|rest], state) do
    init(rest, %{state | mfa: mfa})
  end

  def init([_|rest], state) do
    init(rest, state)
  end

  @impl true
  def init([], state) do
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  @impl true
  def handle_cast({:checkin, worker}, %{monitors: monitors} = state) do
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_checkin(pid, state)
        {:noreply, new_state}

      [] ->
        {:noreply, state}
    end
  end

 @impl true
 def handle_call({:info, name},_from, state) do
  {:reply, Process.info(name, :links), state}
 end

 @impl true
  def handle_call({:checkout, block}, {from_pid, _ref} = from, %{worker_sup: worker_sup, workers: workers, monitors: monitors,
  overflow: overflow, max_overflow: max_overflow, waiting: waiting} = state) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] when max_overflow > 0 and overflow < max_overflow ->
        ref = Process.monitor(from_pid)
        worker = new_worker(worker_sup)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | overflow: overflow + 1}}

      [] when block == true ->
       ref = Process.monitor(from_pid)
       waiting = :queue.in({from, ref}, waiting)

       {:noreply, %{state | waiting: waiting}, :infinity}
      [] ->
        {:reply, :noproc, state}
    end
  end

  @impl true
  def handle_call(:status, _from, %{monitors: monitors, workers: workers} = state) do
    {:reply, {state_name(state),length(workers), :ets.info(monitors, :size)}, state}
  end

  @impl true
  def handle_info(:start_worker_supervisor, %{pool_sup: pool_sup, size: size, mfa: mfa, name: name} = state) do
    {:ok, worker_sup} = Supervisor.start_child(pool_sup, supervisor_spec(name, mfa))
    workers = prepopulate(size, worker_sup)
    IO.inspect(Process.info(worker_sup, :links), label: "worker sup links")
    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  @impl true
  def handle_info({:DOWN, ref,_, _, _}, state = %{monitors: monitors, workers: workers}) do
    IO.inspect("I get called")
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid| workers]}
        {:noreply, new_state}
      [[]] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, _reason},  %{monitors: monitors} = state) do
    IO.inspect(state, label: "state struct")
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_worker_exit(pid, state)
        {:noreply, new_state}

      [[]] ->
        {:noreply, state}
    end
  end

  defp state_name(%State{overflow: _overflow, max_overflow: max_overflow, workers: workers}) do
      case length(workers) == 0 do
        true ->
          if max_overflow < 1 do
            :full
          else
            :overflow
          end
        false ->
          :ready
      end
  end

  defp state_name(%State{overflow: _overflow, max_overflow: _max_overflow}) do
    :full
  end

  defp state_name(_state) do
    :overflow
  end

  defp handle_checkin(pid, state) do
    %{workers: workers, overflow: overflow, worker_sup: worker_sup, waiting: waiting, monitors: monitors} = state

    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        true = :ets.insert(monitors, {pid, ref})
        GenServer.reply(from, pid)
        %{state | waiting: left}

      {:empty, empty} when overflow > 0 ->
        :ok = dismiss_worker(worker_sup, pid)
        %{state | waiting: empty, overflow: overflow - 1}

      {:empty, empty} ->
        %{state | waiting: empty, overflow: 0, workers: [pid | workers]}

    end
  end

  defp handle_worker_exit(_pid, state) do
    %{overflow: overflow, workers: workers, worker_sup: worker_sup, waiting: waiting, monitors: monitors} = state


    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        new_worker = new_worker(worker_sup)
        true = :ets.insert(monitors, {new_worker, ref})
        GenServer.reply(from, new_worker)
        %{state | waiting: left}

      {:empty, empty} when overflow >0 ->
        %{state | oveflow: overflow-1, waiting: empty}

      {:empty, empty} ->
        %{state | workers: [new_worker(worker_sup) | workers], waiting: empty}
      end
  end

  defp dismiss_worker(worker_sup, pid) do
    true = Process.unlink(pid)
    Supervisor.terminate_child(worker_sup, pid)
  end

  defp name(pool_name) do
    :"#{pool_name}Server"
  end

  defp supervisor_spec(name,mfa) do
    Supervisor.child_spec({Pooly.WorkerSupervisor, [self(), mfa]}, id: name <> "WorkerSupervisor", restart: :temporary)
  end

  defp prepopulate(size, sup) do
    prepopulate(size, sup, [])
  end

  defp prepopulate(size, _sup, workers) when size < 1 do
    workers
  end

  defp prepopulate(size, sup, workers) do
    prepopulate(size - 1, sup, [new_worker(sup) | workers])
  end

  defp new_worker(sup) do
    {:ok, worker} = DynamicSupervisor.start_child(sup, {Pooly.Worker,[]})
    worker
  end

end
