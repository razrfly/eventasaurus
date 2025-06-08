defmodule EventasaurusWeb.Auth.AuthController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Auth

  # Privacy-safe email logging for GDPR/CCPA compliance
  defp mask_email(email) do
    case String.split(email, "@", parts: 2) do
      [local, domain] ->
        masked_local = String.slice(local, 0, 2) <> "***"
        "#{masked_local}@#{domain}"
      _ ->
        "***@invalid"
    end
  end

  @doc """
  Show the login form.
  """
  def login(conn, _params) do
    render(conn, :login)
  end

  @doc """
  Process the login form submission.
  """
  def authenticate(conn, %{"user" => %{"email" => email, "password" => password}}) do
    require Logger
    Logger.debug("Attempting login for email: #{email}")

    case Auth.authenticate(email, password) do
      {:ok, auth_data} ->
        Logger.debug("Authentication successful, auth_data: #{inspect(auth_data)}")

        case Auth.store_session(conn, auth_data) do
          {:ok, conn} ->
            # Fetch current user for the session
            user = Auth.get_current_user(conn)
            Logger.debug("User data fetched: #{inspect(user)}")

            conn
            |> assign(:auth_user, user)
            |> put_flash(:info, "You have been logged in successfully.")
            |> redirect(to: ~p"/dashboard")

          {:error, reason} ->
            Logger.error("Failed to store session: #{inspect(reason)}")
            conn
            |> put_flash(:error, "Error storing session data. Please contact support.")
            |> render(:login)
        end

      # Special case for email already exists but with different Supabase ID
      {:error, %Ecto.Changeset{errors: [email: {"has already been taken", _}]}} ->
        Logger.error("Authentication failed: Email already exists with a different ID")
        # Try to get the user by email and log them in directly
        case EventasaurusApp.Accounts.get_user_by_email(email) do
          nil ->
            conn
            |> put_flash(:error, "Authentication failed. Please try again.")
            |> render(:login)

          user ->
            Logger.info("Found existing user with email #{mask_email(email)}, logging in directly")
            conn
            |> assign(:auth_user, user)
            |> put_flash(:info, "You have been logged in successfully.")
            |> redirect(to: ~p"/dashboard")
        end

      {:error, reason} ->
        Logger.error("Authentication failed: #{inspect(reason)}")
        error_message = case reason do
          %{message: message} when is_binary(message) -> message
          %{status: 401} -> "Invalid email or password. Please try again."
          %{status: 404} -> "User not found. Please check your email or create an account."
          _ -> "An error occurred during login. Please try again."
        end

        conn
        |> put_flash(:error, error_message)
        |> render(:login)
    end
  end

  # Fallback for flat parameters (backward compatibility)
  def authenticate(conn, %{"email" => email, "password" => password}) do
    authenticate(conn, %{"user" => %{"email" => email, "password" => password}})
  end

  @doc """
  Show the registration form.
  """
  def register(conn, _params) do
    render(conn, :register)
  end

  @doc """
  Process the registration form submission.
  """
    def create_user(conn, %{"user" => %{"name" => name, "email" => email, "password" => password}}) do
    require Logger
    Logger.info("Registration attempt for email: #{mask_email(email)}")

    case Auth.sign_up_with_email_and_password(email, password, %{name: name}) do
      {:ok, %{"access_token" => access_token, "refresh_token" => refresh_token}} ->
        Logger.info("Registration successful with tokens")
        conn
        |> put_session(:access_token, access_token)
        |> put_session(:refresh_token, refresh_token)
        |> put_flash(:info, "Account created successfully! Please check your email to verify your account.")
        |> redirect(to: ~p"/dashboard")

      {:ok, %{user: _user, access_token: access_token}} ->
        Logger.info("Registration successful with access token")
        conn
        |> put_session(:access_token, access_token)
        |> put_flash(:info, "Account created successfully!")
        |> redirect(to: ~p"/dashboard")

      {:ok, %{user: _user, confirmation_required: true}} ->
        Logger.info("Registration successful, confirmation required")
        conn
        |> put_flash(:info, "Account created successfully! Please check your email to verify your account.")
        |> redirect(to: ~p"/login")

      {:error, %{"message" => message}} ->
        Logger.error("Registration failed with message: #{message}")
        conn
        |> put_flash(:error, message)
        |> render(:register)

      {:error, reason} ->
        Logger.error("Registration failed with reason: #{inspect(reason)}")
        conn
        |> put_flash(:error, "Unable to create account")
        |> render(:register)
    end
  end

  @doc """
  Logs out the current user.
  """
  def logout(conn, _params) do
    # Get current user before clearing session
    current_user = Auth.get_current_user(conn)

    case current_user do
      %{"id" => user_id} ->
        # Use enhanced logout with broadcast
        {:ok, conn} = Auth.logout_with_broadcast(conn, user_id)
        conn
        |> put_flash(:info, "You have been logged out")
        |> redirect(to: ~p"/")
      _ ->
        # No user found, just clear session
        conn
        |> Auth.clear_session()
        |> put_flash(:info, "You have been logged out")
        |> redirect(to: ~p"/")
    end
  end

  @doc """
  Show the forgot password form.
  """
  def forgot_password(conn, _params) do
    render(conn, :forgot_password)
  end

  @doc """
  Handle password reset requests.
  """
  def request_password_reset(conn, %{"email" => email}) do
    case Auth.request_password_reset(email) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "If your email exists in our system, you will receive password reset instructions shortly.")
        |> redirect(to: ~p"/login")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "There was an error processing your request. Please try again.")
        |> redirect(to: ~p"/forgot-password")
    end
  end

  @doc """
  Show the reset password form.
  """
  def reset_password(conn, %{"token" => token}) do
    render(conn, :reset_password, token: token)
  end

  @doc """
  Process the reset password form submission.
  """
  def update_password(conn, %{"token" => token, "password" => password}) do
    case Auth.update_user_password(token, password) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Password updated successfully!")
        |> redirect(to: ~p"/auth/login")

      {:error, %{"message" => message}} ->
        conn
        |> put_flash(:error, message)
        |> render(:reset_password, token: token)

      {:error, _} ->
        conn
        |> put_flash(:error, "Unable to update password")
        |> render(:reset_password, token: token)
    end
  end

  @doc """
  Handle authentication errors from the frontend JavaScript.
  """
  def auth_error(conn, %{"provider" => provider, "reason" => reason} = _params) do
    require Logger
    Logger.warning("Social auth error for #{provider}: #{reason}")

    # Store error information in flash for display
    conn
    |> put_flash(:auth_error, reason)
    |> put_flash(:last_attempted_provider, provider)
    |> json(%{status: "error_logged"})
  end

  @doc """
  Handle retry authentication requests from the frontend.
  """
  def retry_auth(conn, %{"provider" => provider}) do
    require Logger
    Logger.info("Retrying #{provider} authentication")

    # Clear previous error state
    conn
    |> clear_flash()
    |> json(%{status: "retry_initiated", provider: provider})
  end

  @doc """
  Handle callback routes for authentication flows, such as OAuth or email confirmations.
  """
  def callback(conn, params) do
    require Logger
    Logger.info("Auth callback received: #{inspect(params)}")

    case params do
      # OAuth callback with authorization code (new OAuth flow)
      %{"code" => code} when is_binary(code) ->
        Logger.info("OAuth callback with authorization code")
        handle_oauth_callback(conn, code, params)

      # Legacy: Direct token callback (existing email auth flows)
      %{"access_token" => access_token, "refresh_token" => refresh_token} ->
        Logger.info("Callback with tokens - storing session")
        conn
        |> put_session(:access_token, access_token)
        |> put_session(:refresh_token, refresh_token)
        |> put_flash(:info, "Successfully signed in!")
        |> redirect(to: ~p"/dashboard")

      %{"access_token" => access_token} ->
        Logger.info("Callback with access token only - storing session")
        conn
        |> put_session(:access_token, access_token)
        |> put_flash(:info, "Successfully signed in!")
        |> redirect(to: ~p"/dashboard")

      # Error responses
      %{"error" => error, "error_description" => description} ->
        Logger.error("Callback error: #{error} - #{description}")
        error_message = format_oauth_error_message(error, description)
        redirect_path = determine_error_redirect_path(params)

        conn
        |> put_flash(:auth_error, error_message)
        |> put_flash(:last_attempted_provider, get_provider_from_params(params))
        |> redirect(to: redirect_path)

      %{"error" => error} ->
        Logger.error("Callback error: #{error}")
        error_message = format_oauth_error_message(error, nil)
        redirect_path = determine_error_redirect_path(params)

        conn
        |> put_flash(:auth_error, error_message)
        |> put_flash(:last_attempted_provider, get_provider_from_params(params))
        |> redirect(to: redirect_path)

      _other ->
        Logger.warning("Callback with no recognized parameters, redirecting to dashboard")
        # For email confirmations without tokens, redirect to login to let user sign in
        conn
        |> put_flash(:info, "Email confirmed! Please sign in.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  # Handle OAuth authorization code exchange
  defp handle_oauth_callback(conn, code, params) do
    require Logger

    case Auth.exchange_oauth_code(code) do
      {:ok, %{user: user, access_token: access_token} = auth_data} ->
        Logger.info("OAuth authentication successful for user: #{user.email}")

        # Store tokens in session
        conn = conn
               |> put_session(:access_token, access_token)
               |> assign(:auth_user, user)

        # Store refresh token if present
        conn = if Map.has_key?(auth_data, :refresh_token) do
          put_session(conn, :refresh_token, auth_data.refresh_token)
        else
          conn
        end

        # Determine redirect URL based on user type and params
        redirect_to = determine_user_redirect_path(user, params)

        success_message = if user_is_new?(user) do
          "Welcome to Eventasaurus! Your account has been created successfully."
        else
          "Successfully signed in with social authentication!"
        end

        conn
        |> put_flash(:info, success_message)
        |> redirect(to: redirect_to)

      {:error, reason} ->
        Logger.error("OAuth authentication failed: #{inspect(reason)}")

        error_message = case reason do
          %{message: message} when is_binary(message) -> "Authentication failed: #{message}"
          _ -> "Social authentication failed. Please try again."
        end

        conn
        |> put_flash(:error, error_message)
        |> redirect(to: ~p"/auth/login")
    end
  end

  # Helper functions for enhanced error handling

  defp format_oauth_error_message(error, description) do
    case error do
      "access_denied" -> "You declined to authorize the application. Please try again if this was unintentional."
      "invalid_request" -> "There was an issue with the authentication request. Please try again."
      "temporarily_unavailable" -> "The authentication service is temporarily unavailable. Please try again later."
      "server_error" -> "The authentication server encountered an error. Please try again."
      _ -> description || "Social authentication failed. Please try again."
    end
  end

  defp determine_error_redirect_path(params) do
    # Check if this was a registration flow vs login flow
    case Map.get(params, "redirect_to") do
      redirect_url when is_binary(redirect_url) ->
        if String.contains?(redirect_url, "register") do
          ~p"/auth/register"
        else
          ~p"/auth/login"
        end
      _ ->
        ~p"/auth/login"
    end
  end

  defp get_provider_from_params(params) do
    # Try to extract provider from the state parameter or error details
    case Map.get(params, "state") do
      state when is_binary(state) ->
        case Base.decode64(state) do
          {:ok, decoded} ->
            case Jason.decode(decoded) do
              {:ok, %{"provider" => provider}} -> provider
              _ -> "social"
            end
          _ -> "social"
        end
      _ -> "social"
    end
  end

  defp determine_user_redirect_path(user, params) do
    # Check if this is a new user (just created) vs returning user
    case Map.get(params, "redirect_to") do
      redirect_url when is_binary(redirect_url) -> redirect_url
      _ ->
        # For new users, redirect to onboarding; for existing users, to dashboard
        if user_is_new?(user) do
          "/onboarding"
        else
          "/dashboard"
        end
    end
  end

  defp user_is_new?(user) do
    # Check if user was created recently (within last 5 minutes) as a heuristic for new registration
    case user.inserted_at do
      %DateTime{} = inserted_at ->
        DateTime.diff(DateTime.utc_now(), inserted_at, :second) < 300
      _ -> false
    end
  end
end
