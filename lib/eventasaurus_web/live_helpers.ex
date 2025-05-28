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
  (Supabase auth data, existing User structs, etc.) to a consistent local User struct.

  ## Examples

      iex> ensure_user_struct(nil)
      {:error, :no_user}

      iex> ensure_user_struct(%Accounts.User{id: 1})
      {:ok, %Accounts.User{id: 1}}

      iex> ensure_user_struct(%{"id" => "supabase-id", "email" => "test@example.com"})
      {:ok, %Accounts.User{...}}
  """
  def ensure_user_struct(nil), do: {:error, :no_user}
  def ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}
  def ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  def ensure_user_struct(_), do: {:error, :invalid_user_data}
end
