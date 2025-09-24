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
        |> halt()
    end
  end

  # Rate Limiting Logic

  defp check_global_limit(client_id, current_time) do
    global_key = "global:#{client_id}"
    limit = if authenticated_user?(client_id), do: @global_limit_auth, else: @global_limit_anon

    check_rate_limit(global_key, current_time, limit)
  end

  defp check_poll_limit(client_id, poll_id, current_time) do
    poll_key = "poll:#{client_id}:#{poll_id}"
    check_rate_limit(poll_key, current_time, @per_poll_limit)
  end

  defp check_rate_limit(key, current_time, limit) do
    case :ets.lookup(@table_name, key) do
      [{^key, count, window_start}] ->
        if current_time - window_start < @window do
          if count >= limit do
            retry_after = div(@window - (current_time - window_start), 1000) + 1
            {:error, :rate_limited, retry_after}
          else
            :ets.update_counter(@table_name, key, {2, 1})
            :ok
          end
        else
          # Reset window
          :ets.insert(@table_name, {key, 1, current_time})
          :ok
        end

      [] ->
        # First request in window
        :ets.insert(@table_name, {key, 1, current_time})
        :ok
    end
  end

  # Helper Functions

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :named_table, :public])

      _ ->
        :ok
    end
  end

  defp get_client_identifier(conn) do
    case conn.assigns[:current_user] do
      %{id: user_id} -> "user:#{user_id}"
      _ -> "ip:#{get_client_ip(conn)}"
    end
  end

  defp get_client_ip(conn) do
    EventasaurusApp.IPExtractor.get_ip_from_conn(conn)
  end

  defp get_poll_id(conn) do
    # Extract poll ID from path params or body
    case conn.path_params do
      %{"poll_id" => poll_id} ->
        poll_id

      _ ->
        case conn.params do
          %{"poll_id" => poll_id} -> poll_id
          _ -> "unknown"
        end
    end
  end

  defp authenticated_user?("user:" <> _), do: true
  defp authenticated_user?(_), do: false
end
