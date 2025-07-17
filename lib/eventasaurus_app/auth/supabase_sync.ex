defmodule EventasaurusApp.Auth.SupabaseSync do
  @moduledoc """
  Synchronizes Supabase authentication users with our local database.
  This module handles creating or updating User records when users
  sign up or authenticate through Supabase.
  """

  alias EventasaurusApp.Accounts
  require Logger

  @doc """
  Synchronizes a Supabase user with our local database.
  Creates a new user if they don't exist, or updates an existing user
  based on the Supabase ID or email.

  ## Parameters
    - supabase_user: Map containing Supabase user data with at least id, email, and user_metadata

  ## Returns
    - {:ok, %User{}} on success
    - {:error, changeset} on failure
  """
  def sync_user(supabase_user) do
    supabase_id = supabase_user["id"]
    email = supabase_user["email"]

    Logger.debug("Starting Supabase user sync", %{
      supabase_id: supabase_id,
      email_domain: email |> String.split("@") |> List.last()
    })

    if is_nil(supabase_id) or is_nil(email) do
      Logger.error("Invalid Supabase user data: missing ID or email")
      {:error, %{message: "Invalid Supabase user data: missing ID or email"}}
    else
      # First try to find by Supabase ID
      case Accounts.get_user_by_supabase_id(supabase_id) do
        nil ->
          Logger.debug("No user found by Supabase ID, checking by email")
          # If not found by ID, try to find by email
          case Accounts.get_user_by_email(email) do
            nil ->
              # User doesn't exist by ID or email, create new
              Logger.info("No existing user found, creating new user")
              result = create_user_from_supabase(supabase_user)

              case result do
                {:ok, user} ->
                  Logger.info("Successfully created new user", %{user_id: user.id})

                {:error, changeset} ->
                  Logger.error("Failed to create new user", %{errors: inspect(changeset.errors)})
              end

              result

            existing_user ->
              # User exists with same email but different Supabase ID
              # Update the user and set their supabase_id
              Logger.info("User exists with email but different Supabase ID, updating", %{
                user_id: existing_user.id,
                email_domain: email |> String.split("@") |> List.last()
              })

              result = update_user_from_supabase(existing_user, supabase_user, true)

              case result do
                {:ok, user} ->
                  Logger.info("Successfully updated user with Supabase ID", %{user_id: user.id})

                {:error, changeset} ->
                  Logger.error("Failed to update user with Supabase ID", %{
                    user_id: existing_user.id,
                    errors: inspect(changeset.errors)
                  })
              end

              result
          end

        user ->
          # User found by Supabase ID, just update
          Logger.debug("User found by Supabase ID, updating user data", %{user_id: user.id})
          result = update_user_from_supabase(user, supabase_user)

          case result do
            {:ok, updated_user} ->
              Logger.debug("Successfully updated existing user", %{user_id: updated_user.id})

            {:error, changeset} ->
              Logger.error("Failed to update existing user", %{
                user_id: user.id,
                errors: inspect(changeset.errors)
              })
          end

          result
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

  defp update_user_from_supabase(user, supabase_user, update_id \\ false) do
    # Only include supabase_id in the params if update_id is true
    base_params = %{
      email: supabase_user["email"],
      name: extract_name_from_supabase(supabase_user)
    }

    user_params =
      if update_id do
        Map.put(base_params, :supabase_id, supabase_user["id"])
      else
        base_params
      end

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
