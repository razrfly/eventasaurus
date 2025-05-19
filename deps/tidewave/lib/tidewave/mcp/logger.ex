defmodule Tidewave.MCP.Logger do
  @moduledoc false

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get_logs(n) do
    GenServer.call(__MODULE__, {:get_logs, n})
  end

  # Erlang/OTP log handler
  def log(event, config) do
    if event[:meta][:tidewave_mcp] do
      :ok
    else
      %{formatter: {formatter_mod, formatter_config}} = config
      chardata = formatter_mod.format(event, formatter_config)

      GenServer.cast(__MODULE__, {:log, IO.iodata_to_binary(chardata)})
    end
  end

  def init(_) do
    {:ok, %{cb: CircularBuffer.new(1024)}}
  end

  def handle_cast({:log, message}, state) do
    # There is a built-in way for MCPs to expose log messages,
    # but we currently don't use it, as the client support isn't really there.
    # https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/logging/
    cb = CircularBuffer.insert(state.cb, message)

    {:noreply, %{state | cb: cb}}
  end

  def handle_call({:get_logs, n}, _from, state) do
    logs = CircularBuffer.to_list(state.cb)
    {:reply, Enum.take(logs, -n), state}
  end
end
