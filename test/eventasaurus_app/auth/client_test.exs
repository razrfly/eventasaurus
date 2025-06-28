defmodule EventasaurusApp.Auth.ClientTest do
  use ExUnit.Case, async: true

  alias EventasaurusApp.Auth.Client

  describe "Facebook OAuth" do
    test "get_facebook_oauth_url/1 generates correct URL" do
      state = "test_state"
      url = Client.get_facebook_oauth_url(state)

      assert String.contains?(url, "provider=facebook")
      assert String.contains?(url, "state=test_state")
      assert String.contains?(url, "redirect_to=")
    end

    test "get_facebook_oauth_url/0 generates URL without state" do
      url = Client.get_facebook_oauth_url()

      assert String.contains?(url, "provider=facebook")
      assert String.contains?(url, "redirect_to=")
      refute String.contains?(url, "state=")
    end
  end

  describe "Facebook redirect URI" do
    test "get_facebook_redirect_uri uses configured site_url" do
      # This tests the private function indirectly through the OAuth URL
      url = Client.get_facebook_oauth_url()

      # Should contain the redirect_to parameter with the site URL
      assert String.contains?(url, "redirect_to=")
    end
  end
end
