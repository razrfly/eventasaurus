defmodule EventasaurusApp.Auth.AuthHelper do
  @moduledoc """
  Helper functions for integrating with Supabase authentication.
  """

  alias EventasaurusApp.Auth.{Client, SupabaseSync}
  require Logger

  @doc """
  Fetches the current user from Supabase using the access token,
  and syncs the user data with our local database.

  ## Parameters
    - access_token: The Supabase JWT access token

  ## Returns
    - {:ok, %User{}} if the user exists and was synced successfully
    - {:error, reason} otherwise
  """
  def get_current_user(access_token) when is_binary(access_token) do
    with {:ok, supabase_user} <- fetch_supabase_user(access_token),
         {:ok, user} <- SupabaseSync.sync_user(supabase_user) do
      {:ok, user}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)

        Logger.error("User sync error: #{inspect(errors)}")
        # Return the user anyway if we can extract it from the changeset
        if changeset.valid? == false && changeset.data.id do
          Logger.info("Returning existing user despite sync error")
          {:ok, changeset.data}
        else
          {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("Authentication error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_current_user(_), do: {:error, :invalid_token}

  @doc """
  Fetches the Supabase user data using the access token.
  """
  def fetch_supabase_user(access_token) do
    # Use configurable auth client for testing
    auth_client = Application.get_env(:eventasaurus, :auth_client, Client)
    auth_client.get_user(access_token)
  end

  @doc """
  A convenience function to authenticate a user with email and password,
  and sync their data with our local database.

  ## Parameters
    - email: User's email
    - password: User's password

  ## Returns
    - {:ok, %{user: user, access_token: token}} if authentication succeeds
    - {:error, reason} otherwise
  """
  def authenticate_user(email, password) do
    with {:ok, auth_response} <- Client.sign_in(email, password),
         access_token = auth_response["access_token"],
         {:ok, user} <- get_current_user(access_token) do
      {:ok, %{user: user, access_token: access_token}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a new user in Supabase and syncs with our local database.

  ## Parameters
    - email: User's email
    - password: User's password
    - name: User's name

  ## Returns
    - {:ok, %{user: user, access_token: token}} if registration succeeds
    - {:error, reason} otherwise
  """
  def register_user(email, password, name) do
        with {:ok, auth_response} <- Client.sign_up(email, password, name) do
      # Extract user data - it might be nested under "user" or at the top level
      supabase_user = case auth_response do
        %{"user" => user_data} when not is_nil(user_data) -> user_data
        user_data -> user_data  # User data is at the top level
      end

      case SupabaseSync.sync_user(supabase_user) do
        {:ok, user} ->
          # Handle whether email confirmation is required
          case auth_response do
            %{"access_token" => access_token} when not is_nil(access_token) ->
              # Auto-confirmed signup
              {:ok, %{user: user, access_token: access_token}}
            _ ->
              # Email confirmation required
              {:ok, %{user: user, confirmation_required: true}}
          end
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Exchange OAuth authorization code for session tokens and sync user.

  This function handles the complete OAuth callback flow by:
  1. Exchanging the authorization code for tokens
  2. Fetching user data from Supabase
  3. Syncing the user with our local database

  ## Parameters
    - code: The authorization code from OAuth provider

  ## Returns
    - {:ok, %{user: user, access_token: token, refresh_token: token}} if successful
    - {:error, reason} otherwise
  """
  def exchange_oauth_code(code) when is_binary(code) do
    with {:ok, session_data} <- Client.exchange_code_for_session(code),
         access_token = session_data["access_token"],
         {:ok, user} <- get_current_user(access_token) do

      result = %{user: user, access_token: access_token}

      # Include refresh token if present
      result = if session_data["refresh_token"] do
        Map.put(result, :refresh_token, session_data["refresh_token"])
      else
        result
      end

      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("OAuth code exchange failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def exchange_oauth_code(_), do: {:error, :invalid_code}

  @doc """
  Get OAuth authorization URL for a social provider.

  ## Parameters
    - provider: "facebook" | "twitter" | other supported provider
    - redirect_to: Optional URL to redirect to after authentication
    - scopes: Optional scopes to request from the provider

  ## Returns
    The OAuth authorization URL string
  """
  def get_oauth_url(provider, redirect_to \\ nil, scopes \\ nil) do
    Client.get_oauth_url(provider, redirect_to, scopes)
  end
end
