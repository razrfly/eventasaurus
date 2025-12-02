defmodule EventasaurusWeb.LiveHelpers do
  @moduledoc """
  Shared helper functions for Phoenix LiveViews.

  This module contains common functionality used across multiple LiveViews
  to avoid duplication and maintain consistency.
  """

  alias EventasaurusApp.Accounts

  @doc """
  Ensures we have a proper User struct from various auth data formats.

  This function handles the conversion from different authentication data formats
  (Clerk JWT claims, existing User structs, etc.) to a consistent local User struct.

  ## Supported Formats

  - `nil` -> `{:error, :no_user}`
  - `%Accounts.User{}` -> `{:ok, user}`
  - Clerk JWT claims map (with "sub" key) -> syncs user and returns `{:ok, user}`
  - Other -> `{:error, :invalid_user_data}`

  ## Examples

      iex> ensure_user_struct(nil)
      {:error, :no_user}

      iex> ensure_user_struct(%Accounts.User{id: 1})
      {:ok, %Accounts.User{id: 1}}

      iex> ensure_user_struct(%{"sub" => "user_abc123", "email" => "test@example.com"})
      {:ok, %Accounts.User{...}}
  """
  def ensure_user_struct(nil), do: {:error, :no_user}
  def ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}

  # Handle Clerk JWT claims (has "sub" key for Clerk user ID)
  def ensure_user_struct(%{"sub" => _clerk_id} = clerk_claims) do
    alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync
    ClerkSync.sync_user(clerk_claims)
  end

  def ensure_user_struct(_), do: {:error, :invalid_user_data}
end
