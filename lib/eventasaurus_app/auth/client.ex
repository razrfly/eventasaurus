defmodule EventasaurusApp.Auth.Client do
  @moduledoc """
  Client for interacting with Supabase authentication API.
  """

  # Define auth endpoint for Supabase
  @auth_endpoint "/auth/v1"

  # Default HTTP request headers
  defp default_headers do
    [
      {"apikey", get_api_key()},
      {"Content-Type", "application/json"}
    ]
  end

  @doc """
  Sign up a new user with email and password.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  def sign_up(email, password, name \\ nil) do
    url = "#{get_url()}#{@auth_endpoint}/signup"

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
    url = "#{get_url()}#{@auth_endpoint}/token?grant_type=password"
    require Logger

    body = Jason.encode!(%{
      email: email,
      password: password
    })

    Logger.debug("Signing in user #{email}")

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        decoded = Jason.decode!(response_body)
        Logger.debug("Auth successful, response: #{inspect(decoded)}")
        {:ok, decoded}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("Auth failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Authentication failed"}}

      {:error, error} ->
        Logger.error("Auth request error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Sign out a user by invalidating their token.

  Returns :ok on success or {:error, reason} on failure.
  """
  def sign_out(token) do
    url = "#{get_url()}#{@auth_endpoint}/logout"

    headers = [
      {"Authorization", "Bearer #{token}"} | default_headers()
    ]

    case HTTPoison.post(url, "", headers) do
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
    url = "#{get_url()}#{@auth_endpoint}/recover"

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
    url = "#{get_url()}#{@auth_endpoint}/user"

    headers = [
      {"Authorization", "Bearer #{token}"} | default_headers()
    ]

    body = Jason.encode!(%{
      password: new_password
    })

    case HTTPoison.put(url, body, headers) do
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
    url = "#{get_url()}#{@auth_endpoint}/token?grant_type=refresh_token"

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
    url = "#{get_url()}#{@auth_endpoint}/user"

    headers = [
      {"Authorization", "Bearer #{token}"} | default_headers()
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Failed to get user data"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Get the Supabase configuration.
  """
  def get_config do
    Application.get_env(:eventasaurus, :supabase)
  end

  @doc """
  Get Supabase URL from configuration.
  """
  def get_url do
    get_config()[:url]
  end

  @doc """
  Get Supabase API key from configuration.
  """
  def get_api_key do
    get_config()[:api_key]
  end

  @doc """
  Get Supabase database URL from configuration.
  """
  def get_database_url do
    get_config()[:database_url]
  end
end
