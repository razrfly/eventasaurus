defmodule EventasaurusApp.FamilyAssignmentTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Families

  describe "create_user/1 family assignment" do
    test "auto-assigns a valid family name when none provided" do
      attrs = %{
        email: "family-test-#{System.unique_integer([:positive])}@example.com",
        name: "Test User"
      }

      {:ok, user} = Accounts.create_user(attrs)
      assert user.family_name in Families.list_family_names()
    end

    test "preserves explicitly provided family name" do
      attrs = %{
        email: "family-test-#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        family_name: "Obsidian"
      }

      {:ok, user} = Accounts.create_user(attrs)
      assert user.family_name == "Obsidian"
    end

    test "overrides nil family_name with a random one" do
      attrs = %{
        email: "family-test-#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        family_name: nil
      }

      {:ok, user} = Accounts.create_user(attrs)
      assert user.family_name in Families.list_family_names()
    end

    test "overrides empty string family_name with a random one" do
      attrs = %{
        email: "family-test-#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        family_name: ""
      }

      {:ok, user} = Accounts.create_user(attrs)
      assert user.family_name in Families.list_family_names()
    end

    test "rejects invalid family name" do
      attrs = %{
        email: "family-test-#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        family_name: "NotAFamily"
      }

      {:error, changeset} = Accounts.create_user(attrs)
      assert errors_on(changeset)[:family_name] != nil
    end
  end
end
