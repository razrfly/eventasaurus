defmodule EventasaurusWeb.Auth.AuthController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Auth

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
            Logger.info("Found existing user with email #{email}, logging in directly")
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
  def create_user(conn, %{"name" => name, "email" => email, "password" => password}) do
    require Logger
    Logger.info("Registration attempt for email: #{email}")

    case Auth.sign_up_with_email_and_password(email, password, %{name: name}) do
      {:ok, %{"access_token" => access_token, "refresh_token" => refresh_token}} ->
        Logger.info("Registration successful with tokens")
        conn
        |> put_session(:access_token, access_token)
        |> put_session(:refresh_token, refresh_token)
        |> put_flash(:info, "Account created successfully! Please check your email to verify your account.")
        |> redirect(to: ~p"/dashboard")

      {:ok, %{user: user, confirmation_required: true}} ->
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
  Handle callback routes for authentication flows, such as OAuth or email confirmations.
  """
  def callback(conn, %{"access_token" => access_token, "refresh_token" => refresh_token}) do
    conn
    |> put_session(:access_token, access_token)
    |> put_session(:refresh_token, refresh_token)
    |> put_flash(:info, "Successfully signed in!")
    |> redirect(to: ~p"/dashboard")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: ~p"/auth/login")
  end
end
