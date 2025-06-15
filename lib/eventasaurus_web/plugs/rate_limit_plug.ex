defmodule EventasaurusWeb.Plugs.RateLimitPlug do
  @moduledoc """
  Rate limiting plug to prevent abuse of sensitive endpoints.

  Uses ETS for simple in-memory rate limiting. In production,
  consider using Redis or a dedicated rate limiting service.
  """

  import Plug.Conn
  require Logger

  @table_name :rate_limit_table

  def init(opts) do
    # Ensure ETS table exists
    unless :ets.whereis(@table_name) != :undefined do
      :ets.new(@table_name, [:set, :public, :named_table])
    end

    opts
  end

  def call(conn, opts) do
    limit = Keyword.get(opts, :limit, 100)  # requests per window
    window = Keyword.get(opts, :window, 60_000)  # window in milliseconds (1 minute)

    client_id = get_client_identifier(conn)
    current_time = System.system_time(:millisecond)

    case check_rate_limit(client_id, current_time, limit, window) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        Logger.warning("Rate limit exceeded",
          client_id: client_id,
          path: conn.request_path,
          method: conn.method,
          limit: limit,
          window: window
        )

        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(div(window, 1000)))
        |> Phoenix.Controller.json(%{
          error: "rate_limit_exceeded",
          message: "Too many requests. Please try again later.",
          retry_after: div(window, 1000)
        })
        |> halt()
    end
  end

  defp get_client_identifier(conn) do
    # Try to get user ID first, fall back to IP
    case conn.assigns[:user] do
      %{id: user_id} -> "user:#{user_id}"
      _ -> "ip:#{format_ip(conn.remote_ip)}"
    end
  end

  defp check_rate_limit(client_id, current_time, limit, window) do
    window_start = current_time - window

    # Clean old entries and get current count
    case :ets.lookup(@table_name, client_id) do
      [] ->
        # First request from this client
        :ets.insert(@table_name, {client_id, [current_time]})
        :ok

      [{^client_id, timestamps}] ->
        # Filter out old timestamps
        recent_timestamps = Enum.filter(timestamps, &(&1 > window_start))

        if length(recent_timestamps) >= limit do
          {:error, :rate_limited}
        else
          # Add current timestamp and update
          new_timestamps = [current_time | recent_timestamps]
          :ets.insert(@table_name, {client_id, new_timestamps})
          :ok
        end
    end
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_), do: "unknown"
end
