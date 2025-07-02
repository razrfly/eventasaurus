defmodule EventasaurusWeb.ProfileHTMLTest do
  use EventasaurusWeb.ConnCase, async: true

  alias EventasaurusWeb.ProfileHTML
  alias EventasaurusApp.Accounts.User

  describe "display_name/1" do
    test "returns username when available" do
      user = %User{username: "testuser", name: "Test User"}
      assert ProfileHTML.display_name(user) == "testuser"
    end

    test "returns name when username is nil" do
      user = %User{username: nil, name: "Test User"}
      assert ProfileHTML.display_name(user) == "Test User"
    end
  end

  describe "profile_url/1" do
    test "returns profile URL for user with username" do
      user = %User{id: 1, username: "testuser"}
      assert ProfileHTML.profile_url(user) == "/user/testuser"
    end

    test "returns profile URL for user without username" do
      user = %User{id: 1, username: nil}
      assert ProfileHTML.profile_url(user) == "/user/1"
    end

    test "returns # for nil user" do
      assert ProfileHTML.profile_url(nil) == "#"
    end
  end

  describe "short_profile_url/1" do
    test "returns short profile URL for user with username" do
      user = %User{id: 1, username: "testuser"}
      assert ProfileHTML.short_profile_url(user) == "/u/testuser"
    end

    test "returns short profile URL for user without username" do
      user = %User{id: 1, username: nil}
      assert ProfileHTML.short_profile_url(user) == "/u/1"
    end

    test "returns # for nil user" do
      assert ProfileHTML.short_profile_url(nil) == "#"
    end
  end

  describe "shareable_profile_url/2" do
    test "returns full URL with default domain" do
      user = %User{id: 1, username: "testuser"}
      result = ProfileHTML.shareable_profile_url(user)
      assert result == "https://eventasaurus.com/user/testuser"
    end

    test "returns full URL with custom domain" do
      user = %User{id: 1, username: "testuser"}
      result = ProfileHTML.shareable_profile_url(user, "https://example.com")
      assert result == "https://example.com/user/testuser"
    end

    test "returns empty string for nil user" do
      assert ProfileHTML.shareable_profile_url(nil) == ""
      assert ProfileHTML.shareable_profile_url(nil, "https://example.com") == ""
    end
  end

  describe "social_url/2" do
    test "generates correct Instagram URL" do
      assert ProfileHTML.social_url("testuser", :instagram) == "https://instagram.com/testuser"
      assert ProfileHTML.social_url("@testuser", :instagram) == "https://instagram.com/testuser"
    end

    test "generates correct X (Twitter) URL" do
      assert ProfileHTML.social_url("testuser", :x) == "https://x.com/testuser"
      assert ProfileHTML.social_url("@testuser", :x) == "https://x.com/testuser"
    end

    test "generates correct YouTube URL" do
      assert ProfileHTML.social_url("testuser", :youtube) == "https://youtube.com/@testuser"
      assert ProfileHTML.social_url("@testuser", :youtube) == "https://youtube.com/@testuser"
    end

    test "handles full YouTube URLs" do
      full_url = "https://youtube.com/channel/UCtest123"
      assert ProfileHTML.social_url(full_url, :youtube) == full_url
    end

    test "generates correct TikTok URL" do
      assert ProfileHTML.social_url("testuser", :tiktok) == "https://tiktok.com/@testuser"
      assert ProfileHTML.social_url("@testuser", :tiktok) == "https://tiktok.com/@testuser"
    end

    test "generates correct LinkedIn URL" do
      assert ProfileHTML.social_url("testuser", :linkedin) == "https://linkedin.com/in/testuser"
      assert ProfileHTML.social_url("@testuser", :linkedin) == "https://linkedin.com/in/testuser"
    end

    test "handles full LinkedIn URLs" do
      full_url = "https://linkedin.com/in/test-user-123"
      assert ProfileHTML.social_url(full_url, :linkedin) == full_url
    end

    test "returns nil for empty or nil handles" do
      assert ProfileHTML.social_url("", :instagram) == nil
      assert ProfileHTML.social_url(nil, :instagram) == nil
    end

    test "returns # for unknown platforms" do
      assert ProfileHTML.social_url("testuser", :unknown) == "#"
    end
  end

  describe "format_website_url/1" do
    test "returns URL as-is if it starts with protocol" do
      assert ProfileHTML.format_website_url("https://example.com") == "https://example.com"
      assert ProfileHTML.format_website_url("http://example.com") == "http://example.com"
    end

    test "adds https:// prefix if missing" do
      assert ProfileHTML.format_website_url("example.com") == "https://example.com"
      assert ProfileHTML.format_website_url("www.example.com") == "https://www.example.com"
    end

    test "returns nil for empty or nil URLs" do
      assert ProfileHTML.format_website_url("") == nil
      assert ProfileHTML.format_website_url(nil) == nil
    end
  end

  describe "social_links/1" do
    test "returns list of configured social platforms" do
      user = %User{
        instagram_handle: "myinsta",
        x_handle: "mytwitter",
        youtube_handle: "",
        tiktok_handle: nil,
        linkedin_handle: "mylinkedin"
      }

      links = ProfileHTML.social_links(user)

      assert length(links) == 3
      assert {:instagram, "myinsta"} in links
      assert {:x, "mytwitter"} in links
      assert {:linkedin, "mylinkedin"} in links
      refute {:youtube, ""} in links
      refute {:tiktok, nil} in links
    end

    test "returns empty list when no social links configured" do
      user = %User{
        instagram_handle: nil,
        x_handle: "",
        youtube_handle: nil,
        tiktok_handle: nil,
        linkedin_handle: ""
      }

      assert ProfileHTML.social_links(user) == []
    end
  end

  describe "platform_name/1" do
    test "returns correct platform display names" do
      assert ProfileHTML.platform_name(:instagram) == "Instagram"
      assert ProfileHTML.platform_name(:x) == "X"
      assert ProfileHTML.platform_name(:youtube) == "YouTube"
      assert ProfileHTML.platform_name(:tiktok) == "TikTok"
      assert ProfileHTML.platform_name(:linkedin) == "LinkedIn"
    end

    test "returns stringified name for unknown platforms" do
      assert ProfileHTML.platform_name(:unknown) == "unknown"
    end
  end

  describe "profile_meta_tags/1" do
    test "returns meta tags for user" do
      user = %User{
        id: 1,
        username: "testuser",
        name: "Test User",
        bio: "This is my bio",
        email: "test@example.com"
      }

      meta_tags = ProfileHTML.profile_meta_tags(user)

      assert meta_tags.title == "testuser (@testuser) - Eventasaurus"
      assert meta_tags.description == "This is my bio"
      assert meta_tags.canonical_url == "/user/testuser"
      assert meta_tags.og_title == "testuser on Eventasaurus"
      assert meta_tags.og_url == "https://eventasaurus.com/user/testuser"
      assert meta_tags.twitter_card == "summary"
    end

    test "returns empty map for nil user" do
      assert ProfileHTML.profile_meta_tags(nil) == %{}
    end
  end

  describe "social_icon/1" do
    test "returns icons for all platforms" do
      # Currently returns generic 🔗 for all platforms
      assert ProfileHTML.social_icon(:instagram) == "🔗"
      assert ProfileHTML.social_icon(:x) == "🔗"
      assert ProfileHTML.social_icon(:youtube) == "🔗"
      assert ProfileHTML.social_icon(:tiktok) == "🔗"
      assert ProfileHTML.social_icon(:linkedin) == "🔗"
      assert ProfileHTML.social_icon(:unknown) == "🔗"
    end
  end
end
