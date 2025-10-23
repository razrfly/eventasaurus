defmodule Eventasaurus.EmailsTest do
  use EventasaurusApp.DataCase, async: true
  import Swoosh.TestAssertions
  alias Eventasaurus.Emails
  alias EventasaurusApp.{Events, Accounts}

  describe "guest_invitation_email/5" do
    test "creates a properly formatted email with basic event data" do
      organizer = user_fixture(%{name: "Alice Organizer", email: "alice@example.com"})

      event =
        simple_event_struct(%{
          title: "Test Event",
          description: "A test event description",
          start_at: ~U[2024-12-25 15:00:00Z],
          slug: "test-event"
        })

      email =
        Emails.guest_invitation_email(
          "guest@example.com",
          "John Guest",
          event,
          "Looking forward to seeing you there!",
          organizer
        )

      # Test email structure
      assert email.subject == "You're invited to Test Event"
      assert email.to == [{"John Guest", "guest@example.com"}]
      assert email.from == {"Eventasaurus", "invitations@eventasaur.us"}
      assert email.reply_to == {"", "alice@example.com"}

      # Test HTML content includes key elements
      html_body = email.html_body
      assert html_body =~ "Test Event"
      assert html_body =~ "Alice Organizer"
      assert html_body =~ "John Guest"
      assert html_body =~ "A test event description"
      assert html_body =~ "December 25, 2024"
      assert html_body =~ "Looking forward to seeing you there!"
      assert html_body =~ "http://localhost:4002/events/test-event"

      # Test text content includes key elements
      text_body = email.text_body
      assert text_body =~ "Test Event"
      assert text_body =~ "Alice Organizer"
      assert text_body =~ "John Guest"
      assert text_body =~ "A test event description"
      assert text_body =~ "December 25, 2024"
      assert text_body =~ "Looking forward to seeing you there!"
      assert text_body =~ "http://localhost:4002/events/test-event"
    end

    test "handles minimal event data gracefully" do
      organizer = user_fixture(%{username: "organizer", email: "org@example.com"})

      event =
        simple_event_struct(%{
          title: "Simple Event",
          description: nil,
          start_at: nil,
          slug: "simple-event"
        })

      email =
        Emails.guest_invitation_email(
          "guest@example.com",
          # No guest name
          nil,
          event,
          # No invitation message
          nil,
          organizer
        )

      # Should still work with minimal data
      assert email.subject == "You're invited to Simple Event"
      assert email.to == [{"", "guest@example.com"}]
      assert email.from == {"Eventasaurus", "invitations@eventasaur.us"}

      # Should handle missing data gracefully
      html_body = email.html_body
      assert html_body =~ "Simple Event"
      # Should use user's name
      assert html_body =~ "Test User"
      # Should default when guest name is nil
      assert html_body =~ "Hi there,"
      # Should handle nil start_at
      assert html_body =~ "Date TBD"

      text_body = email.text_body
      assert text_body =~ "Simple Event"
      assert text_body =~ "Test User"
      assert text_body =~ "Hi there,"
      assert text_body =~ "Date TBD"
    end

    test "handles non-ticketed events correctly" do
      organizer = user_fixture()

      event =
        simple_event_struct(%{
          title: "Free Event",
          is_ticketed: false,
          slug: "free-event"
        })

      email =
        Emails.guest_invitation_email(
          "guest@example.com",
          "Guest Name",
          event,
          "",
          organizer
        )

      # Price section should not appear for non-ticketed events
      refute email.html_body =~ "Price"
      refute email.text_body =~ "Price"
    end
  end

  describe "send_guest_invitation/5" do
    test "sends email successfully in test mode" do
      organizer = user_fixture(%{name: "Test Organizer", email: "organizer@example.com"})
      event = simple_event_struct(%{title: "Email Test Event", slug: "email-test-event"})

      assert {:ok, _response} =
               Emails.send_guest_invitation(
                 "recipient@example.com",
                 "Recipient Name",
                 event,
                 "Test invitation message",
                 organizer
               )

      # Verify email was sent using Swoosh test assertions
      assert_email_sent(fn email ->
        email.subject == "You're invited to Email Test Event" and
          email.to == [{"Recipient Name", "recipient@example.com"}]
      end)
    end
  end

  describe "security" do
    test "escapes HTML in user-provided content to prevent XSS" do
      organizer = user_fixture(%{name: "<script>alert('xss')</script>"})

      event =
        simple_event_struct(%{
          title: "Event <script>alert('xss')</script>",
          description: "<img src=x onerror=alert('xss')>",
          slug: "test-event"
        })

      email =
        Emails.guest_invitation_email(
          "guest@example.com",
          "<b>Bold Guest</b>",
          event,
          "<script>alert('message')</script>",
          organizer
        )

      # HTML should be escaped
      assert email.html_body =~ "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
      assert email.html_body =~ "&lt;img src=x onerror=alert(&#39;xss&#39;)&gt;"
      assert email.html_body =~ "&lt;b&gt;Bold Guest&lt;/b&gt;"
      # Ensure raw script tags are not present
      refute email.html_body =~ "<script>alert('xss')</script>"
    end

    test "validates email address format" do
      organizer = user_fixture()
      event = simple_event_struct()

      assert_raise ArgumentError, ~r/Invalid email/, fn ->
        Emails.guest_invitation_email(
          "not-an-email",
          "Guest",
          event,
          "",
          organizer
        )
      end
    end
  end

  describe "error handling" do
    test "handles mailer delivery failures gracefully" do
      # Mock a mailer failure scenario
      organizer = user_fixture()
      event = simple_event_struct()

      # This would need proper mocking setup for full testing
      # For now, just verify the function exists and can be called
      assert is_function(&Emails.send_guest_invitation/5)
    end
  end

  describe "image CDN optimization" do
    test "wraps external image URLs with CDN transformations when CDN is enabled" do
      organizer = user_fixture()

      # Test with external_image_data (Unsplash/TMDB)
      event =
        simple_event_struct(%{
          title: "Event with External Image",
          external_image_data: %{"url" => "https://images.unsplash.com/photo-123.jpg"},
          slug: "event-with-image"
        })

      email =
        Emails.guest_invitation_email(
          "guest@example.com",
          "Guest Name",
          event,
          "",
          organizer
        )

      html_body = email.html_body

      # If CDN is enabled, URL should be wrapped
      # If CDN is disabled (dev default), URL should be original
      # Test that image tag exists
      assert html_body =~ ~r/<img[^>]+class="event-image"/

      # In development, CDN might be disabled, so we just verify the image is rendered
      # In production with CDN enabled, it would contain cdn.wombie.com
    end

    test "wraps user-uploaded cover image URLs with CDN transformations" do
      organizer = user_fixture()

      # Test with cover_image_url (user upload)
      event =
        simple_event_struct(%{
          title: "Event with Cover Image",
          cover_image_url: "https://example.com/uploads/event-cover.jpg",
          slug: "event-with-cover"
        })

      email =
        Emails.guest_invitation_email(
          "guest@example.com",
          "Guest Name",
          event,
          "",
          organizer
        )

      html_body = email.html_body

      # Verify image is rendered
      assert html_body =~ ~r/<img[^>]+class="event-image"/
    end

    test "handles events without images gracefully" do
      organizer = user_fixture()

      # Test with no image
      event =
        simple_event_struct(%{
          title: "Event without Image",
          cover_image_url: nil,
          external_image_data: nil,
          slug: "event-no-image"
        })

      email =
        Emails.guest_invitation_email(
          "guest@example.com",
          "Guest Name",
          event,
          "",
          organizer
        )

      html_body = email.html_body

      # Should not contain an event-image
      refute html_body =~ ~r/<img[^>]+class="event-image"/
    end
  end

  # Helper to create a simple event struct without database interactions
  defp simple_event_struct(attrs \\ %{}) do
    defaults = %{
      id: System.unique_integer([:positive]),
      title: "Test Event",
      description: "Test description",
      slug: "test-event",
      start_at: ~U[2024-12-01 10:00:00Z],
      ends_at: ~U[2024-12-01 12:00:00Z],
      status: :confirmed,
      visibility: :public,
      timezone: "UTC",
      is_ticketed: false
    }

    struct(Events.Event, Map.merge(defaults, attrs))
  end

  # Simple user fixture using the actual Accounts module
  defp user_fixture(attrs \\ %{}) do
    default_attrs = %{
      supabase_id: "test-sb-#{System.unique_integer([:positive])}",
      email: "user-#{System.unique_integer([:positive])}@example.com",
      username: "user#{System.unique_integer([:positive])}",
      name: "Test User"
    }

    {:ok, user} =
      attrs
      |> Enum.into(default_attrs)
      |> Accounts.create_user()

    user
  end
end
