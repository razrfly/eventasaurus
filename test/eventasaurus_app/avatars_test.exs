defmodule EventasaurusApp.AvatarsTest do
  use ExUnit.Case, async: true

  alias EventasaurusApp.Avatars

  describe "generate_url/2" do
    test "generates a valid DiceBear URL" do
      url = Avatars.generate_url("test@example.com")

      assert String.starts_with?(url, "https://api.dicebear.com/9.x/dylan/svg")
      assert String.contains?(url, "seed=test%40example.com")
    end

    test "properly encodes special characters in seed" do
      url = Avatars.generate_url("user@domain.com")

      assert String.contains?(url, "seed=user%40domain.com")
    end

    test "includes options as query parameters" do
      url = Avatars.generate_url("test", %{size: 100, backgroundColor: "transparent"})

      assert String.contains?(url, "size=100")
      assert String.contains?(url, "backgroundColor=transparent")
    end
  end

  describe "generate_user_avatar/2" do
    test "generates avatar from user struct" do
      user = %{email: "test@example.com"}
      url = Avatars.generate_user_avatar(user)

      assert String.contains?(url, "seed=test%40example.com")
    end

    test "generates avatar from email string" do
      url = Avatars.generate_user_avatar("test@example.com")

      assert String.contains?(url, "seed=test%40example.com")
    end
  end

  describe "generate_user_avatar_by_id/2" do
    test "generates avatar using user ID" do
      url = Avatars.generate_user_avatar_by_id(123)

      assert String.contains?(url, "seed=user_123")
    end
  end

  describe "generate_event_avatar/2" do
    test "generates avatar using event ID" do
      url = Avatars.generate_event_avatar(456)

      assert String.contains?(url, "seed=event_456")
    end
  end

  describe "current_style/0" do
    test "returns the configured style" do
      style = Avatars.current_style()

      assert style == "dylan"
    end
  end

  describe "available_styles/0" do
    test "returns list of available styles" do
      styles = Avatars.available_styles()

      assert is_list(styles)
      assert "dylan" in styles
      assert "avataaars" in styles
      assert "bottts" in styles
    end
  end

  describe "valid_style?/1" do
    test "returns true for valid styles" do
      assert Avatars.valid_style?("dylan") == true
      assert Avatars.valid_style?("avataaars") == true
    end

    test "returns false for invalid styles" do
      assert Avatars.valid_style?("invalid") == false
      assert Avatars.valid_style?("not-a-style") == false
    end
  end
end
