defmodule EventasaurusWeb.Dev.DevAuth do
  @moduledoc """
  Development-only authentication helpers for quick user switching.
  This module is only loaded in development and test environments.
  All functionality is disabled in production.
  """

  alias EventasaurusApp.Accounts
  require Logger

  @doc """
  Check if dev mode quick login is enabled.
  Always returns false in production.
  """
  def enabled? do
    Application.get_env(:eventasaurus, :environment, :prod) in [:dev, :test] &&
      Application.get_env(:eventasaurus, :dev_quick_login, true)
  end

  @doc """
  Get a list of available test users for quick login.
  Returns empty list if dev mode is disabled.
  """
  def list_quick_login_users do
    if enabled?() do
      # First, try to get our known test accounts
      known_accounts = [
        {"holden@gmail.com", "Personal Account"},
        {"admin@example.com", "Admin User"},
        {"demo@example.com", "Demo User"},
        {"organizer@example.com", "Event Organizer"},
        {"participant@example.com", "Event Participant"}
      ]
      
      # Get the actual users from the database
      users = known_accounts
      |> Enum.map(fn {email, label} ->
        case Accounts.get_user_by_email(email) do
          nil -> nil
          user -> {user, label}
        end
      end)
      |> Enum.filter(& &1)
      
      # If we have less than 3 users, add some random ones
      if length(users) < 3 do
        additional = Accounts.list_users()
        |> Enum.take(10)
        |> Enum.map(fn user ->
          label = user.name || String.split(user.email, "@") |> List.first()
          {user, label}
        end)
        
        Enum.uniq_by(users ++ additional, fn {user, _} -> user.id end)
        |> Enum.take(10)
      else
        users
      end
    else
      []
    end
  end

  @doc """
  Perform quick login for a user in development mode.
  Returns {:ok, user} or {:error, reason}.
  """
  def quick_login(user_id) when is_binary(user_id) do
    user_id
    |> String.to_integer()
    |> quick_login()
  rescue
    _ -> {:error, :invalid_user_id}
  end

  def quick_login(user_id) when is_integer(user_id) do
    if enabled?() do
      case Accounts.get_user(user_id) do
        nil ->
          {:error, :user_not_found}
        
        user ->
          Logger.info("🚧 DEV: Quick login for user #{user.email} (ID: #{user.id})")
          {:ok, user}
      end
    else
      {:error, :dev_mode_disabled}
    end
  end

  def quick_login(_), do: {:error, :invalid_user_id}

  @doc """
  Create a fake auth session for development.
  This simulates what would happen after a successful Supabase login.
  """
  def create_dev_session(conn, user) do
    if enabled?() do
      # Simply set the session values needed for dev mode
      conn
      |> Plug.Conn.put_session(:current_user_id, user.id)
      |> Plug.Conn.put_session(:dev_mode_login, true)
      |> Plug.Conn.put_session(:user_email, user.email)
      |> Plug.Conn.configure_session(renew: true)
    else
      conn
    end
  end
end