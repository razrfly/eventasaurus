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
end
