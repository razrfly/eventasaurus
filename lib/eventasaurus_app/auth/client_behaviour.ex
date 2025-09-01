defmodule EventasaurusApp.Auth.ClientBehaviour do
  @moduledoc """
  Behaviour for authentication client implementations.
  This enables mocking of the Auth.Client in tests.
  """

  @doc """
  Sign up a new user with email and password.
  """
  @callback sign_up(String.t(), String.t(), String.t() | nil) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Sign in a user with email and password.
  """
  @callback sign_in(String.t(), String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Sign out a user by invalidating their token.
  """
  @callback sign_out(String.t()) ::
    :ok | {:error, any()}

  @doc """
  Reset a user's password by sending a reset email.
  """
  @callback reset_password(String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Update a user's password using a reset token.
  """
  @callback update_password(String.t(), String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Refresh an expired access token using a refresh token.
  """
  @callback refresh_token(String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get the current user information using their access token.
  """
  @callback get_user(String.t()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Create a user using admin API.
  
  Parameters:
    - email :: String.t()
    - password :: String.t()
    - user_metadata :: map()
    - email_confirm :: boolean() - true to auto-confirm (dev), false to require confirmation
  """
  @callback admin_create_user(String.t(), String.t(), map(), boolean()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Update a user using admin API.
  """
  @callback admin_update_user(String.t(), map()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Get a user by email using the admin API.
  """
  @callback admin_get_user_by_email(String.t()) :: {:ok, map()} | {:error, any()}

  @doc """
  Sign in with Facebook OAuth authorization code.
  """
  @callback sign_in_with_facebook_oauth(String.t()) :: {:ok, map()} | {:error, any()}

  @doc """
  Get the Facebook OAuth login URL.
  """
  @callback get_facebook_oauth_url() :: String.t()

  @doc """
  Link a Facebook account to an existing authenticated user.
  """
  @callback link_facebook_account(String.t(), String.t()) :: {:ok, map()} | {:error, any()}

  @doc """
  Sign in with Google OAuth authorization code.
  """
  @callback sign_in_with_google_oauth(String.t()) :: {:ok, map()} | {:error, any()}

  @doc """
  Get the Google OAuth login URL.
  """
  @callback get_google_oauth_url() :: String.t()

  @doc """
  Link a Google account to an existing authenticated user.
  """
  @callback link_google_account(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
end
