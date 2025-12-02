defmodule EventasaurusApp.Auth.Clerk.Sync do
  @moduledoc """
  Synchronizes Clerk authentication users with our local database.
  This module handles creating or updating User records when users
  authenticate through Clerk.

  ## How It Works

  Our `users.id` (integer primary key) is the canonical identifier.
  Clerk stores this as `external_id`, and JWT claims include it as `userId`.

  1. Look up users by their integer ID from `claims["userId"]`
  2. Create new users if they don't exist (for new Clerk signups)
  3. Simple `Repo.get(User, id)` lookup - no UUID complexity

  ## Usage

      case ClerkSync.sync_user(clerk_claims) do
        {:ok, user} -> # User struct
        {:error, reason} -> # Error handling
      end
  """

  alias EventasaurusApp.Accounts
  require Logger

  @doc """
  Synchronizes a Clerk user with our local database.

  Takes the verified JWT claims from Clerk and ensures a corresponding
  User record exists in our database.

  ## Parameters
    - claims: Map containing verified Clerk JWT claims
    - opts: Optional keyword list with additional options

  ## Claims Structure
    - "sub": Clerk user ID (e.g., "user_abc123")
    - "userId": Our users.id (integer, stored as Clerk's external_id)
    - "email": User's email address
    - "first_name", "last_name": User's name components

  ## Returns
    - {:ok, %User{}} on success
    - {:error, reason} on failure
  """
  def sync_user(claims, opts \\ [])

  def sync_user(claims, opts) when is_map(claims) do
    # Extract user identifiers from claims
    # Priority: userId (our integer ID) > email lookup > create new
    user_id = parse_user_id(claims["userId"])
    clerk_id = claims["sub"]
    email = claims["email"]

    Logger.debug("Starting Clerk user sync", %{
      clerk_id: clerk_id,
      user_id: user_id,
      has_email: not is_nil(email)
    })

    find_or_create_user(user_id, clerk_id, email, claims, opts)
  end

  def sync_user(_, _), do: {:error, :invalid_claims}

  @doc """
  Gets a user from the local database based on Clerk claims.

  This is a read-only operation that doesn't create or update users.
  Useful for checking if a user exists without triggering sync.

  ## Returns
    - {:ok, %User{}} if user is found
    - {:error, :not_found} if no matching user
  """
  def get_user(claims) when is_map(claims) do
    user_id = parse_user_id(claims["userId"])
    email = claims["email"]

    cond do
      # If we have a user ID, look up directly by primary key
      is_integer(user_id) ->
        case Accounts.get_user(user_id) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      # Fall back to email lookup for new Clerk signups
      not is_nil(email) ->
        case Accounts.get_user_by_email(email) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      true ->
        {:error, :not_found}
    end
  end

  def get_user(_), do: {:error, :invalid_claims}

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp find_or_create_user(user_id, clerk_id, email, claims, opts) do
    cond do
      # Strategy 1: Look up by integer ID (migrated users)
      is_integer(user_id) ->
        case Accounts.get_user(user_id) do
          nil ->
            # ID not found - shouldn't happen for migrated users
            Logger.warning("User ID from claims not found in database", %{user_id: user_id})
            find_by_email_or_create(clerk_id, email, claims, opts)

          user ->
            Logger.debug("Found user by ID", %{user_id: user.id})
            maybe_update_user(user, claims, opts)
        end

      # Strategy 2: New Clerk signup - no userId claim yet
      true ->
        find_by_email_or_create(clerk_id, email, claims, opts)
    end
  end

  defp find_by_email_or_create(clerk_id, email, claims, opts) do
    if email do
      case Accounts.get_user_by_email(email) do
        nil ->
          # No user exists, create new
          create_user_from_clerk(clerk_id, email, claims, opts)

        user ->
          # User exists with email, update their info
          Logger.info("Found user by email", %{user_id: user.id})
          maybe_update_user(user, claims, opts)
      end
    else
      # No email in claims - try to fetch from Clerk API
      fetch_email_and_create(clerk_id, claims, opts)
    end
  end

  defp fetch_email_and_create(clerk_id, claims, opts) do
    case EventasaurusApp.Auth.Clerk.Client.get_user(clerk_id) do
      {:ok, clerk_user} ->
        email = extract_email_from_clerk_user(clerk_user)

        if email do
          # Retry with email
          find_by_email_or_create(clerk_id, email, claims, opts)
        else
          Logger.error("Clerk user has no email address", %{clerk_id: clerk_id})
          {:error, :no_email}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch Clerk user", %{
          clerk_id: clerk_id,
          reason: inspect(reason)
        })

        {:error, :clerk_api_error}
    end
  end

  defp create_user_from_clerk(clerk_id, email, claims, opts) do
    name = extract_name_from_claims(claims)

    # For new Clerk-native users, generate a UUID for legacy supabase_id column
    # TODO: Once supabase_id is nullable, this can be removed
    supabase_id = Ecto.UUID.generate()

    user_params = %{
      email: email,
      name: name,
      supabase_id: supabase_id
    }

    # Add referral_event_id from metadata if present
    metadata = Keyword.get(opts, :metadata, %{})

    user_params =
      if Map.has_key?(metadata, :referral_event_id) do
        Map.put(user_params, :referral_event_id, metadata.referral_event_id)
      else
        user_params
      end

    Logger.info("Creating new user from Clerk", %{
      email_domain: email_domain(email),
      clerk_id: clerk_id
    })

    case Accounts.create_user(user_params) do
      {:ok, user} ->
        Logger.info("Successfully created user from Clerk", %{user_id: user.id})
        # TODO: Update Clerk external_id with new user.id via webhook or API
        {:ok, user}

      {:error, changeset} ->
        Logger.error("Failed to create user from Clerk", %{
          errors: inspect(changeset.errors)
        })

        {:error, changeset}
    end
  end

  defp maybe_update_user(user, claims, opts) do
    if Keyword.get(opts, :update_on_sync, false) do
      name = extract_name_from_claims(claims)

      case Accounts.update_user(user, %{name: name}) do
        {:ok, updated_user} ->
          {:ok, updated_user}

        {:error, _changeset} ->
          # Update failed, but user exists - return existing user
          {:ok, user}
      end
    else
      {:ok, user}
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp extract_name_from_claims(claims) do
    first_name = claims["first_name"] || ""
    last_name = claims["last_name"] || ""

    name = String.trim("#{first_name} #{last_name}")

    if name == "" do
      # Fall back to email prefix
      case claims["email"] do
        nil -> "User"
        email -> email |> String.split("@") |> List.first()
      end
    else
      name
    end
  end

  defp extract_email_from_clerk_user(clerk_user) do
    case clerk_user["email_addresses"] do
      [first | _] -> first["email_address"]
      _ -> nil
    end
  end

  # Parse userId from claims - handles string or integer
  defp parse_user_id(nil), do: nil
  defp parse_user_id(id) when is_integer(id), do: id

  defp parse_user_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end

  defp parse_user_id(_), do: nil

  defp email_domain(nil), do: "unknown"
  defp email_domain(email), do: email |> String.split("@") |> List.last()
end
