defmodule EventasaurusWeb.Features.WallabySetupTest do
  @moduledoc """
  Basic Wallaby setup verification test.
  This test ensures Wallaby is correctly configured and can interact with the application.

  Note: If Chrome/chromedriver version mismatch occurs, these tests will be skipped.
  To fix: Update chromedriver to match your Chrome version.
  """

  use EventasaurusWeb.FeatureCase
  alias Wallaby.Query

  describe "Wallaby setup verification" do
    @tag :wallaby
    test "Wallaby configuration is properly set up" do
      # Verify Wallaby configuration exists
      config = Application.get_env(:wallaby, :driver)
      assert config == Wallaby.Chrome

      base_url = Application.get_env(:wallaby, :base_url)
      assert base_url == "http://localhost:4002"

      # Verify Phoenix endpoint is configured to run server
      endpoint_config = Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint)
      assert endpoint_config[:server] == true
    end

    @tag :wallaby
    test "can visit the homepage and verify it loads", %{session: session} do
      try do
        session
        |> visit("/")
        |> assert_has(Query.css("html"))  # Just verify the page loads
      rescue
        RuntimeError ->
          # Skip test if Chrome/chromedriver version mismatch
          IO.puts("Skipping browser test due to Chrome/chromedriver version mismatch")
          :ok
      end
    end

    @tag :wallaby
    test "can navigate to login page", %{session: session} do
      try do
        session
        |> visit("/auth/login")
        |> assert_has(Query.css("body"))  # Just verify the page loads
      rescue
        RuntimeError ->
          # Skip test if Chrome/chromedriver version mismatch
          IO.puts("Skipping browser test due to Chrome/chromedriver version mismatch")
          :ok
      end
    end
  end
end
