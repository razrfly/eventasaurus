defmodule EventasaurusApp.Auth.Client do
  @moduledoc """
  Client for interacting with Supabase API directly using HTTPoison.
  This replaces the dependency on the supabase/gotrue/postgrestex packages.
  """

  # Get Supabase configuration from application config
  def get_config do
    Application.get_env(:eventasaurus, :supabase)
  end

  def get_url do
    get_config()[:url]
  end

  def get_api_key do
    get_config()[:api_key]
  end

  def get_database_url do
    get_config()[:database_url]
  end

  def get_auth_url do
    "#{get_url()}/auth/v1"
  end

  # Default HTTP request headers
  defp default_headers do
    [
      {"apikey", get_api_key()},
      {"Content-Type", "application/json"}
    ]
  end

  defp auth_headers(token) do
    [{"Authorization", "Bearer #{token}"} | default_headers()]
  end

  @doc """
  Sign up a new user with email and password.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  def sign_up(email, password, name \\ nil) do
    url = "#{get_auth_url()}/signup"

    body = Jason.encode!(%{
      email: email,
      password: password,
      data: %{name: name}
    })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Signup failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Sign in a user with email and password.

  Returns {:ok, auth_data} with tokens on success or {:error, reason} on failure.
  """
  def sign_in(email, password) do
    url = "#{get_auth_url()}/token?grant_type=password"

    body = Jason.encode!(%{
      email: email,
      password: password
    })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Authentication failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Sign out a user by invalidating their token.

  Returns :ok on success or {:error, reason} on failure.
  """
  def sign_out(token) do
    url = "#{get_auth_url()}/logout"

    case HTTPoison.post(url, "", auth_headers(token)) do
      {:ok, %{status_code: status}} when status in [200, 204] ->
        :ok

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Logout failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Reset a user's password by sending a reset email.

  Returns {:ok, %{email: email}} on success or {:error, reason} on failure.
  """
  def reset_password(email) do
    url = "#{get_auth_url()}/recover"

    body = Jason.encode!(%{
      email: email
    })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: status}} when status in [200, 204] ->
        {:ok, %{email: email}}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Password reset request failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Update a user's password using a reset token.

  Returns {:ok, %{}} on success or {:error, reason} on failure.
  """
  def update_password(token, new_password) do
    url = "#{get_auth_url()}/user"

    body = Jason.encode!(%{
      password: new_password
    })

    case HTTPoison.put(url, body, auth_headers(token)) do
      {:ok, %{status_code: 200}} ->
        {:ok, %{}}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Password update failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Refresh an expired access token using a refresh token.

  Returns {:ok, tokens} on success or {:error, reason} on failure.
  """
  def refresh_token(refresh_token) do
    url = "#{get_auth_url()}/token?grant_type=refresh_token"

    body = Jason.encode!(%{
      refresh_token: refresh_token
    })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Token refresh failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Get the current user information using their access token.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  def get_user(token) do
    url = "#{get_auth_url()}/user"

    case HTTPoison.get(url, auth_headers(token)) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Failed to get user data"}}

      {:error, error} ->
        {:error, error}
    end
  end
end
