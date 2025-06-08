defmodule EventasaurusApp.Auth.Client do
  @moduledoc """
  Client for interacting with Supabase API directly using HTTPoison.
  This replaces the dependency on the supabase/gotrue/postgrestex packages.
  """

  @behaviour EventasaurusApp.Auth.ClientBehaviour

  require Logger

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
    auth_url = "#{get_url()}/auth/v1"
    Logger.debug("Using Supabase auth URL: #{auth_url}")
    auth_url
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
    Logger.debug("Authenticating user #{email} with URL: #{url}")

    body = Jason.encode!(%{
      email: email,
      password: password
    })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("Authentication successful")
        {:ok, response}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("Authentication failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Authentication failed"}}

      {:error, %HTTPoison.Error{reason: :nxdomain} = _error} ->
        Logger.error("DNS resolution failed for Supabase URL: #{get_url()}")
        {:error, %{status: 503, message: "Authentication service unavailable, DNS resolution failed"}}

      {:error, error} ->
        Logger.error("Authentication request failed: #{inspect(error)}")
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
  Alias for refresh_token/1 to match session management naming convention.

  Returns {:ok, tokens} on success or {:error, reason} on failure.
  """
  def refresh_session(refresh_token), do: refresh_token(refresh_token)

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

  # Admin API functions for programmatic user creation

  defp admin_headers do
    # Use runtime environment detection instead of compile-time Mix.env()
    runtime_env = System.get_env("MIX_ENV") || "dev"

    service_role_key = if runtime_env == "dev" do
      System.get_env("SUPABASE_SERVICE_ROLE_KEY_LOCAL") ||
      System.get_env("SUPABASE_API_SECRET") ||
      System.get_env("SUPABASE_SERVICE_ROLE_KEY")
    else
      System.get_env("SUPABASE_API_SECRET") ||
      System.get_env("SUPABASE_SERVICE_ROLE_KEY")
    end

    # Fail fast if no service role key is available - don't fall back to regular API key for security
    if is_nil(service_role_key) do
      raise "No service role key found. Please set SUPABASE_SERVICE_ROLE_KEY_LOCAL (dev) or SUPABASE_API_SECRET/SUPABASE_SERVICE_ROLE_KEY (prod) environment variables."
    end

    [
      {"apikey", service_role_key},
      {"Authorization", "Bearer #{service_role_key}"},
      {"Content-Type", "application/json"}
    ]
  end

  @doc """
  Create a user using admin API with email confirmation required.

  This requires a service role key and is used for programmatic user creation
  where we want to create accounts that require email confirmation for access.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  def admin_create_user(email, password, user_metadata \\ %{}) do
    url = "#{get_auth_url()}/admin/users"

    body = Jason.encode!(%{
      email: email,
      password: password,
      user_metadata: user_metadata,
      email_confirm: false  # This requires email confirmation for account access
    })

    case HTTPoison.post(url, body, admin_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "User creation failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Update a user using admin API.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  def admin_update_user(user_id, attrs) do
    url = "#{get_auth_url()}/admin/users/#{user_id}"

    body = Jason.encode!(attrs)

    case HTTPoison.put(url, body, admin_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "User update failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Delete a user using admin API.

  Returns {:ok, %{}} on success or {:error, reason} on failure.
  """
  def admin_delete_user(user_id) do
    url = "#{get_auth_url()}/admin/users/#{user_id}"

    case HTTPoison.delete(url, admin_headers()) do
      {:ok, %{status_code: 200}} ->
        {:ok, %{}}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "User deletion failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Sign in with OTP (magic link) - creates user if doesn't exist and sends confirmation email.

  This uses Supabase's passwordless authentication which automatically:
  - Creates new users if they don't exist
  - Sends confirmation emails automatically
  - Requires email confirmation for account access

  Returns {:ok, response} on success or {:error, reason} on failure.
  """
  def sign_in_with_otp(email, user_metadata \\ %{}) do
    url = "#{get_auth_url()}/otp"

    body = Jason.encode!(%{
      email: email,
      data: user_metadata,  # Include name and other metadata
      options: %{
        shouldCreateUser: true,  # Auto-create user if doesn't exist
        emailRedirectTo: "#{get_config()[:site_url]}/auth/callback"
      }
    })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}
      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "OTP request failed"}}
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Get a user by email using admin API.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  def admin_get_user_by_email(email) do
    # Fetch all users and manually filter by email due to local Supabase bug
    # where email parameter returns admin user for any query
    url = "#{get_auth_url()}/admin/users"

    Logger.debug("admin_get_user_by_email: Searching for email #{email}")
    Logger.debug("admin_get_user_by_email: Using URL #{url}")

    case HTTPoison.get(url, admin_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("admin_get_user_by_email: Full response: #{inspect(response)}")

        case response["users"] do
          users when is_list(users) ->
            Logger.debug("admin_get_user_by_email: Got #{length(users)} users, manually filtering")
            # Manually filter by exact email match
            matching_user = Enum.find(users, fn user ->
              Logger.debug("admin_get_user_by_email: Comparing #{user["email"]} with #{email}")
              user["email"] == email
            end)

            if matching_user do
              Logger.debug("admin_get_user_by_email: Found matching user: #{matching_user["email"]}")
            else
              Logger.debug("admin_get_user_by_email: No matching user found after manual filtering")
            end

            {:ok, matching_user}
          _ ->
            Logger.debug("admin_get_user_by_email: Unexpected response format")
            {:ok, nil}            # Unexpected response format
        end

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("admin_get_user_by_email: HTTP error #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Failed to get user"}}

      {:error, error} ->
        Logger.error("admin_get_user_by_email: Request error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Exchange OAuth authorization code for access and refresh tokens.

  This function handles the server-side OAuth callback by exchanging the
  authorization code received from OAuth providers (Facebook, Twitter, etc.)
  for a session with access and refresh tokens.

  Returns {:ok, session_data} on success or {:error, reason} on failure.
  """
  def exchange_code_for_session(code) do
    url = "#{get_auth_url()}/token?grant_type=authorization_code"

    body = Jason.encode!(%{
      auth_code: code
    })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        session_data = Jason.decode!(response_body)
        Logger.info("OAuth code exchange successful")
        {:ok, session_data}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("OAuth code exchange failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "OAuth code exchange failed"}}

      {:error, error} ->
        Logger.error("OAuth code exchange request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get OAuth URL for a specific provider.

  Generates the OAuth authorization URL for redirecting users to social providers.
  The user will be redirected back to the callback URL after authentication.

  ## Parameters
    - provider: "facebook" | "twitter" | other supported provider
    - redirect_to: The URL to redirect to after successful authentication
    - scopes: Optional scopes to request from the provider

  Returns the OAuth authorization URL.
  """
  def get_oauth_url(provider, redirect_to \\ nil, scopes \\ nil) do
    base_url = "#{get_auth_url()}/authorize"
    redirect_url = redirect_to || "#{get_config()[:site_url]}/auth/callback"

    query_params = [
      {"provider", provider},
      {"redirect_to", redirect_url}
    ]

    query_params = if scopes, do: [{"scopes", scopes} | query_params], else: query_params

    query_string = URI.encode_query(query_params)
    "#{base_url}?#{query_string}"
  end
end
