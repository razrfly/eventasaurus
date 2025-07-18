defmodule EventasaurusApp.IPExtractor do
  @moduledoc """
  Shared utilities for extracting client IP addresses from Plug connections.
  
  Handles both direct connections and proxied connections by checking for
  the X-Forwarded-For header first, then falling back to the remote IP.
  """

  @doc """
  Extracts the client IP address from a Plug connection.
  
  First checks for the X-Forwarded-For header (for proxied connections),
  then falls back to the remote IP address from the connection.
  
  Returns a string representation of the IP address.
  """
  def get_ip_from_conn(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> 
        case :inet.ntoa(conn.remote_ip) do
          ip when is_list(ip) -> to_string(ip)
          _ -> "unknown"
        end
    end
  end
end