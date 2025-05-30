defmodule EventasaurusWeb.Features.AuthNotificationTest do
  use EventasaurusWeb.FeatureCase, async: false

  import Wallaby.Query, only: [css: 1]
  import Wallaby.Browser

  describe "authentication notification behavior" do
    test "should show only one 'You must log in' message when accessing protected page", %{session: session} do
      # Visit a protected page that requires authentication
      session = session |> visit("/events/new")

      # Verify we're redirected to login
      current_url = session |> current_url()
      assert String.contains?(current_url, "/auth/login")

      # Check that we have exactly one flash message
      flash_elements = session |> all(css("[role='alert']"))
      assert length(flash_elements) == 1, "Expected exactly 1 flash element, but found #{length(flash_elements)}"

      # Check that the login message appears exactly once in the page text
      page_text = Wallaby.Browser.text(session)
      login_message_count =
        page_text
        |> String.split("You must log in to access this page")
        |> length()
        |> Kernel.-(1) # Subtract 1 because split creates n+1 parts for n occurrences

      assert login_message_count == 1, "Expected exactly 1 login message, but found #{login_message_count}"

      # Verify that the error flash has the proper "Error!" title
      assert String.contains?(page_text, "Error!"), "Expected flash message to contain 'Error!' title"
    end
  end
end
