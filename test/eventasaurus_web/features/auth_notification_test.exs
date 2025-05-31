defmodule EventasaurusWeb.Features.AuthNotificationTest do
  use EventasaurusWeb.FeatureCase, async: false

  import Wallaby.Query, only: [css: 1]
  import Wallaby.Browser
  import EventasaurusApp.Factory

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

  describe "event management authorization vulnerabilities" do
    setup do
      # Create a user and their event using proper Events context
      user = insert(:user)

      # Create an event with organizer using the Events context function
      event_attrs = %{
        title: "My Private Event",
        description: "This is my private event that only I should be able to manage",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day),
        timezone: "America/Los_Angeles",
        visibility: :public
      }

      {:ok, event} = EventasaurusApp.Events.create_event_with_organizer(event_attrs, user)

      %{user: user, event: event}
    end

    test "✅ SECURITY FIXED: unauthenticated user cannot access event management page", %{session: session, event: event} do
      # Visit the event management page without being logged in
      session = session |> visit("/events/#{event.slug}")

      # Should be redirected to login (SECURITY FIXED)
      current_url = session |> current_url()

      # This assertion should now PASS, showing the security fix worked
      assert String.contains?(current_url, "/auth/login"),
        "✅ SECURITY FIXED: Unauthenticated user properly redirected to login. URL: #{current_url}"
    end

    test "✅ SECURITY FIXED: event management page properly protected", %{session: session, event: event} do
      # Visit the event management page without being logged in
      session = session |> visit("/events/#{event.slug}")

      current_url = session |> current_url()
      page_text = Wallaby.Browser.text(session)

      # Verify we're on the login page
      assert String.contains?(current_url, "/auth/login"),
        "Should be redirected to login page"

      # Verify we see the login form, not the event management page
      assert String.contains?(page_text, "Sign in to account"),
        "Should see login form"

      # Verify we don't see any event management content
      refute String.contains?(page_text, event.title),
        "Should not see event title on login page"
    end

    test "✅ AUTHORIZATION: users can only access events they organize", %{event: event} do
      # Create a different user (not the event organizer)
      other_user = insert(:user)

      # Create another event owned by the other user
      other_event_attrs = %{
        title: "Other User's Event",
        description: "This event belongs to someone else",
        start_at: DateTime.utc_now() |> DateTime.add(14, :day),
        timezone: "America/Los_Angeles",
        visibility: :public
      }

      {:ok, other_event} = EventasaurusApp.Events.create_event_with_organizer(other_event_attrs, other_user)

      # Verify ownership relationships
      assert EventasaurusApp.Events.user_can_manage_event?(other_user, other_event),
        "Other user should be able to manage their own event"

      refute EventasaurusApp.Events.user_can_manage_event?(other_user, event),
        "Other user should NOT be able to manage the first user's event"
    end
  end
end
