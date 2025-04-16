defmodule EventasaurusApp.Auth.SupabaseSync do
  @moduledoc """
  Synchronizes Supabase authentication users with our local database.
  This module handles creating or updating User records when users
  sign up or authenticate through Supabase.
  """

  alias EventasaurusApp.Accounts

  @doc """
  Synchronizes a Supabase user with our local database.
  Creates a new user if they don't exist, or updates an existing user
  based on the Supabase ID.

  ## Parameters
    - supabase_user: Map containing Supabase user data with at least id, email, and user_metadata

  ## Returns
    - {:ok, %User{}} on success
    - {:error, changeset} on failure
  """
  def sync_user(supabase_user) do
    supabase_id = supabase_user["id"]

    if is_nil(supabase_id) do
      {:error, %{message: "Invalid Supabase user data: missing ID"}}
    else
      case Accounts.get_user_by_supabase_id(supabase_id) do
        nil -> create_user_from_supabase(supabase_user)
        user -> update_user_from_supabase(user, supabase_user)
      end
    end
  end

  defp create_user_from_supabase(supabase_user) do
    user_params = %{
      email: supabase_user["email"],
      name: extract_name_from_supabase(supabase_user),
      supabase_id: supabase_user["id"]
    }

    Accounts.create_user(user_params)
  end

  defp update_user_from_supabase(user, supabase_user) do
    user_params = %{
      email: supabase_user["email"],
      name: extract_name_from_supabase(supabase_user)
    }

    Accounts.update_user(user, user_params)
  end

  defp extract_name_from_supabase(supabase_user) do
    # Try to get name from user_metadata, falling back to the email prefix
    case supabase_user do
      %{"user_metadata" => %{"name" => name}} when is_binary(name) and name != "" ->
        name

      %{"user_metadata" => %{"full_name" => name}} when is_binary(name) and name != "" ->
        name

      _ ->
        # Extract name from email (part before @)
        supabase_user["email"]
        |> String.split("@")
        |> List.first()
    end
  end
end
