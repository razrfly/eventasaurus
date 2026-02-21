defmodule EventasaurusApp.Auth.SeedUserManager do
  @moduledoc """
  Manages user creation for seeding with comprehensive error handling and logging.

  Note: With the migration to Clerk authentication, this module now only creates
  local database users. Authentication is handled by Clerk, so users created here
  will need to authenticate through Clerk's UI.
  """

  require Logger
  alias EventasaurusApp.{Repo, Accounts}

  @doc """
  Creates a local user in the database.
  Returns {:ok, user} or {:error, reason} with detailed logging.

  With Clerk authentication, users created here will need to authenticate
  through Clerk separately.
  """
  @spec create_user(map()) :: {:ok, Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    email = Map.get(attrs, :email)
    Logger.info("Creating user: #{email}")
    create_local_user(attrs)
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

    results =
      Enum.map(users_attrs, fn attrs ->
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

    Logger.info(
      "Batch creation complete: #{length(successful)} successful, #{length(failed)} failed"
    )

    {successful, failed}
  end

  # Private functions

  defp create_local_user(attrs) do
    Logger.debug("Creating local database user for #{Map.get(attrs, :email)}")

    # Remove password field as it's not used with Clerk
    user_attrs = Map.delete(attrs, :password)

    create_database_user(user_attrs)
  end

  defp create_database_user(attrs) do
    # Auto-assign a random family name if not provided (NOT NULL column)
    attrs = Map.put_new_lazy(attrs, :family_name, &EventasaurusApp.Families.random_family_name/0)

    changeset =
      %Accounts.User{}
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
    changeset =
      user
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

  @doc """
  Validates that a user can authenticate.

  Note: With Clerk authentication, this function is deprecated.
  Authentication is now handled through Clerk's UI.
  """
  def validate_auth(_email, _password) do
    Logger.info("validate_auth is deprecated - authentication is now handled by Clerk")
    :ok
  end

  @doc """
  Provides a summary of seeded users.
  """
  @spec summarize_users() :: %{total: non_neg_integer(), users: [String.t()]}
  def summarize_users do
    users = Repo.all(Accounts.User)

    Logger.info("""

    ===== User Summary =====
    Total users: #{length(users)}

    All users (first 20):
    #{users |> Enum.take(20) |> Enum.map(fn u -> "  - #{u.email} (id: #{u.id})" end) |> Enum.join("\n")}
    ========================
    """)

    %{
      total: length(users),
      users: Enum.map(users, & &1.email)
    }
  end
end
