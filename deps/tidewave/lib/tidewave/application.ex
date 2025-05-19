defmodule Tidewave.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Tidewave.MCP
    ]

    opts = [strategy: :one_for_one, name: Tidewave.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
