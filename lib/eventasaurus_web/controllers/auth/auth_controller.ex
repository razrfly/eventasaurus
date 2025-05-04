defmodule EventasaurusWeb.Auth.AuthController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Auth

  @doc """
  Show the login form.
  """
  def login(conn, _params) do
    render(conn, :login_template)
  end

  @doc """
  Process the login form submission.
  """
  def create_session(conn, %{"email" => email, "password" => password}) do
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
            |> assign(:current_user, user)
            |> put_flash(:info, "You have been logged in successfully.")
            |> redirect(to: ~p"/dashboard")

          {:error, reason} ->
            Logger.error("Failed to store session: #{inspect(reason)}")
            conn
            |> put_flash(:error, "Error storing session data. Please contact support.")
            |> render(:login_template)
        end

      # Special case for email already exists but with different Supabase ID
      {:error, %Ecto.Changeset{errors: [email: {"has already been taken", _}]}} ->
        Logger.error("Authentication failed: Email already exists with a different ID")
        # Try to get the user by email and log them in directly
        case EventasaurusApp.Accounts.get_user_by_email(email) do
          nil ->
            conn
            |> put_flash(:error, "Authentication failed. Please try again.")
            |> render(:login_template)

          user ->
            Logger.info("Found existing user with email #{email}, logging in directly")
            conn
            |> assign(:current_user, user)
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
        |> render(:login_template)
    end
  end

  @doc """
  Show the registration form.
  """
  def register(conn, _params) do
    render(conn, :register_template)
  end

  @doc """
  Process the registration form submission.
  """
  def create_user(conn, %{"name" => name, "email" => email, "password" => password, "password_confirmation" => password_confirmation}) do
    require Logger

    if password == password_confirmation do
      case Auth.register(email, password, name) do
        {:ok, user_data} ->
          Logger.debug("User registered successfully: #{inspect(user_data)}")

          # Automatically log the user in after registration
          case Auth.authenticate(email, password) do
            {:ok, auth_data} ->
              case Auth.store_session(conn, auth_data) do
                {:ok, conn} ->
                  # Fetch current user for the session
                  user = Auth.get_current_user(conn)

                  conn
                  |> assign(:current_user, user)
                  |> put_flash(:info, "Your account has been created successfully and you're now logged in.")
                  |> redirect(to: ~p"/dashboard")

                {:error, _reason} ->
                  # Registration was successful, but auto-login failed, so redirect to login page
                  conn
                  |> put_flash(:info, "Your account has been created successfully. Please log in.")
                  |> redirect(to: ~p"/login")
              end

            {:error, _reason} ->
              # Registration was successful, but we couldn't log in automatically
              conn
              |> put_flash(:info, "Your account has been created successfully. Please log in.")
              |> redirect(to: ~p"/login")
          end

        {:error, reason} ->
          Logger.error("Registration failed: #{inspect(reason)}")
          error_message = case reason do
            %{message: message} when is_binary(message) -> message
            _ -> "There was an error creating your account. Please try again."
          end

          conn
          |> put_flash(:error, error_message)
          |> render(:register_template)
      end
    else
      conn
      |> put_flash(:error, "Passwords do not match. Please try again.")
      |> render(:register_template)
    end
  end

  @doc """
  Logs out the current user.
  """
  def logout(conn, _params) do
    # Get the current access token
    token = get_session(conn, :access_token) || "mock_token"

    case Auth.logout(token) do
      :ok ->
        conn
        |> Auth.clear_session()
        |> put_flash(:info, "You have been logged out successfully.")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "There was an error logging out. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  @doc """
  Show the forgot password form.
  """
  def forgot_password(conn, _params) do
    render(conn, :forgot_password_template)
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
    render(conn, :reset_password_template, token: token)
  end

  @doc """
  Process the reset password form submission.
  """
  def update_password(conn, %{"token" => token, "password" => password, "password_confirmation" => password_confirmation}) do
    if password == password_confirmation do
      case Auth.reset_password(token, password) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Your password has been reset successfully. Please log in with your new password.")
          |> redirect(to: ~p"/login")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "There was an error resetting your password. Please try again.")
          |> render(:reset_password_template, token: token)
      end
    else
      conn
      |> put_flash(:error, "Passwords do not match. Please try again.")
      |> render(:reset_password_template, token: token)
    end
  end

  @doc """
  Handle callback routes for authentication flows, such as OAuth or email confirmations.
  """
  def callback(conn, params) do
    case params do
      %{"access_token" => access_token, "refresh_token" => refresh_token, "type" => type} ->
        auth_data = %{access_token: access_token, refresh_token: refresh_token}
        {:ok, conn} = Auth.store_session(conn, auth_data)

        message = case type do
          "signup" -> "Your email has been confirmed and you're now signed in!"
          "recovery" -> "Your password has been reset successfully."
          _ -> "Authentication completed successfully."
        end

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/dashboard")

      _ ->
        # No tokens provided, just redirect to home
        conn
        |> put_flash(:error, "Invalid authentication callback. Please try logging in.")
        |> redirect(to: ~p"/login")
    end
  end
end
