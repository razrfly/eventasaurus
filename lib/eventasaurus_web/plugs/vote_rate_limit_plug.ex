defmodule EventasaurusWeb.Plugs.VoteRateLimitPlug do
  @moduledoc """
  Specialized rate limiting for poll voting to prevent vote spamming.

  Stricter limits than general API rate limiting:
  - Authenticated users: 30 votes per minute across all polls
  - Anonymous users: 10 votes per minute per IP
  - Per-poll limit: 5 votes per minute per user/IP
  """

  import Plug.Conn
  require Logger

  @table_name :vote_rate_limit_table
  # votes per minute for authenticated users
  @global_limit_auth 30
  # votes per minute for anonymous users
  @global_limit_anon 10
  # votes per minute per poll
  @per_poll_limit 5
  # 1 minute window
  @window 60_000

  def init(opts) do
    ensure_table_exists()
    opts
  end

  def call(conn, _opts) do
    ensure_table_exists()

    client_id = get_client_identifier(conn)
    poll_id = get_poll_id(conn)
    current_time = System.system_time(:millisecond)

    # Check both global and per-poll limits
    with :ok <- check_global_limit(client_id, current_time),
         :ok <- check_poll_limit(client_id, poll_id, current_time) do
      conn
    else
      {:error, :rate_limited, retry_after} ->
        Logger.warning("Vote rate limit exceeded",
          client_id: client_id,
          poll_id: poll_id,
          path: conn.request_path
        )

        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(retry_after))
        |> Phoenix.Controller.json(%{
          error: "vote_rate_limit_exceeded",
          message: "Too many votes. Please wait before voting again.",
          retry_after: retry_after
        })
        |> halt()
    end
  end

  defp get_client_identifier(conn) do
    case conn.assigns[:current_user] do
      %{id: user_id} -> {:authenticated, "user:#{user_id}"}
      _ -> {:anonymous, "ip:#{format_ip(conn.remote_ip)}"}
    end
  end

  defp get_poll_id(conn) do
    # Extract poll_id from params or path
    conn.params["poll_id"] || conn.params["id"] ||
      conn.path_params["poll_id"] || conn.path_params["id"]
  end

  defp check_global_limit({auth_type, client_id}, current_time) do
    limit =
      case auth_type do
        :authenticated -> @global_limit_auth
        :anonymous -> @global_limit_anon
      end

    check_rate_limit("global:#{client_id}", current_time, limit)
  end

  defp check_poll_limit({_auth_type, _client_id}, nil, _current_time), do: :ok

  defp check_poll_limit({_auth_type, client_id}, poll_id, current_time) do
    check_rate_limit("poll:#{poll_id}:#{client_id}", current_time, @per_poll_limit)
  end

  defp check_rate_limit(key, current_time, limit) do
    window_start = current_time - @window

    case :ets.lookup(@table_name, key) do
      [] ->
        :ets.insert(@table_name, {key, [current_time]})
        :ok

      [{^key, timestamps}] ->
        recent_timestamps = Enum.filter(timestamps, &(&1 > window_start))

        if length(recent_timestamps) >= limit do
          # Calculate retry_after based on oldest timestamp in window
          oldest_in_window = Enum.min(recent_timestamps)
          retry_after = div(oldest_in_window + @window - current_time, 1000)
          {:error, :rate_limited, max(retry_after, 1)}
        else
          new_timestamps = [current_time | recent_timestamps]
          :ets.insert(@table_name, {key, new_timestamps})
          :ok
        end
    end
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_), do: "unknown"

  defp ensure_table_exists do
    if :ets.whereis(@table_name) == :undefined do
      try do
        :ets.new(@table_name, [:set, :public, :named_table])
      rescue
        ArgumentError -> :ok
      end
    end
  end
end

