defmodule EventasaurusWeb.Plugs.RawBodyPlug do
  @moduledoc """
  A plug to capture the raw request body for webhook signature verification.

  This plug reads the raw body and stores it in conn.assigns[:raw_body]
  while preserving the body for normal request processing.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case read_body(conn) do
      {:ok, body, conn} ->
        conn
        |> assign(:raw_body, body)
        |> put_req_header("content-length", to_string(byte_size(body)))

      {:more, _partial_body, conn} ->
        # Handle large bodies by reading in chunks
        read_full_body(conn, "")

      {:error, _reason} ->
        conn
    end
  end

  defp read_full_body(conn, acc) do
    case read_body(conn) do
      {:ok, body, conn} ->
        full_body = acc <> body

        conn
        |> assign(:raw_body, full_body)
        |> put_req_header("content-length", to_string(byte_size(full_body)))

      {:more, partial_body, conn} ->
        read_full_body(conn, acc <> partial_body)

      {:error, _reason} ->
        conn
    end
  end
end
