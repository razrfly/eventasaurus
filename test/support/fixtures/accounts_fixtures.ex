defmodule EventasaurusApp.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EventasaurusApp.Accounts` context.
  """

  alias EventasaurusApp.Accounts

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "test#{System.unique_integer([:positive])}@example.com",
        name: "Test User #{System.unique_integer([:positive])}",
        profile_public: true,
        default_currency: "USD"
      })
      |> Accounts.create_user()

    user
  end
end
