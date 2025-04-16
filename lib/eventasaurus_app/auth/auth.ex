defmodule EventasaurusApp.Auth do
  @moduledoc """
  The Auth context provides functions for user authentication.
  It serves as a facade over the Supabase client implementation.
  """

  alias EventasaurusApp.Auth.Client
  import Plug.Conn

  @doc """
  Register a new user with email and password.
  """
  def register(email, password, name \\ nil) do
    Client.sign_up(email, password, name)
  end

  @doc """
  Authenticate a user with email and password.
  """
  def authenticate(email, password) do
    Client.sign_in(email, password)
  end

  @doc """
  Log out a user.
  """
  def logout(token) do
    Client.sign_out(token)
  end

  @doc """
  Request a password reset for a user.
  """
  def request_password_reset(email) do
    Client.reset_password(email)
  end

  @doc """
  Reset a user's password using the reset token.
  """
  def reset_password(token, new_password) do
    Client.update_password(token, new_password)
  end

  @doc """
  Store authentication tokens in the session.
  """
  def store_session(conn, %{access_token: access_token, refresh_token: refresh_token}) do
    conn = conn
      |> put_session(:access_token, access_token)
      |> put_session(:refresh_token, refresh_token)
      |> configure_session(renew: true)

    {:ok, conn}
  end

  @doc """
  Clear authentication tokens from the session.
  """
  def clear_session(conn) do
    conn = conn
      |> delete_session(:access_token)
      |> delete_session(:refresh_token)
      |> configure_session(drop: true)

    conn
  end

  @doc """
  Get the current user from the session.
  """
  def get_current_user(conn) do
    # If we have an access token, try to get the user data
    with token when is_binary(token) <- get_session(conn, :access_token),
         {:ok, user} <- Client.get_user(token) do
      user
    else
      _ -> nil
    end
  end
end
