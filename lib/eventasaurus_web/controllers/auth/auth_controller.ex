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
  def create_session(conn, %{"email" => email, "password" => password}) do
    case Auth.authenticate(email, password) do
      {:ok, auth_data} ->
        conn
        |> Auth.store_session(auth_data)
        |> put_flash(:info, "You have been logged in successfully.")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid email or password. Please try again.")
        |> render(:login)
    end
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
  def create_user(conn, %{"name" => name, "email" => email, "password" => password, "password_confirmation" => password_confirmation}) do
    if password == password_confirmation do
      case Auth.register(email, password) do
        {:ok, _user_data} ->
          conn
          |> put_flash(:info, "Your account has been created successfully. Please log in.")
          |> redirect(to: ~p"/login")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "There was an error creating your account. Please try again.")
          |> render(:register)
      end
    else
      conn
      |> put_flash(:error, "Passwords do not match. Please try again.")
      |> render(:register)
    end
  end

  @doc """
  Logs out the current user.
  """
  def logout(conn, _params) do
    # Get the current access token (to be implemented in session management)
    # For now we'll use a placeholder
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
  def update_password(conn, %{"token" => token, "password" => password, "password_confirmation" => password_confirmation}) do
    # This would be implemented to validate the token and update the password
    # For now, we'll just redirect with a success message
    conn
    |> put_flash(:info, "Your password has been reset successfully. Please log in with your new password.")
    |> redirect(to: ~p"/login")
  end

  @doc """
  Handle callback routes for authentication flows, such as OAuth or email confirmations.
  """
  def callback(conn, params) do
    # This would be implemented for OAuth or email confirmation flows
    # For now, redirect to home
    conn
    |> put_flash(:info, "Authentication completed.")
    |> redirect(to: ~p"/")
  end
end
