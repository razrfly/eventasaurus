defmodule EventasaurusWeb.PublicEventLiveMetaTagsTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

    describe "Open Graph meta tags" do
    setup do
      user = user_fixture()

      event = event_fixture(%{
        title: "Test Event for Social Sharing",
        description: "This is a test event to verify that Open Graph meta tags are working correctly for social media sharing.",
        slug: "test-social-event"
      })

      %{event: event, user: user}
    end

    test "includes Open Graph meta tags on event page", %{conn: conn, event: event} do
      {:ok, _live, html} = live(conn, ~p"/#{event.slug}")

      # Check for Open Graph meta tags
      assert html =~ ~s(property="og:title" content="#{event.title}")
      assert html =~ ~s(property="og:description")
      assert html =~ ~s(property="og:image")
      assert html =~ ~s(property="og:image:width" content="800")
      assert html =~ ~s(property="og:image:height" content="419")
      assert html =~ ~s(property="og:type" content="website")
      assert html =~ ~s(property="og:url")
      assert html =~ ~s(property="og:site_name" content="Eventasaurus")
    end

    test "includes Twitter Card meta tags on event page", %{conn: conn, event: event} do
      {:ok, _live, html} = live(conn, ~p"/#{event.slug}")

      # Check for Twitter Card meta tags
      assert html =~ ~s(name="twitter:card" content="summary_large_image")
      assert html =~ ~s(name="twitter:title" content="#{event.title}")
      assert html =~ ~s(name="twitter:description")
      assert html =~ ~s(name="twitter:image")
    end

    test "includes social card image URL", %{conn: conn, event: event} do
      {:ok, _live, html} = live(conn, ~p"/#{event.slug}")

      # Check that the social card URL is included
      assert html =~ ~s(/events/#{event.id}/social_card.png)
    end

        test "truncates long descriptions for meta tags", %{conn: conn} do
      _user = user_fixture()
      long_description = String.duplicate("This is a very long description. ", 10)

      event = event_fixture(%{
        title: "Event with Long Description",
        description: long_description,
        slug: "long-desc-event"
      })

      {:ok, _live, html} = live(conn, ~p"/#{event.slug}")

      # Extract the og:description content
      [_, description_content] = Regex.run(~r/property="og:description" content="([^"]*)"/, html)

      # Should be truncated to around 160 characters
      assert String.length(description_content) <= 160
      assert String.ends_with?(description_content, "...")
    end

        test "handles events without descriptions", %{conn: conn} do
      _user = user_fixture()

      event = event_fixture(%{
        title: "Event Without Description",
        description: nil,
        slug: "no-desc-event"
      })

      {:ok, _live, html} = live(conn, ~p"/#{event.slug}")

      # Should have a fallback description
      assert html =~ ~s(property="og:description" content="Join us for #{event.title}")
    end
  end

  # Note: Testing default meta tags on the home page requires session handling
  # which is outside the scope of this social card meta tags feature
end
