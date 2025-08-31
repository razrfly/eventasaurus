defmodule EventasaurusApp.Auth.SeedUserManager do
  @moduledoc """
  Manages user creation for seeding with comprehensive error handling and logging.
  Provides a unified interface for creating users with or without Supabase authentication.
  """

  require Logger
  alias EventasaurusApp.Auth.{Client, ServiceRoleHelper}
  alias EventasaurusApp.{Repo, Accounts}

  @doc """
  Creates a user with Supabase authentication if available, otherwise creates a local user.
  Returns {:ok, user} or {:error, reason} with detailed logging.
  """
  def create_user(attrs) do
    email = Map.get(attrs, :email)
    
    Logger.info("Creating user: #{email}")
    
    if ServiceRoleHelper.service_role_key_available?() do
      create_auth_user(attrs)
    else
      create_local_user(attrs)
    end
  end

  @doc """
  Creates or updates a user, handling existing users gracefully.
  """
  def get_or_create_user(attrs) do
    email = Map.get(attrs, :email)
    
    case Repo.get_by(Accounts.User, email: email) do
      nil ->
        Logger.info("Creating new user: #{email}")
        create_user(attrs)
        
      existing_user ->
        Logger.info("User already exists: #{email}, updating...")
        update_existing_user(existing_user, attrs)
    end
  end

  @doc """
  Batch creates multiple users with progress tracking and error recovery.
  Returns {successful_users, failed_users} tuple.
  """
  def batch_create_users(users_attrs) do
    Logger.info("Starting batch user creation for #{length(users_attrs)} users")
    
    results = Enum.map(users_attrs, fn attrs ->
      case create_user(attrs) do
        {:ok, user} -> 
          {:ok, user}
        {:error, reason} -> 
          Logger.error("Failed to create user #{Map.get(attrs, :email)}: #{inspect(reason)}")
          {:error, {attrs, reason}}
      end
    end)
    
    successful = for {:ok, user} <- results, do: user
    failed = for {:error, data} <- results, do: data
    
    Logger.info("Batch creation complete: #{length(successful)} successful, #{length(failed)} failed")
    
    {successful, failed}
  end

  # Private functions

  defp create_auth_user(attrs) do
    email = Map.get(attrs, :email)
    password = Map.get(attrs, :password, "testpass123")
    name = Map.get(attrs, :name, "Test User")
    
    Logger.debug("Creating Supabase auth user for #{email}")
    
    case Client.admin_create_user(email, password, %{name: name}, true) do
      {:ok, auth_user} ->
        user_attrs = attrs
        |> Map.put(:supabase_id, auth_user["id"])
        |> Map.delete(:password)
        
        create_database_user(user_attrs)
        
      {:error, %{message: message}} when is_binary(message) ->
        if String.contains?(message, "already been registered") do
          Logger.warning("Auth user already exists for #{email}, creating local user only")
          handle_existing_auth_user(attrs)
        else
          Logger.error("Supabase auth creation failed for #{email}: #{message}")
          {:error, message}
        end
        
      {:error, error} ->
        Logger.error("Unexpected error creating auth for #{email}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp create_local_user(attrs) do
    Logger.warning("Creating local user without auth for #{Map.get(attrs, :email)}")
    
    user_attrs = attrs
    |> Map.put(:supabase_id, Ecto.UUID.generate())
    |> Map.delete(:password)
    
    create_database_user(user_attrs)
  end

  defp create_database_user(attrs) do
    changeset = %Accounts.User{}
    |> Ecto.Changeset.change(attrs)
    
    case Repo.insert(changeset) do
      {:ok, user} ->
        Logger.info("Successfully created user: #{user.email}")
        {:ok, user}
        
      {:error, changeset} ->
        Logger.error("Database insert failed: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp update_existing_user(user, attrs) do
    changeset = user
    |> Ecto.Changeset.change(Map.delete(attrs, :password))
    
    case Repo.update(changeset) do
      {:ok, updated_user} ->
        Logger.info("Successfully updated user: #{updated_user.email}")
        {:ok, updated_user}
        
      {:error, changeset} ->
        Logger.error("Failed to update user: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp handle_existing_auth_user(attrs) do
    # Try to find the existing auth user and sync with our database
    email = Map.get(attrs, :email)
    
    case fetch_supabase_user_by_email(email) do
      {:ok, auth_user} ->
        user_attrs = attrs
        |> Map.put(:supabase_id, auth_user["id"])
        |> Map.delete(:password)
        
        case Repo.get_by(Accounts.User, email: email) do
          nil -> create_database_user(user_attrs)
          existing -> update_existing_user(existing, user_attrs)
        end
        
      {:error, _} ->
        # Can't fetch the auth user, create with generated ID
        Logger.warning("Could not fetch existing auth user for #{email}, using generated ID")
        create_local_user(attrs)
    end
  end

  defp fetch_supabase_user_by_email(_email) do
    # This would require admin API access to list users
    # For now, we'll return an error to trigger fallback
    {:error, :not_implemented}
  end

  @doc """
  Validates that a user can authenticate with Supabase.
  Useful for testing seed data.
  """
  def validate_auth(email, password) do
    Logger.info("Validating authentication for #{email}")
    
    case Client.sign_in(email, password) do
      {:ok, _} ->
        Logger.info("✅ Authentication successful for #{email}")
        :ok
        
      {:error, reason} ->
        Logger.error("❌ Authentication failed for #{email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Provides a summary of seeded users and their auth status.
  """
  def summarize_users do
    users = Repo.all(Accounts.User)
    
    with_auth = Enum.filter(users, fn u -> 
      u.supabase_id && !String.starts_with?(u.supabase_id, "pending")
    end)
    
    without_auth = Enum.filter(users, fn u -> 
      !u.supabase_id || String.starts_with?(u.supabase_id, "pending")
    end)
    
    Logger.info("""
    
    ===== User Summary =====
    Total users: #{length(users)}
    With auth: #{length(with_auth)}
    Without auth: #{length(without_auth)}
    
    Users with authentication:
    #{Enum.map(with_auth, fn u -> "  - #{u.email}" end) |> Enum.join("\n")}
    
    Users without authentication:
    #{Enum.map(without_auth, fn u -> "  - #{u.email}" end) |> Enum.join("\n")}
    ========================
    """)
    
    %{
      total: length(users),
      with_auth: length(with_auth),
      without_auth: length(without_auth),
      auth_users: Enum.map(with_auth, & &1.email),
      local_users: Enum.map(without_auth, & &1.email)
    }
  end
end