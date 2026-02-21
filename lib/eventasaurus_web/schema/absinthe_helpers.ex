defmodule EventasaurusWeb.Schema.AbsintheHelpers do
  @moduledoc """
  Helpers for Absinthe.Plug callbacks (e.g. before_send).
  """

  def before_send(conn, %Absinthe.Blueprint{} = _blueprint) do
    conn
  end
end
