defmodule EventasaurusApp.AccountsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Accounts
  import EventasaurusApp.AccountsFixtures

  describe "users" do
    test "get_user_by_email/1 returns user when email exists" do
      user = user_fixture()
      found_user = Accounts.get_user_by_email(user.email)
      assert found_user.id == user.id
    end

    test "get_user_by_email/1 returns nil when email doesn't exist" do
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end

    test "get_user_by_supabase_id/1 returns user when supabase_id exists" do
      user = user_fixture()
      found_user = Accounts.get_user_by_supabase_id(user.supabase_id)
      assert found_user.id == user.id
    end

    test "get_user_by_supabase_id/1 returns nil when supabase_id doesn't exist" do
      assert Accounts.get_user_by_supabase_id("nonexistent-supabase-id") == nil
    end
  end

  describe "find_or_create_from_supabase/1" do
    test "returns existing user when supabase_id exists" do
      user = user_fixture()

      supabase_user = %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      }

      assert {:ok, found_user} = Accounts.find_or_create_from_supabase(supabase_user)
      assert found_user.id == user.id
      assert found_user.email == user.email
      assert found_user.supabase_id == user.supabase_id
    end

    test "creates new user when supabase_id doesn't exist" do
      supabase_user = %{
        "id" => "new-supabase-id-#{System.unique_integer([:positive])}",
        "email" => "newuser#{System.unique_integer([:positive])}@example.com",
        "user_metadata" => %{"name" => "New User"}
      }

      # Verify user doesn't exist
      assert Accounts.get_user_by_supabase_id(supabase_user["id"]) == nil

      # Create user
      assert {:ok, created_user} = Accounts.find_or_create_from_supabase(supabase_user)

      # Verify user was created correctly
      assert created_user.email == supabase_user["email"]
      assert created_user.name == supabase_user["user_metadata"]["name"]
      assert created_user.supabase_id == supabase_user["id"]

      # Verify user exists in database
      found_user = Accounts.get_user_by_supabase_id(supabase_user["id"])
      assert found_user.id == created_user.id
    end

    test "extracts name from email when user_metadata name is missing" do
      unique_id = System.unique_integer([:positive])
      supabase_user = %{
        "id" => "test-supabase-id-#{unique_id}",
        "email" => "john.doe#{unique_id}@example.com",
        "user_metadata" => %{}
      }

      assert {:ok, created_user} = Accounts.find_or_create_from_supabase(supabase_user)

      # Should extract and capitalize the first part of the email before @
      assert created_user.name == "John.doe#{unique_id}"
      assert created_user.email == supabase_user["email"]
    end

    test "handles user_metadata with nil name" do
      unique_id = System.unique_integer([:positive])
      supabase_user = %{
        "id" => "test-supabase-id-#{unique_id}",
        "email" => "test#{unique_id}@example.com",
        "user_metadata" => %{"name" => nil}
      }

      assert {:ok, created_user} = Accounts.find_or_create_from_supabase(supabase_user)

      # Should extract and capitalize the first part of the email before @
      assert created_user.name == "Test#{unique_id}"
    end

    test "returns error for invalid supabase data" do
      # Missing required fields
      invalid_data_cases = [
        %{},
        %{"id" => "test"},
        %{"email" => "test@example.com"},
        %{"id" => "test", "email" => "test@example.com"},
        %{"id" => "test", "user_metadata" => %{}},
        "invalid_string",
        nil
      ]

      for invalid_data <- invalid_data_cases do
        assert {:error, :invalid_supabase_data} = Accounts.find_or_create_from_supabase(invalid_data)
      end
    end

    test "handles duplicate email creation gracefully" do
      # Create a user first
      existing_user = user_fixture()

      # Try to create another user with same email but different supabase_id
      supabase_user = %{
        "id" => "different-supabase-id-#{System.unique_integer([:positive])}",
        "email" => existing_user.email, # Same email
        "user_metadata" => %{"name" => "Different Name"}
      }

      # Should return error due to email uniqueness constraint
      assert {:error, changeset} = Accounts.find_or_create_from_supabase(supabase_user)
      assert changeset.errors[:email] != nil
    end
  end


end
