defmodule EventasaurusApp.Auth.Clerk.Client do
  @moduledoc """
  HTTP client for Clerk Backend API.

  Provides functions to interact with Clerk's Backend API for user management,
  session verification, and other administrative operations.

  ## Configuration

  Requires the following configuration in runtime.exs:

      config :eventasaurus, :clerk,
        secret_key: "sk_test_...",
        domain: "your-app.clerk.accounts.dev"

  ## Usage

      # Get a user by ID
      {:ok, user} = Client.get_user("user_abc123")

      # Get a user by external ID (Supabase UUID)
      {:ok, user} = Client.get_user_by_external_id("ea9eb0a9-729a-4329-b760-6033c309e583")

      # List all users
      {:ok, users} = Client.list_users()
  """

  require Logger

  @base_url "https://api.clerk.com/v1"
  @timeout 30_000

  # ============================================================================
  # User Operations
  # ============================================================================

  @doc """
  Get a user by their Clerk user ID.

  ## Examples

      {:ok, user} = Client.get_user("user_abc123")
      {:error, :not_found} = Client.get_user("user_nonexistent")
  """
  def get_user(user_id) do
    request(:get, "/users/#{user_id}")
  end

  @doc """
  Get a user by their external ID (e.g., Supabase UUID).

  This is useful during migration when you need to look up users by their
  original Supabase ID.

  ## Examples

      {:ok, user} = Client.get_user_by_external_id("ea9eb0a9-729a-4329-b760-6033c309e583")
  """
  def get_user_by_external_id(external_id) do
    case list_users(external_id: external_id) do
      {:ok, [user | _]} -> {:ok, user}
      {:ok, []} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  List users with optional filters.

  ## Options

    * `:limit` - Maximum number of users to return (default: 10, max: 500)
    * `:offset` - Number of users to skip (for pagination)
    * `:email_address` - Filter by email address
    * `:external_id` - Filter by external ID
    * `:phone_number` - Filter by phone number
    * `:order_by` - Sort order (e.g., "+created_at", "-created_at")

  ## Examples

      {:ok, users} = Client.list_users(limit: 100)
      {:ok, users} = Client.list_users(email_address: "user@example.com")
      {:ok, users} = Client.list_users(external_id: "supabase-uuid-here")
  """
  def list_users(opts \\ []) do
    query_params =
      opts
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Enum.map(fn
        {:email_address, v} -> {"email_address", v}
        {:external_id, v} -> {"external_id", v}
        {:phone_number, v} -> {"phone_number", v}
        {:limit, v} -> {"limit", to_string(v)}
        {:offset, v} -> {"offset", to_string(v)}
        {:order_by, v} -> {"order_by", v}
      end)
      |> URI.encode_query()

    path = if query_params == "", do: "/users", else: "/users?#{query_params}"
    request(:get, path)
  end

  @doc """
  Update a user's attributes.

  ## Examples

      {:ok, user} = Client.update_user("user_abc123", %{
        first_name: "John",
        last_name: "Doe"
      })
  """
  def update_user(user_id, attrs) do
    request(:patch, "/users/#{user_id}", attrs)
  end

  @doc """
  Delete a user.

  ## Examples

      {:ok, _} = Client.delete_user("user_abc123")
  """
  def delete_user(user_id) do
    request(:delete, "/users/#{user_id}")
  end

  # ============================================================================
  # Session Operations
  # ============================================================================

  @doc """
  Get a session by its ID.

  ## Examples

      {:ok, session} = Client.get_session("sess_abc123")
  """
  def get_session(session_id) do
    request(:get, "/sessions/#{session_id}")
  end

  @doc """
  Revoke a session.

  ## Examples

      {:ok, session} = Client.revoke_session("sess_abc123")
  """
  def revoke_session(session_id) do
    request(:post, "/sessions/#{session_id}/revoke")
  end

  @doc """
  Verify a client session token.

  This is an alternative to JWT verification when you need to verify
  a session token against Clerk's servers.

  ## Examples

      {:ok, client} = Client.verify_client(session_token)
  """
  def verify_client(token) do
    request(:get, "/clients/verify?token=#{URI.encode_www_form(token)}")
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp request(method, path, body \\ nil) do
    url = @base_url <> path
    headers = build_headers()

    options = [
      recv_timeout: @timeout
    ]

    result =
      case method do
        :get ->
          HTTPoison.get(url, headers, options)

        :post ->
          json_body = if body, do: Jason.encode!(body), else: ""
          HTTPoison.post(url, json_body, headers, options)

        :patch ->
          json_body = if body, do: Jason.encode!(body), else: ""
          HTTPoison.patch(url, json_body, headers, options)

        :delete ->
          HTTPoison.delete(url, headers, options)
      end

    handle_response(result)
  end

  defp build_headers do
    secret_key = get_config(:secret_key)

    if is_nil(secret_key) do
      raise "Clerk secret_key is not configured. Set CLERK_SECRET_KEY environment variable."
    end

    [
      {"Authorization", "Bearer #{secret_key}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}})
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:ok, body}
    end
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 404}}) do
    {:error, :not_found}
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 401}}) do
    {:error, :unauthorized}
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 403}}) do
    {:error, :forbidden}
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 422, body: body}}) do
    case Jason.decode(body) do
      {:ok, %{"errors" => errors}} -> {:error, {:validation_error, errors}}
      _ -> {:error, :validation_error}
    end
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}) do
    Logger.error("Clerk API error: status=#{status}, body=#{body}")
    {:error, {:api_error, status, body}}
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    Logger.error("Clerk API request failed: #{inspect(reason)}")
    {:error, {:request_failed, reason}}
  end

  defp get_config(key) do
    Application.get_env(:eventasaurus, :clerk, [])
    |> Keyword.get(key)
  end
end
