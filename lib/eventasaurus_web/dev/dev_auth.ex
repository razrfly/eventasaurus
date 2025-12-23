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
  Get a list of available test users for quick login, organized by category.
  Returns a map with :personal, :organizers, and :participants keys.
  """
  def list_quick_login_users do
    if enabled?() do
      import Ecto.Query
      alias EventasaurusApp.Repo

      # Get ALL users with their event management counts
      users_with_counts =
        Repo.all(
          from(u in EventasaurusApp.Accounts.User,
            left_join: eu in EventasaurusApp.Events.EventUser,
            on: u.id == eu.user_id and eu.role in ["owner", "organizer"],
            group_by: u.id,
            select: {u, count(eu.id)},
            order_by: [desc: count(eu.id), asc: u.email]
          )
        )

      # Separate into categories
      personal =
        users_with_counts
        |> Enum.filter(fn {user, _} -> user.email == "holden@gmail.com" end)
        |> Enum.map(fn {user, _} -> {user, "Personal Account"} end)

      # Organizers: anyone who manages at least 4 events
      organizers =
        users_with_counts
        |> Enum.filter(fn {user, count} ->
          count >= 4 && user.email != "holden@gmail.com"
        end)
        |> Enum.map(fn {user, count} ->
          label = format_user_label(user, count)
          {user, label}
        end)

      # Participants: users who don't manage any events (limited to 5 for cleaner UI)
      participants =
        users_with_counts
        |> Enum.filter(fn {user, count} ->
          count == 0 && user.email != "holden@gmail.com"
        end)
        # Limit participants to 5 for cleaner dropdown
        |> Enum.take(5)
        |> Enum.map(fn {user, _count} ->
          {user, user.name || String.split(user.email, "@") |> List.first()}
        end)

      # Return as categorized structure for the component to handle
      %{
        personal: personal,
        organizers: organizers,
        participants: participants
      }
    else
      %{personal: [], organizers: [], participants: []}
    end
  end

  # Format user label with emoji and event count
  defp format_user_label(user, event_count) do
    email_prefix = user.email |> String.split("@") |> List.first() |> String.downcase()

    emoji =
      cond do
        String.contains?(email_prefix, "movie") -> "🎬"
        String.contains?(email_prefix, "foodie") -> "🍴"
        String.contains?(email_prefix, "go_kart") -> "🏎️"
        String.contains?(email_prefix, "workshop") -> "🎓"
        String.contains?(email_prefix, "entertainment") -> "🎭"
        String.contains?(email_prefix, ["community_fund", "fundraiser"]) -> "🤝"
        String.contains?(email_prefix, "sports") -> "⚽"
        String.contains?(email_prefix, "book") -> "📚"
        String.contains?(email_prefix, ["game", "gaming"]) -> "🎮"
        String.contains?(email_prefix, ["outdoor", "hiking"]) -> "🥾"
        String.contains?(email_prefix, ["music", "concert"]) -> "🎵"
        String.contains?(email_prefix, "wine") -> "🍷"
        String.contains?(email_prefix, "tech") -> "💻"
        String.contains?(email_prefix, "art") -> "🎨"
        String.contains?(email_prefix, "fitness") -> "💪"
        true -> "📅"
      end

    "#{emoji} #{user.name || user.email} (#{event_count} events)"
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
  This simulates what would happen after a successful Clerk login.
  """
  def create_dev_session(conn, user) do
    require Logger

    if enabled?() do
      # In dev mode, use a fake access token
      # File uploads now use Cloudflare R2 with service credentials, not user tokens
      dev_access_token = "dev_mode_token_#{user.id}"

      Logger.debug("🔧 DEV AUTH: Creating dev session for user #{user.id}")

      # Calculate a fake expiration time (1 day from now)
      expires_at = DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.to_iso8601()

      # Simply set the session values needed for dev mode
      conn
      |> Plug.Conn.put_session("current_user_id", user.id)
      |> Plug.Conn.put_session("dev_mode_login", true)
      |> Plug.Conn.put_session("user_email", user.email)
      |> Plug.Conn.put_session("access_token", dev_access_token)
      |> Plug.Conn.put_session("token_expires_at", expires_at)
      |> Plug.Conn.configure_session(renew: true)
      |> tap(fn _ ->
        Logger.info("✅ DEV AUTH: Session created for user #{user.id} with access_token stored")
      end)
    else
      conn
    end
  end
end
