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
  @impl true
  def sign_up(email, password, name \\ nil) do
    url = "#{get_auth_url()}/signup"

    body =
      Jason.encode!(%{
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
  @impl true
  def sign_in(email, password) do
    url = "#{get_auth_url()}/token?grant_type=password"
    Logger.debug("Authenticating user #{email} with URL: #{url}")

    body =
      Jason.encode!(%{
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

        {:error,
         %{status: 503, message: "Authentication service unavailable, DNS resolution failed"}}

      {:error, error} ->
        Logger.error("Authentication request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Sign out a user by invalidating their token.

  Returns :ok on success or {:error, reason} on failure.
  """
  @impl true
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
  @impl true
  def reset_password(email) do
    # Use the new server-side authentication flow
    alias EventasaurusApp.Auth.ServerAuth
    ServerAuth.request_password_reset(email)
  end

  @doc """
  Update a user's password using a reset token.

  Returns {:ok, %{}} on success or {:error, reason} on failure.
  """
  @impl true
  def update_password(token, new_password) do
    url = "#{get_auth_url()}/user"

    body =
      Jason.encode!(%{
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
  Update the current user's password using their access token.

  This is an alias for update_password/2 but with clearer naming for
  password recovery flows where the user is temporarily authenticated.

  Returns {:ok, %{}} on success or {:error, reason} on failure.
  """
  def update_user_password(access_token, new_password) do
    update_password(access_token, new_password)
  end

  @doc """
  Refresh an expired access token using a refresh token.

  Returns {:ok, tokens} on success or {:error, reason} on failure.
  """
  @impl true
  def refresh_token(refresh_token) do
    url = "#{get_auth_url()}/token?grant_type=refresh_token"
    Logger.debug("Refreshing token with URL: #{url}")

    body =
      Jason.encode!(%{
        refresh_token: refresh_token
      })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("Token refresh successful. Response keys: #{inspect(Map.keys(response))}")
        {:ok, response}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("Token refresh failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Token refresh failed"}}

      {:error, error} ->
        Logger.error("Token refresh request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Validate a JWT access token for integrity and expiration.

  This function validates the token by attempting to fetch user data
  with it, which will fail if the token is invalid or expired.

  Returns {:ok, token_data} on success or {:error, reason} on failure.
  """
  def validate_token(token) do
    url = "#{get_auth_url()}/user"

    case HTTPoison.get(url, auth_headers(token)) do
      {:ok, %{status_code: 200, body: response_body}} ->
        user_data = Jason.decode!(response_body)
        {:ok, user_data}

      {:ok, %{status_code: 401, body: _}} ->
        {:error, :expired}

      {:ok, %{status_code: 403, body: _}} ->
        {:error, :invalid}

      {:ok, %{status_code: _code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, error["message"] || "Token validation failed"}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Get the current user information using their access token.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  @impl true
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

    service_role_key =
      if runtime_env == "dev" do
        System.get_env("SUPABASE_SERVICE_ROLE_KEY_LOCAL") ||
          System.get_env("SUPABASE_SECRET_KEY")
      else
        System.get_env("SUPABASE_SECRET_KEY")
      end

    # Fail fast if no service role key is available - don't fall back to regular API key for security
    if is_nil(service_role_key) do
      raise "No service role key found. Please set SUPABASE_SERVICE_ROLE_KEY_LOCAL (dev) or SUPABASE_SECRET_KEY (prod) environment variables."
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
  @impl true
  def admin_create_user(email, password, user_metadata \\ %{}, email_confirm \\ true) do
    url = "#{get_auth_url()}/admin/users"

    body =
      Jason.encode!(%{
        email: email,
        password: password,
        user_metadata: user_metadata,
        # Auto-confirm email for dev environment
        email_confirm: email_confirm
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
  @impl true
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

    body =
      Jason.encode!(%{
        email: email,
        # Include name and other metadata
        data: user_metadata,
        options: %{
          # Auto-create user if doesn't exist
          shouldCreateUser: true,
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
  Sign in with Facebook OAuth using authorization code.
  This method exchanges the authorization code for access tokens.

  Returns {:ok, auth_data} on success or {:error, reason} on failure.
  """
  @impl true
  def sign_in_with_facebook_oauth(code) do
    url = "#{get_auth_url()}/token?grant_type=authorization_code"

    body =
      Jason.encode!(%{
        code: code,
        redirect_uri: get_facebook_redirect_uri()
      })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("Facebook OAuth authentication successful")
        {:ok, response}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("Facebook OAuth failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Facebook authentication failed"}}

      {:error, %HTTPoison.Error{reason: :nxdomain} = _error} ->
        Logger.error("DNS resolution failed for Supabase URL: #{get_url()}")
        {:error, %{status: 503, message: "Authentication service unavailable"}}

      {:error, error} ->
        Logger.error("Facebook OAuth request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Generate the Facebook OAuth login URL for redirecting users.
  """
  @impl true
  def get_facebook_oauth_url do
    base_url = "#{get_auth_url()}/authorize"
    redirect_uri = get_facebook_redirect_uri()

    params = [
      {"provider", "facebook"},
      {"redirect_to", redirect_uri}
    ]

    query_string = URI.encode_query(params)

    "#{base_url}?#{query_string}"
  end

  @doc """
  Link a Facebook account to an existing authenticated user.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  @impl true
  def link_facebook_account(access_token, facebook_oauth_code) do
    url = "#{get_auth_url()}/user/identities"

    body =
      Jason.encode!(%{
        provider: "facebook",
        code: facebook_oauth_code,
        redirect_uri: get_facebook_redirect_uri()
      })

    case HTTPoison.post(url, body, auth_headers(access_token)) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("Facebook account linked successfully")
        {:ok, response}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("Facebook account linking failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Failed to link Facebook account"}}

      {:error, error} ->
        Logger.error("Facebook account linking request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Unlink a Facebook account from an authenticated user using Supabase Admin API.

  Returns {:ok, %{}} on success or {:error, reason} on failure.
  """
  def unlink_facebook_account(access_token, identity_id) do
    # First, get the user ID from the access token
    case decode_jwt_payload(access_token) do
      {:ok, payload} ->
        user_id = Map.get(payload, "sub")

        if user_id do
          # Use admin API to unlink the identity
          url = "#{get_auth_url()}/admin/users/#{user_id}/identities/#{identity_id}"

          case HTTPoison.delete(url, admin_headers(), timeout: 30000, recv_timeout: 30000) do
            {:ok, %{status_code: 200, body: response_body}} ->
              response = Jason.decode!(response_body)
              Logger.debug("Facebook account unlinked successfully")
              {:ok, response}

            {:ok, %{status_code: 404, body: response_body}} ->
              # Admin API failed, try user API fallback
              case Jason.decode(response_body) do
                {:ok, error_json} ->
                  message = error_json["message"] || "Identity not found"

                  cond do
                    String.contains?(message, "manual_linking_disabled") ->
                      try_user_api_unlink(access_token, identity_id)

                    String.contains?(message, "minimum_identity_count") ->
                      {:error, %{status: 422, message: "minimum_identity_count"}}

                    true ->
                      try_user_api_unlink(access_token, identity_id)
                  end

                {:error, _} ->
                  # Not JSON, probably HTML 404 page - try user API instead
                  try_user_api_unlink(access_token, identity_id)
              end

            {:ok, %{status_code: 422, body: response_body}} ->
              error = Jason.decode!(response_body)

              Logger.error(
                "Facebook account unlinking failed - validation error: #{inspect(error)}"
              )

              {:error,
               %{
                 status: 422,
                 message: error["message"] || "Cannot unlink last authentication method"
               }}

            {:ok, %{status_code: code, body: response_body}} ->
              error = Jason.decode!(response_body)

              Logger.error(
                "Facebook account unlinking failed with status #{code}: #{inspect(error)}"
              )

              {:error,
               %{status: code, message: error["message"] || "Failed to unlink Facebook account"}}

            {:error, error} ->
              Logger.error("Facebook account unlinking request failed: #{inspect(error)}")
              {:error, error}
          end
        else
          Logger.error("Could not extract user ID from access token")
          {:error, %{status: 401, message: "Invalid access token"}}
        end

      {:error, reason} ->
        Logger.error("Failed to decode access token for unlinking: #{inspect(reason)}")
        {:error, %{status: 401, message: "Invalid access token"}}
    end
  end

  defp get_facebook_redirect_uri do
    site_url = get_config()[:site_url] || "http://localhost:4000"
    "#{site_url}/auth/callback"
  end

  @doc """
  Sign in with Google OAuth authorization code.

  Returns {:ok, auth_data} on success or {:error, reason} on failure.
  """
  @impl true
  def sign_in_with_google_oauth(code) do
    url = "#{get_auth_url()}/token?grant_type=authorization_code"

    body =
      Jason.encode!(%{
        code: code,
        redirect_uri: get_google_redirect_uri()
      })

    case HTTPoison.post(url, body, default_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("Google OAuth authentication successful")
        {:ok, response}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("Google OAuth failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Google authentication failed"}}

      {:error, %HTTPoison.Error{reason: :nxdomain} = _error} ->
        Logger.error("DNS resolution failed for Supabase URL: #{get_url()}")
        {:error, %{status: 503, message: "Authentication service unavailable"}}

      {:error, error} ->
        Logger.error("Google OAuth request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Generate the Google OAuth login URL for redirecting users.
  """
  @impl true
  def get_google_oauth_url do
    base_url = "#{get_auth_url()}/authorize"
    redirect_uri = get_google_redirect_uri()

    params = [
      {"provider", "google"},
      {"redirect_to", redirect_uri}
    ]

    query_string = URI.encode_query(params)

    "#{base_url}?#{query_string}"
  end

  @doc """
  Link a Google account to an existing authenticated user.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  @impl true
  def link_google_account(access_token, google_oauth_code) do
    url = "#{get_auth_url()}/user/identities"

    body =
      Jason.encode!(%{
        provider: "google",
        code: google_oauth_code,
        redirect_uri: get_google_redirect_uri()
      })

    case HTTPoison.post(url, body, auth_headers(access_token)) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("Google account linked successfully")
        {:ok, response}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        Logger.error("Google account linking failed with status #{code}: #{inspect(error)}")
        {:error, %{status: code, message: error["message"] || "Failed to link Google account"}}

      {:error, error} ->
        Logger.error("Google account linking request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp get_google_redirect_uri do
    site_url = get_config()[:site_url] || "http://localhost:4000"
    "#{site_url}/auth/callback"
  end

  @doc """
  Get a user by email using admin API.

  Returns {:ok, user_data} on success or {:error, reason} on failure.
  """
  @impl true
  def admin_get_user_by_email(email) do
    # Fetch all users and manually filter by email due to local Supabase bug
    # where email parameter returns admin user for any query
    # We need to fetch all pages since we might have more than 100 users
    fetch_user_from_all_pages(email, 1)
  end

  defp fetch_user_from_all_pages(email, page) do
    url = "#{get_auth_url()}/admin/users?page=#{page}&per_page=100"

    Logger.debug("admin_get_user_by_email: Searching for email #{email} on page #{page}")
    Logger.debug("admin_get_user_by_email: Using URL #{url}")

    case HTTPoison.get(url, admin_headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("admin_get_user_by_email: Full response: #{inspect(response)}")

        case response["users"] do
          users when is_list(users) ->
            Logger.debug(
              "admin_get_user_by_email: Got #{length(users)} users on page #{page}, manually filtering"
            )

            # Manually filter by case-insensitive email match
            matching_user =
              Enum.find(users, fn user ->
                Logger.debug("admin_get_user_by_email: Comparing #{user["email"]} with #{email}")
                # Case-insensitive comparison
                String.downcase(user["email"] || "") == String.downcase(email || "")
              end)

            cond do
              # Found the user!
              matching_user ->
                Logger.debug(
                  "admin_get_user_by_email: Found matching user: #{matching_user["email"]} on page #{page}"
                )

                {:ok, matching_user}

              # No user found and we got a full page - check next page
              length(users) == 100 ->
                Logger.debug(
                  "admin_get_user_by_email: No match on page #{page}, checking page #{page + 1}"
                )

                fetch_user_from_all_pages(email, page + 1)

              # No user found and this was a partial page - we've checked all users
              true ->
                Logger.debug(
                  "admin_get_user_by_email: No matching user found after checking all #{page} page(s)"
                )

                {:ok, nil}
            end

          _ ->
            Logger.debug("admin_get_user_by_email: Unexpected response format")
            # Unexpected response format
            {:ok, nil}
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
  Get real user identities from Supabase API (not just JWT parsing).

  Returns {:ok, identities} on success or {:error, reason} on failure.
  """
  def get_real_user_identities(access_token) do
    url = "#{get_auth_url()}/user"

    case HTTPoison.get(url, auth_headers(access_token)) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("Real user identities retrieved successfully")
        # Extract identities from user response and format like the expected structure
        identities = Map.get(response, "identities", [])
        {:ok, %{"identities" => identities}}

      {:ok, %{status_code: code, body: response_body}} ->
        Logger.error("Failed to get real user identities with status #{code}: #{response_body}")

        # Try to decode JSON response, but handle cases where it's HTML/plain text
        error_message =
          case Jason.decode(response_body) do
            {:ok, error_json} ->
              error_json["message"] || "Failed to get user identities"

            {:error, _} ->
              # Not JSON, probably HTML 404 page
              "API endpoint not available (status #{code})"
          end

        {:error, %{status: code, message: error_message}}

      {:error, error} ->
        Logger.error("Real user identities request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get user providers from JWT token app_metadata.

  Returns {:ok, providers} on success or {:error, reason} on failure.
  """
  def get_user_identities(access_token) do
    try do
      # Decode JWT token to extract app_metadata
      case decode_jwt_payload(access_token) do
        {:ok, payload} ->
          app_metadata = Map.get(payload, "app_metadata", %{})
          providers = Map.get(app_metadata, "providers", [])

          Logger.debug("User providers extracted from JWT: #{inspect(providers)}")

          # Transform providers into identity-like format for compatibility
          identities =
            Enum.map(providers, fn provider ->
              %{
                "provider" => provider,
                "provider_type" => provider,
                "id" => "#{provider}_identity"
              }
            end)

          {:ok, %{"identities" => identities}}

        {:error, reason} ->
          Logger.error("Failed to decode JWT for user identities: #{inspect(reason)}")
          {:error, %{status: 401, message: "Invalid authentication token"}}
      end
    rescue
      error ->
        Logger.error("Error parsing JWT for user identities: #{inspect(error)}")
        {:error, %{status: 500, message: "Failed to parse authentication token"}}
    end
  end

  # Alternative method using user API instead of admin API
  defp try_user_api_unlink(access_token, identity_id) do
    # Try the most likely working endpoint first
    urls_to_try = [
      "#{get_auth_url()}/user/identities/#{identity_id}",
      "#{get_auth_url()}/user/identities",
      "#{get_auth_url()}/user"
    ]

    try_user_api_endpoints(access_token, urls_to_try)
  end

  defp try_user_api_endpoints(access_token, [url | remaining_urls]) do
    case HTTPoison.delete(url, auth_headers(access_token), timeout: 30000, recv_timeout: 30000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        Logger.debug("User API unlinking succeeded")
        {:ok, response}

      {:ok, %{status_code: _code, body: _response_body}} when remaining_urls != [] ->
        # Try next endpoint
        try_user_api_endpoints(access_token, remaining_urls)

      {:ok, %{status_code: code, body: response_body}} ->
        error_message =
          case Jason.decode(response_body) do
            {:ok, error_json} -> error_json["message"] || "User API unlinking failed"
            {:error, _} -> "User API unlinking failed (status #{code})"
          end

        {:error, %{status: code, message: error_message}}

      {:error, _error} when remaining_urls != [] ->
        # Try next endpoint
        try_user_api_endpoints(access_token, remaining_urls)

      {:error, error} ->
        {:error, error}
    end
  end

  defp try_user_api_endpoints(_access_token, []) do
    {:error, %{status: 404, message: "No working user API endpoint found"}}
  end

  # Helper function to decode JWT payload
  defp decode_jwt_payload(jwt_token) do
    try do
      # Split JWT token into parts
      case String.split(jwt_token, ".") do
        [_header, payload, _signature] ->
          # Decode base64 payload
          case Base.url_decode64(payload, padding: false) do
            {:ok, decoded_payload} ->
              case Jason.decode(decoded_payload) do
                {:ok, json_payload} ->
                  {:ok, json_payload}

                {:error, reason} ->
                  {:error, {:json_decode_error, reason}}
              end

            :error ->
              {:error, :base64_decode_error}
          end

        _ ->
          {:error, :invalid_jwt_format}
      end
    rescue
      error ->
        {:error, {:decode_error, error}}
    end
  end
end
