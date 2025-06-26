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
    authenticate(conn, %{"user" => %{"email" => email, "password" => password, "remember_me" => "true"}})
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

      {:error, _reason} ->
        conn
        |> put_flash(:error, "There was an error processing your request. Please try again.")
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
      %{"access_token" => access_token, "refresh_token" => refresh_token, "type" => "recovery"} ->
        Logger.info("Password recovery callback with tokens - setting recovery session")
        conn
        |> put_session(:access_token, access_token)
        |> put_session(:refresh_token, refresh_token)
        |> put_session(:password_recovery, true)
        |> put_flash(:info, "Please set your new password below.")
        |> redirect(to: ~p"/auth/reset-password")

      %{"access_token" => access_token, "type" => "recovery"} ->
        Logger.info("Password recovery callback with access token - setting recovery session")
        conn
        |> put_session(:access_token, access_token)
        |> put_session(:password_recovery, true)
        |> put_flash(:info, "Please set your new password below.")
        |> redirect(to: ~p"/auth/reset-password")

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
end
