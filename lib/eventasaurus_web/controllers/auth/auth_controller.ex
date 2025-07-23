defmodule EventasaurusWeb.Auth.AuthController do
  use EventasaurusWeb, :controller
  require Logger

  alias EventasaurusApp.Auth
  alias EventasaurusApp.Services.Turnstile

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
  def login(conn, params) do
    require Logger
    Logger.debug("Login action - params: #{inspect(params)}")
    
    # Store return URL if provided in query params (voluntary login)
    conn = case params["return_to"] do
      nil -> 
        Logger.debug("No return_to parameter provided")
        conn
      return_to when is_binary(return_to) ->
        Logger.debug("return_to parameter: #{return_to}")
        # Validate the URL before storing
        if valid_internal_url?(return_to) do
          Logger.debug("Valid return URL, storing in session: #{return_to}")
          put_session(conn, :user_return_to, return_to)
        else
          Logger.warning("Invalid return URL rejected: #{return_to}")
          conn
        end
      _ -> conn
    end
    
    render(conn, :login)
  end

  @doc """
  Process the login form submission.
  """
  def authenticate(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    require Logger
    Logger.debug("Attempting login for email: #{email}")

    # Extract remember_me preference, defaulting to true for better UX
    remember_me = case Map.get(user_params, "remember_me") do
      "false" -> false
      _ -> true  # Default to true - most users prefer to stay logged in
    end

    Logger.debug("Remember me preference: #{remember_me}")

    case Auth.authenticate(email, password) do
      {:ok, auth_data} ->
        Logger.debug("Authentication successful, auth_data: #{inspect(auth_data)}")

        case Auth.store_session(conn, auth_data, remember_me) do
          {:ok, conn} ->
            # Fetch current user for the session
            user = Auth.get_current_user(conn)
            Logger.debug("User data fetched: #{inspect(user)}")

            # Check for stored return URL using the standard session key
            return_to = get_session(conn, :user_return_to)
            Logger.debug("Retrieved user_return_to from session: #{inspect(return_to)}")
            
            conn
            |> assign(:auth_user, user)
            |> put_flash(:info, "You have been logged in successfully.")
            |> delete_session(:user_return_to)
            |> redirect(to: return_to || ~p"/dashboard")

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
            
            # Check for stored return URL using the standard session key
            return_to = get_session(conn, :user_return_to)
            Logger.debug("Retrieved user_return_to from session: #{inspect(return_to)}")
            
            conn
            |> assign(:auth_user, user)
            |> put_flash(:info, "You have been logged in successfully.")
            |> delete_session(:user_return_to)
            |> redirect(to: return_to || ~p"/dashboard")
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
    authenticate(conn, %{"user" => %{"email" => email, "password" => password, "remember_me" => "true"}})
  end

  @doc """
  Show the registration form.
  """
  def register(conn, params) do
    # Store return URL if provided in query params
    conn = case params["return_to"] do
      nil -> conn
      return_to when is_binary(return_to) ->
        if valid_internal_url?(return_to) do
          put_session(conn, :user_return_to, return_to)
        else
          conn
        end
      _ -> conn
    end
    
    render(conn, :register)
  end

  @doc """
  Process the registration form submission.
  """
    def create_user(conn, %{"user" => %{"name" => name, "email" => email, "password" => password}} = params) do
    require Logger
    Logger.info("Registration attempt for email: #{mask_email(email)}")

    # Verify Turnstile token if enabled
    with :ok <- verify_turnstile(params) do
      case Auth.sign_up_with_email_and_password(email, password, %{name: name}) do
      {:ok, %{"access_token" => access_token, "refresh_token" => refresh_token}} ->
        Logger.info("Registration successful with tokens")
        
        # Check for stored return URL
        return_to = get_session(conn, :user_return_to)
        
        conn
        |> put_session(:access_token, access_token)
        |> put_session(:refresh_token, refresh_token)
        |> put_flash(:info, "Account created successfully! Please check your email to verify your account.")
        |> delete_session(:user_return_to)
        |> redirect(to: return_to || ~p"/dashboard")

      {:ok, %{user: _user, access_token: access_token}} ->
        Logger.info("Registration successful with access token")
        
        # Check for stored return URL
        return_to = get_session(conn, :user_return_to)
        
        conn
        |> put_session(:access_token, access_token)
        |> put_flash(:info, "Account created successfully!")
        |> delete_session(:user_return_to)
        |> redirect(to: return_to || ~p"/dashboard")

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
    else
      {:error, :turnstile_failed} ->
        Logger.warning("Registration blocked by Turnstile verification")
        conn
        |> put_flash(:error, "Please complete the security verification")
        |> render(:register)
    end
  end

  @doc """
  Logs out the current user.
  """
  def logout(conn, _params) do
    conn
    |> Auth.clear_session()
    |> put_flash(:info, "You have been logged out")
    |> redirect(to: ~p"/")
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
  def request_password_reset(conn, %{"user" => %{"email" => email}}) do
    case Auth.request_password_reset(email) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "If your email exists in our system, you will receive password reset instructions shortly.")
        |> redirect(to: ~p"/auth/login")

      {:error, reason} ->
        require Logger
        Logger.error("Password reset request failed for email: #{inspect(reason)}")
        
        error_message = case reason do
          %{status: 429} ->
            "Too many password reset requests have been sent recently. Please wait a few minutes before trying again."
          %{message: msg} when is_binary(msg) ->
            msg
          _ ->
            "There was an error processing your request. Please try again."
        end
        
        conn
        |> put_flash(:error, error_message)
        |> redirect(to: ~p"/auth/forgot-password")
    end
  end

  # Fallback for direct email parameter (backward compatibility)
  def request_password_reset(conn, %{"email" => email}) do
    request_password_reset(conn, %{"user" => %{"email" => email}})
  end

  @doc """
  Handle callback routes for authentication flows, such as OAuth or email confirmations.
  """
  def callback(conn, params) do
    require Logger
    Logger.info("Auth callback received: #{inspect(params)}")

    case params do
      # Facebook OAuth callback
      %{"code" => code} when not is_nil(code) ->
        handle_facebook_oauth_callback(conn, code, params)

      %{"access_token" => _access_token, "refresh_token" => _refresh_token, "type" => "recovery"} = auth_data ->
        Logger.info("Password recovery callback with tokens - setting recovery session")
        case Auth.store_session(conn, auth_data, true) do
          {:ok, conn} ->
            conn
            |> put_session(:password_recovery, true)
            |> put_flash(:info, "Please set your new password below.")
            |> redirect(to: ~p"/auth/reset-password")
          {:error, _} ->
            conn
            |> put_flash(:error, "Session error. Please try again.")
            |> redirect(to: ~p"/auth/login")
        end

      %{"access_token" => access_token, "type" => "recovery"} ->
        Logger.info("Password recovery callback with access token - setting recovery session")
        conn
        |> put_session(:access_token, access_token)
        |> put_session(:password_recovery, true)
        |> put_flash(:info, "Please set your new password below.")
        |> redirect(to: ~p"/auth/reset-password")

      %{"access_token" => access_token, "refresh_token" => _refresh_token} = auth_data ->
        Logger.info("Callback with tokens - storing session")
        case Auth.store_session(conn, auth_data, true) do
          {:ok, conn} ->
            conn
            |> handle_post_auth_actions(access_token)
            |> handle_auth_redirect()
          {:error, _} ->
            conn
            |> put_flash(:error, "Session error. Please try again.")
            |> redirect(to: ~p"/auth/login")
        end

      %{"access_token" => access_token} ->
        Logger.info("Callback with access token only - storing session")
        conn
        |> put_session(:access_token, access_token)
        |> handle_post_auth_actions(access_token)
        |> handle_auth_redirect()

      %{"error" => error, "error_description" => description} ->
        Logger.error("Callback error: #{error} - #{description}")
        conn
        |> put_flash(:error, "Authentication failed: #{description}")
        |> redirect(to: ~p"/auth/login")

      %{"error" => error} ->
        Logger.error("Callback error: #{error}")
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: ~p"/auth/login")

      _other ->
        Logger.warning("Callback with no recognized parameters, redirecting to dashboard")
        # For email confirmations without tokens, redirect to login to let user sign in
        conn
        |> put_flash(:info, "Email confirmed! Please sign in.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Show the reset password form.
  """
  def reset_password(conn, params) do
    # Handle both token-based and session-based password recovery
    cond do
      # Token from URL parameter (legacy support)
      Map.has_key?(params, "token") ->
        render(conn, :reset_password, token: params["token"])

      # Recovery session with authenticated user
      conn.assigns[:auth_user] && get_session(conn, :password_recovery) ->
        render(conn, :reset_password, token: nil)

      # No recovery context - redirect to forgot password
      true ->
        conn
        |> put_flash(:error, "Invalid or expired password reset link. Please request a new one.")
        |> redirect(to: ~p"/auth/forgot-password")
    end
  end

  @doc """
  Process the reset password form submission.
  """
  def update_password(conn, %{"user" => %{"password" => password, "password_confirmation" => password_confirmation}} = params) do
    if password != password_confirmation do
      conn
      |> put_flash(:error, "Passwords do not match.")
      |> render(:reset_password, token: params["token"])
    else
      cond do
        # Token-based password reset (legacy)
        Map.has_key?(params, "token") && params["token"] ->
          case Auth.update_user_password(params["token"], password) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "Password updated successfully!")
              |> redirect(to: ~p"/auth/login")

            {:error, %{"message" => message}} ->
              conn
              |> put_flash(:error, message)
              |> render(:reset_password, token: params["token"])

            {:error, _} ->
              conn
              |> put_flash(:error, "Unable to update password")
              |> render(:reset_password, token: params["token"])
          end

        # Session-based password recovery (new flow)
        conn.assigns[:auth_user] && get_session(conn, :password_recovery) ->
          case Auth.update_current_user_password(conn, password) do
            {:ok, _} ->
              conn
              |> delete_session(:password_recovery)
              |> put_flash(:info, "Password updated successfully! You are now logged in.")
              |> redirect(to: ~p"/dashboard")

            {:error, %{"message" => message}} ->
              conn
              |> put_flash(:error, message)
              |> render(:reset_password, token: nil)

            {:error, _} ->
              conn
              |> put_flash(:error, "Unable to update password")
              |> render(:reset_password, token: nil)
          end

        # No valid context
        true ->
          conn
          |> put_flash(:error, "Invalid password reset session. Please request a new password reset.")
          |> redirect(to: ~p"/auth/forgot-password")
      end
    end
  end

  # Fallback for old format (backward compatibility)
  def update_password(conn, %{"token" => token, "password" => password}) do
    require Logger
    Logger.warning("Deprecated password reset format used. Please include password_confirmation in requests.")

    # For backward compatibility, use password as confirmation if not provided
    update_password(conn, %{
      "user" => %{
        "password" => password,
        "password_confirmation" => password
      },
      "token" => token
    })
  end

  @doc """
  Redirect user to Facebook OAuth login.
  """
  def facebook_login(conn, _params) do
    # Store action type (let Supabase handle CSRF state)
    conn = put_session(conn, :oauth_action, "login")

    # Get Facebook OAuth URL and redirect
    facebook_url = Auth.get_facebook_oauth_url()
    redirect(conn, external: facebook_url)
  end

  @doc """
  Handle Facebook OAuth error callback.
  """
  def facebook_callback(conn, %{"error" => error, "error_description" => description}) do
    Logger.error("Facebook OAuth error: #{error} - #{description}")
    conn
    |> put_flash(:error, "Facebook authentication was cancelled or failed.")
    |> redirect(to: ~p"/auth/login")
  end

  defp handle_facebook_oauth_callback(conn, code, _params) do
    oauth_action = get_session(conn, :oauth_action) || "login"

    Logger.info("Facebook OAuth callback - OAuth action: #{inspect(oauth_action)}")

    # Clear the OAuth action from session
    conn = delete_session(conn, :oauth_action)

    case oauth_action do
      "link" ->
        # User is trying to link Facebook account to existing account
        handle_facebook_account_linking(conn, code)

      "login" ->
        # User is trying to sign in with Facebook
        case Auth.sign_in_with_facebook_oauth(code) do
          {:ok, auth_data} ->
            Logger.info("Facebook OAuth successful")
            handle_successful_facebook_auth(conn, auth_data)

          {:error, error} ->
            Logger.error("Facebook OAuth callback failed: #{inspect(error)}")
            conn
            |> put_flash(:error, "Facebook authentication failed. Please try again.")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  defp handle_facebook_account_linking(conn, code) do
    case Auth.link_facebook_account(conn, code) do
      {:ok, _result} ->
        Logger.info("Facebook account linked successfully")
        conn
        |> put_flash(:info, "Facebook account connected successfully!")
        |> redirect(to: ~p"/settings/account")

      {:error, reason} ->
        Logger.error("Facebook account linking failed: #{inspect(reason)}")
        error_message = case reason do
          :no_authentication_token -> "Authentication session expired. Please log in again."
          %{message: message} when is_binary(message) -> message
          _ -> "Failed to connect Facebook account. Please try again."
        end

        conn
        |> put_flash(:error, error_message)
        |> redirect(to: ~p"/settings/account")
    end
  end

  defp handle_successful_facebook_auth(conn, auth_data) do
    # Safely extract required data with fallbacks
    user_data = Map.get(auth_data, "user")
    access_token = Map.get(auth_data, "access_token")

    if user_data && access_token do
      # Sync user with local database (using existing pattern)
      case EventasaurusApp.Auth.SupabaseSync.sync_user(user_data) do
        {:ok, user} ->
          # Check for stored return URL using the standard session key
          return_to = get_session(conn, :user_return_to)
          
          case Auth.store_session(conn, auth_data, true) do
            {:ok, conn} ->
              conn
              |> put_session(:current_user_id, user.id)
              |> put_flash(:info, "Successfully signed in with Facebook!")
              |> delete_session(:user_return_to)
              |> redirect(to: return_to || ~p"/dashboard")
            {:error, _} ->
              conn
              |> put_flash(:error, "Session error. Please try again.")
              |> redirect(to: ~p"/auth/login")
          end

        {:error, reason} ->
          Logger.error("Failed to sync Facebook user: #{inspect(reason)}")
          conn
          |> put_flash(:error, "Authentication failed - unable to create account.")
          |> redirect(to: ~p"/auth/login")
      end
    else
      Logger.error("Facebook OAuth missing required data: user=#{inspect(user_data != nil)}, access_token=#{inspect(access_token != nil)}")
      conn
      |> put_flash(:error, "Facebook authentication failed - incomplete data received.")
      |> redirect(to: ~p"/auth/login")
    end
  end

  # ============ PRIVATE FUNCTIONS ============

  # Validate that a URL is internal to our application
  defp valid_internal_url?(url) when is_binary(url) do
    # First check if it starts with "/" (relative URL)
    if String.starts_with?(url, "/") do
      # Additional check: ensure no protocol in path (prevents //evil.com)
      not String.contains?(url, "//")
    else
      # For absolute URLs, parse and check the host
      case URI.parse(url) do
        %URI{host: nil} -> 
          # No host means relative URL, but should start with "/"
          String.starts_with?(url, "/")
        %URI{host: host, scheme: scheme} when scheme in ["http", "https"] ->
          # Check if it's our domain
          app_host = EventasaurusWeb.Endpoint.host()
          host == app_host || (host == "localhost" && app_host == "localhost")
        _ ->
          false
      end
    end
  rescue
    _ -> false
  end
  defp valid_internal_url?(_), do: false

  # Handle post-authentication actions like processing pending interest registrations.
  defp handle_post_auth_actions(conn, access_token) do
    try do
      # Get user data from access token
      case EventasaurusApp.Auth.Client.get_user(access_token) do
        {:ok, supabase_user} ->
          # Check for pending interest event ID in user metadata
          user_metadata = Map.get(supabase_user, "user_metadata", %{})
          pending_event_id = Map.get(user_metadata, "pending_interest_event_id")

          if pending_event_id do
            process_pending_interest(conn, access_token, pending_event_id)
          else
            conn
          end

        {:error, reason} ->
          Logger.warning("Could not get user data for post-auth actions: #{inspect(reason)}")
          conn
      end
    rescue
      error ->
        Logger.warning("Error in post-auth actions: #{inspect(error)}")
        conn
    end
  end

  # Process pending interest registration for a user after successful authentication.
  defp process_pending_interest(conn, access_token, event_id) do
    try do
      # First ensure the user is synced with local database
      case EventasaurusApp.Auth.Client.get_user(access_token) do
        {:ok, supabase_user} ->
          case EventasaurusApp.Auth.SupabaseSync.sync_user(supabase_user) do
            {:ok, local_user} ->
              # Try to register interest
              case register_user_interest(local_user.id, event_id) do
                {:ok, event} ->
                  Logger.info("Successfully registered interest for user #{local_user.id} in event #{event_id}")
                  conn
                  |> put_flash(:info, "Welcome! Your interest in '#{event.title}' has been registered.")
                  |> put_session(:just_registered_interest, true)

                {:error, reason} ->
                  Logger.warning("Failed to register interest: #{inspect(reason)}")
                  conn
              end

            {:error, reason} ->
              Logger.warning("Failed to sync user for interest registration: #{inspect(reason)}")
              conn
          end

        {:error, reason} ->
          Logger.warning("Failed to get user data for interest registration: #{inspect(reason)}")
          conn
      end
    rescue
      error ->
        Logger.warning("Error processing pending interest: #{inspect(error)}")
        conn
    end
  end

  # Register a user's interest in an event using the participant API.
  defp register_user_interest(user_id, event_id) do
    try do
      # Parse event_id to integer if it's a string
      event_id = if is_binary(event_id), do: String.to_integer(event_id), else: event_id

      # Get the event first to validate it exists
      case EventasaurusApp.Events.get_event(event_id) do
        nil ->
          {:error, :event_not_found}

        event ->
          # Use the participant status API to register interest
          case EventasaurusApp.Events.update_participant_status(user_id, event_id, :interested) do
            {:ok, _participant} ->
              {:ok, event}

            {:error, reason} ->
              {:error, reason}
          end
      end
    rescue
      ArgumentError ->
        Logger.warning("Invalid event_id format: #{inspect(event_id)}")
        {:error, :invalid_event_id}

      error ->
        Logger.warning("Error registering user interest: #{inspect(error)}")
                 {:error, :registration_failed}
     end
   end

   # Handle redirect after successful authentication, considering if interest was just registered.
   defp handle_auth_redirect(conn) do
     cond do
       # User just registered interest - redirect back to event
       get_session(conn, :just_registered_interest) ->
         # Flash message should already be set by process_pending_interest
         conn
         |> delete_session(:just_registered_interest)
         |> redirect(to: ~p"/dashboard")  # For now, redirect to dashboard
         # TODO: Could redirect to event page if we store event slug in session

       # Normal authentication - redirect to dashboard
       true ->
         conn
         |> put_flash(:info, "Successfully signed in!")
         |> redirect(to: ~p"/dashboard")
     end
   end

  # Verify Turnstile token for bot protection
  defp verify_turnstile(params) do
    if Turnstile.enabled?() do
      token = params["cf-turnstile-response"] || params["user"]["cf-turnstile-response"] || ""
      
      case Turnstile.verify_token(token) do
        {:ok, true} -> :ok
        {:ok, false} -> {:error, :turnstile_failed}
        {:error, reason} ->
          Logger.error("Turnstile verification error: #{inspect(reason)}")
          # Allow registration to proceed on network/config errors to avoid blocking legitimate users
          :ok
      end
    else
      :ok
    end
  end
 end
