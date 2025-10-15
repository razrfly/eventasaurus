defmodule EventasaurusWeb.NotFoundError do
  @moduledoc """
  Exception for 404 Not Found errors in LiveView.
  Implements Plug.Exception protocol to return 404 status.
  """
  defexception message: "Not Found", plug_status: 404
end
