defmodule EventasaurusApp.AccountsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User
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

    test "get_user_by_username_or_id/1 returns user when username exists" do
      user = user_fixture(%{username: "testuser123"})
      found_user = Accounts.get_user_by_username_or_id("testuser123")
      assert found_user.id == user.id
    end

    test "get_user_by_username_or_id/1 returns user when ID exists" do
      user = user_fixture()
      found_user = Accounts.get_user_by_username_or_id(to_string(user.id))
      assert found_user.id == user.id
    end

    test "get_user_by_username_or_id/1 handles user-{id} pattern for users without usernames" do
      # No username set
      user = user_fixture()
      slug = "user-#{user.id}"
      found_user = Accounts.get_user_by_username_or_id(slug)
      assert found_user.id == user.id
    end

    test "get_user_by_username_or_id/1 returns nil when identifier doesn't exist" do
      assert Accounts.get_user_by_username_or_id("nonexistent") == nil
      assert Accounts.get_user_by_username_or_id("99999") == nil
      assert Accounts.get_user_by_username_or_id("user-99999") == nil
    end

    test "get_user_by_username_or_id/1 prioritizes username over ID" do
      # Create user with ID, e.g., 1
      user1 = user_fixture()
      # Username is "1"
      user2 = user_fixture(%{username: to_string(user1.id)})

      # When searching for "1", should find user2 (username) not user1 (ID)
      found_user = Accounts.get_user_by_username_or_id(to_string(user1.id))
      assert found_user.id == user2.id
    end
  end

  describe "user profile fields" do
    test "profile_changeset/2 validates username format" do
      user = user_fixture()

      # Valid usernames
      valid_usernames = [
        "user123",
        "test_user",
        "my-handle",
        "abc",
        "user_with_underscore",
        "A1B2c3d4e5f6g7h8i9j0k1l2m3n4o"
      ]

      for username <- valid_usernames do
        changeset = User.profile_changeset(user, %{username: username})
        assert changeset.valid?, "Username '#{username}' should be valid"
      end

      # Invalid usernames
      invalid_usernames = [
        "us",
        "user@name",
        "user.name",
        "user name",
        "user#tag",
        "user!",
        "a very long username that exceeds thirty characters"
      ]

      for username <- invalid_usernames do
        changeset = User.profile_changeset(user, %{username: username})
        refute changeset.valid?, "Username '#{username}' should be invalid"
        assert changeset.errors[:username]
      end
    end

    test "profile_changeset/2 validates reserved usernames" do
      user = user_fixture()

      reserved_usernames = ["admin", "api", "www", "support", "root", "Administrator", "ADMIN"]

      for username <- reserved_usernames do
        changeset = User.profile_changeset(user, %{username: username})
        refute changeset.valid?, "Username '#{username}' should be invalid"

        assert changeset.errors[:username], "Should have username error for '#{username}'"
        error = changeset.errors[:username]
        {error_message, _} = if is_list(error), do: List.first(error), else: error

        assert String.contains?(error_message, "reserved"),
               "Error message should contain 'reserved' for '#{username}'"
      end
    end

    test "profile_changeset/2 validates bio length" do
      user = user_fixture()

      # Valid bio
      valid_bio = "This is a valid bio under 500 characters."
      changeset = User.profile_changeset(user, %{bio: valid_bio})
      assert changeset.valid?

      # Invalid bio (too long)
      long_bio = String.duplicate("a", 501)
      changeset = User.profile_changeset(user, %{bio: long_bio})
      refute changeset.valid?
      assert changeset.errors[:bio]
    end

    test "profile_changeset/2 validates website URL format" do
      user = user_fixture()

      # Valid URLs
      valid_urls = ["https://example.com", "http://test.org", "https://my-site.co.uk"]

      for url <- valid_urls do
        changeset = User.profile_changeset(user, %{website_url: url})
        assert changeset.valid?, "URL '#{url}' should be valid"
      end

      # Invalid URLs
      invalid_urls = ["example.com", "ftp://test.com", "not-a-url", "www.example.com"]

      for url <- invalid_urls do
        changeset = User.profile_changeset(user, %{website_url: url})
        refute changeset.valid?, "URL '#{url}' should be invalid"
        assert changeset.errors[:website_url]
      end

      # Empty URL should be valid
      changeset = User.profile_changeset(user, %{website_url: ""})
      assert changeset.valid?
    end

    test "profile_changeset/2 normalizes social media handles" do
      user = user_fixture()

      # Should remove @ symbol from handles
      changeset =
        User.profile_changeset(user, %{
          instagram_handle: "@testuser",
          x_handle: "@twitteruser",
          tiktok_handle: "@tiktokuser"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :instagram_handle) == "testuser"
      assert Ecto.Changeset.get_change(changeset, :x_handle) == "twitteruser"
      assert Ecto.Changeset.get_change(changeset, :tiktok_handle) == "tiktokuser"
    end

    test "profile_changeset/2 validates social media handle lengths" do
      user = user_fixture()

      # X handle too long
      long_x = String.duplicate("a", 16)
      changeset = User.profile_changeset(user, %{x_handle: long_x})
      refute changeset.valid?
      assert changeset.errors[:x_handle]

      # Instagram handle too long
      long_instagram = String.duplicate("a", 31)
      changeset = User.profile_changeset(user, %{instagram_handle: long_instagram})
      refute changeset.valid?
      assert changeset.errors[:instagram_handle]
    end

    test "profile_changeset/2 validates currency" do
      user = user_fixture()

      # Valid currencies
      valid_currencies = ["USD", "EUR", "GBP", "CAD", "AUD"]

      for currency <- valid_currencies do
        changeset = User.profile_changeset(user, %{default_currency: currency})
        assert changeset.valid?, "Currency '#{currency}' should be valid"
      end

      # Invalid currency
      changeset = User.profile_changeset(user, %{default_currency: "INVALID"})
      refute changeset.valid?
      assert changeset.errors[:default_currency]
    end

    test "profile_changeset/2 allows updating all profile fields" do
      user = user_fixture()

      profile_attrs = %{
        username: "testuser123",
        bio: "This is my bio",
        website_url: "https://example.com",
        profile_public: false,
        instagram_handle: "myinsta",
        x_handle: "mytwitter",
        youtube_handle: "mychannel",
        tiktok_handle: "mytiktok",
        linkedin_handle: "mylinkedin",
        default_currency: "EUR",
        timezone: "Europe/London"
      }

      changeset = User.profile_changeset(user, profile_attrs)
      assert changeset.valid?

      # Verify all fields are included in the changeset
      for {field, value} <- profile_attrs do
        assert Ecto.Changeset.get_change(changeset, field) == value
      end
    end

    test "profile_changeset/2 requires name field" do
      user = user_fixture()

      # Name is required
      changeset = User.profile_changeset(user, %{name: ""})
      refute changeset.valid?
      assert changeset.errors[:name]

      changeset = User.profile_changeset(user, %{name: nil})
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "profile_changeset/2 excludes sensitive fields" do
      user = user_fixture()

      # Should not allow updating email or supabase_id through profile_changeset
      changeset =
        User.profile_changeset(user, %{
          email: "newemail@example.com",
          supabase_id: "new-supabase-id",
          username: "validusername"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :email) == nil
      assert Ecto.Changeset.get_change(changeset, :supabase_id) == nil
      assert Ecto.Changeset.get_change(changeset, :username) == "validusername"
    end
  end

  describe "user helper functions" do
    test "display_name/1 returns username when available" do
      user = %User{username: "testuser", name: "Test User"}
      assert User.display_name(user) == "testuser"
    end

    test "display_name/1 returns name when username is nil" do
      user = %User{username: nil, name: "Test User"}
      assert User.display_name(user) == "Test User"
    end

    test "profile_url/1 returns username-based URL when username exists" do
      user = %User{id: 1, username: "testuser"}
      assert User.profile_url(user) == "/user/testuser"
    end

    test "profile_url/1 returns ID-based URL when username is nil" do
      user = %User{id: 1, username: nil}
      assert User.profile_url(user) == "/user/1"
    end

    test "short_profile_url/1 returns username-based short URL when username exists" do
      user = %User{id: 1, username: "testuser"}
      assert User.short_profile_url(user) == "/u/testuser"
    end

    test "short_profile_url/1 returns ID-based short URL when username is nil" do
      user = %User{id: 1, username: nil}
      assert User.short_profile_url(user) == "/u/1"
    end

    test "username_slug/1 returns username when available" do
      user = %User{id: 1, username: "testuser"}
      assert User.username_slug(user) == "testuser"
    end

    test "username_slug/1 returns user-{id} when username is nil" do
      user = %User{id: 1, username: nil}
      assert User.username_slug(user) == "user-1"
    end

    test "shareable_profile_url/1 returns full URL with default domain" do
      user = %User{id: 1, username: "testuser"}
      assert User.shareable_profile_url(user) == "https://eventasaurus.com/user/testuser"
    end

    test "shareable_profile_url/2 returns full URL with custom domain" do
      user = %User{id: 1, username: "testuser"}

      assert User.shareable_profile_url(user, "https://example.com") ==
               "https://example.com/user/testuser"
    end

    test "has_username?/1 returns true when username exists" do
      user = %User{username: "testuser"}
      assert User.has_username?(user) == true
    end

    test "has_username?/1 returns false when username is nil" do
      user = %User{username: nil}
      assert User.has_username?(user) == false
    end

    test "profile_handle/1 returns @username when username exists" do
      user = %User{id: 1, username: "testuser"}
      assert User.profile_handle(user) == "@testuser"
    end

    test "profile_handle/1 returns @user-{id} when username is nil" do
      user = %User{id: 1, username: nil}
      assert User.profile_handle(user) == "@user-1"
    end

    test "profile_public?/1 returns correct visibility status" do
      public_user = %User{profile_public: true}
      private_user = %User{profile_public: false}
      nil_user = %User{profile_public: nil}

      assert User.profile_public?(public_user) == true
      assert User.profile_public?(private_user) == false
      assert User.profile_public?(nil_user) == false
    end

    test "profile_meta_tags/1 returns comprehensive meta tags" do
      user = %User{
        id: 1,
        username: "testuser",
        name: "Test User",
        bio: "This is my bio",
        email: "test@example.com"
      }

      meta_tags = User.profile_meta_tags(user)

      assert meta_tags.title == "testuser (@testuser) - Eventasaurus"
      assert meta_tags.description == "This is my bio"
      assert meta_tags.canonical_url == "/user/testuser"
      assert meta_tags.og_title == "testuser on Eventasaurus"
      assert meta_tags.og_description == "This is my bio"
      assert meta_tags.og_url == "https://eventasaurus.com/user/testuser"
      assert meta_tags.twitter_card == "summary"
      assert meta_tags.twitter_title == "testuser (@testuser)"
      assert meta_tags.twitter_description == "This is my bio"
      assert String.contains?(meta_tags.og_image, "dicebear.com")
      assert String.contains?(meta_tags.twitter_image, "dicebear.com")
    end

    test "profile_meta_tags/1 uses display name as fallback for bio" do
      user = %User{
        id: 1,
        username: "testuser",
        name: "Test User",
        bio: nil,
        email: "test@example.com"
      }

      meta_tags = User.profile_meta_tags(user)

      assert meta_tags.description == "testuser's profile on Eventasaurus"
      assert meta_tags.og_description == "Check out testuser's profile on Eventasaurus"
      assert meta_tags.twitter_description == "testuser's profile on Eventasaurus"
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
        assert {:error, :invalid_supabase_data} =
                 Accounts.find_or_create_from_supabase(invalid_data)
      end
    end

    test "handles duplicate email creation gracefully" do
      # Create a user first
      existing_user = user_fixture()

      # Try to create another user with same email but different supabase_id
      supabase_user = %{
        "id" => "different-supabase-id-#{System.unique_integer([:positive])}",
        # Same email
        "email" => existing_user.email,
        "user_metadata" => %{"name" => "Different Name"}
      }

      # Should return error due to email uniqueness constraint
      assert {:error, changeset} = Accounts.find_or_create_from_supabase(supabase_user)
      assert changeset.errors[:email] != nil
    end
  end
end
