defmodule EventasaurusApp.Auth.Clerk.Sync do
  @moduledoc """
  Synchronizes Clerk authentication users with our local database.
  This module handles creating or updating User records when users
  authenticate through Clerk.

  ## How It Works

  During the migration period, Clerk users have their original Supabase UUID
  stored as `external_id` in Clerk. This allows us to:

  1. Look up users by their original Supabase UUID (stored in `supabase_id` column)
  2. Create new users if they don't exist
  3. Optionally track the Clerk user ID for future reference

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
    - "external_id" or "userId": Original Supabase UUID
    - "email": User's email address
    - "first_name", "last_name": User's name components

  ## Returns
    - {:ok, %User{}} on success
    - {:error, reason} on failure
  """
  def sync_user(claims, opts \\ [])

  def sync_user(claims, opts) when is_map(claims) do
    # Extract user identifiers from claims
    # Priority: external_id (Supabase UUID) > userId (custom claim) > sub (Clerk ID)
    user_id = claims["external_id"] || claims["userId"] || claims["sub"]
    clerk_id = claims["sub"]
    email = claims["email"]

    Logger.debug("Starting Clerk user sync", %{
      clerk_id: clerk_id,
      user_id: user_id,
      has_email: not is_nil(email)
    })

    if is_nil(user_id) do
      Logger.error("Invalid Clerk claims: missing user identifier")
      {:error, :missing_user_id}
    else
      find_or_create_user(user_id, clerk_id, email, claims, opts)
    end
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
    user_id = claims["external_id"] || claims["userId"] || claims["sub"]

    cond do
      is_nil(user_id) ->
        {:error, :missing_user_id}

      # Check if it looks like a Supabase UUID
      is_uuid?(user_id) ->
        case Accounts.get_user_by_supabase_id(user_id) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      # Otherwise it's a Clerk ID - try email lookup
      email = claims["email"] ->
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
    # Strategy 1: Look up by Supabase UUID (external_id)
    # This handles migrated users who have their original UUID in external_id
    if is_uuid?(user_id) do
      case Accounts.get_user_by_supabase_id(user_id) do
        nil ->
          # Not found by UUID, try email
          find_by_email_or_create(user_id, clerk_id, email, claims, opts)

        user ->
          Logger.debug("Found user by Supabase ID", %{user_id: user.id})
          maybe_update_user(user, claims, opts)
      end
    else
      # user_id is a Clerk ID, not a UUID - this is a new Clerk-native user
      find_by_email_or_create(user_id, clerk_id, email, claims, opts)
    end
  end

  defp find_by_email_or_create(user_id, clerk_id, email, claims, opts) do
    if email do
      case Accounts.get_user_by_email(email) do
        nil ->
          # No user exists, create new
          create_user_from_clerk(user_id, clerk_id, email, claims, opts)

        user ->
          # User exists with email, update their info
          Logger.info("Found user by email", %{user_id: user.id})
          maybe_update_user(user, claims, opts)
      end
    else
      # No email in claims - try to fetch from Clerk API
      fetch_email_and_create(user_id, clerk_id, claims, opts)
    end
  end

  defp fetch_email_and_create(user_id, clerk_id, claims, opts) do
    case EventasaurusApp.Auth.Clerk.Client.get_user(clerk_id) do
      {:ok, clerk_user} ->
        email = extract_email_from_clerk_user(clerk_user)

        if email do
          # Retry with email
          find_by_email_or_create(user_id, clerk_id, email, claims, opts)
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

  defp create_user_from_clerk(user_id, _clerk_id, email, claims, opts) do
    name = extract_name_from_claims(claims)

    # Use the external_id (Supabase UUID) as supabase_id if available
    # Otherwise generate a new UUID for new Clerk-native users
    supabase_id =
      if is_uuid?(user_id) do
        user_id
      else
        # For new Clerk-native users, we need to generate a UUID
        # or use the Clerk ID as-is (but our schema expects UUID format)
        Ecto.UUID.generate()
      end

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

    Logger.info("Creating new user from Clerk", %{email_domain: email_domain(email)})

    case Accounts.create_user(user_params) do
      {:ok, user} ->
        Logger.info("Successfully created user from Clerk", %{user_id: user.id})
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

  defp is_uuid?(str) when is_binary(str) do
    # UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    String.match?(str, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  end

  defp is_uuid?(_), do: false

  defp email_domain(nil), do: "unknown"
  defp email_domain(email), do: email |> String.split("@") |> List.last()
end
