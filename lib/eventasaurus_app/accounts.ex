defmodule EventasaurusApp.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Accounts.User

  @doc """
  Returns the list of users.
  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user.

  Returns nil if the User does not exist.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by Supabase ID.
  """
  def get_user_by_supabase_id(supabase_id) do
    Repo.get_by(User, supabase_id: supabase_id)
  end

  @doc """
  Gets a user by username (case-insensitive).
  """
  def get_user_by_username(username) when is_binary(username) do
    from(u in User, where: fragment("lower(?)", u.username) == ^String.downcase(username))
    |> Repo.one()
  end

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Finds or creates a user from Supabase user data.
  Returns {:ok, user} or {:error, reason}.
  """
  def find_or_create_from_supabase(%{"id" => supabase_id, "email" => email, "user_metadata" => user_metadata}) do
    case get_user_by_supabase_id(supabase_id) do
      %User{} = user ->
        {:ok, user}
      nil ->
        name = user_metadata["name"] || extract_name_from_email(email)
        user_params = %{
          email: email,
          name: name,
          supabase_id: supabase_id
        }
        create_user(user_params)
    end
  end

  def find_or_create_from_supabase(_), do: {:error, :invalid_supabase_data}

  # Helper function to extract name from email consistently
  defp extract_name_from_email(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.capitalize()
  end

  defp extract_name_from_email(_), do: "User"
end
