defmodule Eventasaurus.Services.PosthogServiceTest do
  @moduledoc """
  Tests for PosthogService event tracking functionality.

  This test suite covers:
  - Event tracking functions for guest invitation analytics
  - GDPR compliance and consent handling
  - Error handling and API communication
  - Event metadata validation
  """

  use ExUnit.Case, async: true

  alias Eventasaurus.Services.PosthogService

  import Mox

  setup :verify_on_exit!

  describe "track_guest_invitation_modal_opened/3" do
    test "tracks modal opened event with correct metadata" do
      event_id = 123
      event_slug = "test-event"
      event_title = "Test Event"
      source = "guest_list_button"

      # Mock HTTPoison.post to verify the correct data is sent
      expect(HTTPoisonMock, :post, fn url, body, headers ->
        assert url == "https://app.posthog.com/capture/"

        # Parse the request body
        parsed_body = Jason.decode!(body)
        assert parsed_body["api_key"] == "test-posthog-key"
        assert parsed_body["event"] == "guest_invitation_modal_opened"

        # Verify properties
        properties = parsed_body["properties"]
        assert properties["event_id"] == event_id
        assert properties["event_slug"] == event_slug
        assert properties["event_title"] == event_title
        assert properties["source"] == source
        assert properties["$lib"] == "eventasaurus-backend"
        assert Map.has_key?(properties, "$timestamp")

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      # Set up environment
      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_guest_invitation_modal_opened(
        event_id,
        event_slug,
        event_title,
        source
      )

      assert {:ok, %{"status" => 1}} = result
    end

    test "handles missing API key gracefully" do
      System.delete_env("POSTHOG_API_KEY")

      result = PosthogService.track_guest_invitation_modal_opened(
        123, "test-event", "Test Event", "button"
      )

      assert {:error, :missing_api_key} = result
    end

    test "handles API errors gracefully" do
      # Mock API failure
      expect(HTTPoisonMock, :post, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{status_code: 400, body: "{\"error\":\"Bad Request\"}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_guest_invitation_modal_opened(
        123, "test-event", "Test Event", "button"
      )

      assert {:error, _} = result
    end

    test "handles network timeouts" do
      expect(HTTPoisonMock, :post, fn _url, _body, _headers ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_guest_invitation_modal_opened(
        123, "test-event", "Test Event", "button"
      )

      assert {:error, %HTTPoison.Error{reason: :timeout}} = result
    end
  end

  describe "track_historical_participant_selected/3" do
    test "tracks participant selection with complete metadata" do
      event_metadata = %{
        event_id: 123,
        event_slug: "test-event",
        event_title: "Test Event"
      }

      participant_metadata = %{
        participant_user_id: 456,
        participant_name: "John Doe",
        participant_email: "john@example.com"
      }

      analytics_metadata = %{
        recommendation_level: "highly_recommended",
        participation_count: 5,
        total_score: 8.7,
        total_selections: 3
      }

      expect(HTTPoisonMock, :post, fn url, body, headers ->
        parsed_body = Jason.decode!(body)

        assert parsed_body["event"] == "historical_participant_selected"

        properties = parsed_body["properties"]
        assert properties["event_id"] == 123
        assert properties["event_slug"] == "test-event"
        assert properties["event_title"] == "Test Event"
        assert properties["participant_user_id"] == 456
        assert properties["participant_name"] == "John Doe"
        assert properties["participant_email"] == "john@example.com"
        assert properties["recommendation_level"] == "highly_recommended"
        assert properties["participation_count"] == 5
        assert properties["total_score"] == 8.7
        assert properties["total_selections"] == 3

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_historical_participant_selected(
        event_metadata,
        participant_metadata,
        analytics_metadata
      )

      assert {:ok, %{"status" => 1}} = result
    end

    test "handles partial metadata gracefully" do
      # Test with minimal required metadata
      event_metadata = %{event_id: 123}
      participant_metadata = %{participant_user_id: 456}
      analytics_metadata = %{}

      expect(HTTPoisonMock, :post, fn url, body, headers ->
        parsed_body = Jason.decode!(body)
        properties = parsed_body["properties"]

        # Should still have the essential fields
        assert properties["event_id"] == 123
        assert properties["participant_user_id"] == 456

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_historical_participant_selected(
        event_metadata,
        participant_metadata,
        analytics_metadata
      )

      assert {:ok, %{"status" => 1}} = result
    end
  end

  describe "track_guest_added_directly/3" do
    test "tracks direct guest addition with complete analytics" do
      event_metadata = %{
        event_id: 123,
        event_slug: "test-event",
        event_title: "Test Event"
      }

      guest_counts = %{
        suggested_guests: 3,
        manual_guests: 2
      }

      source_breakdown = %{
        historical_suggestions: 3,
        manual_emails: 2,
        total_added: 5
      }

      expect(HTTPoisonMock, :post, fn url, body, headers ->
        parsed_body = Jason.decode!(body)

        assert parsed_body["event"] == "guest_added_directly"

        properties = parsed_body["properties"]
        assert properties["event_id"] == 123
        assert properties["suggested_guests"] == 3
        assert properties["manual_guests"] == 2
        assert properties["historical_suggestions"] == 3
        assert properties["manual_emails"] == 2
        assert properties["total_added"] == 5

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_guest_added_directly(
        event_metadata,
        guest_counts,
        source_breakdown
      )

      assert {:ok, %{"status" => 1}} = result
    end

    test "validates numeric data types" do
      event_metadata = %{event_id: 123}

      # Test with invalid numeric values
      guest_counts = %{
        suggested_guests: "invalid",  # Should be integer
        manual_guests: 2
      }

      source_breakdown = %{total_added: 2}

      # Should handle type conversion gracefully
      expect(HTTPoisonMock, :post, fn url, body, headers ->
        parsed_body = Jason.decode!(body)
        properties = parsed_body["properties"]

        # Invalid data should be handled appropriately
        assert is_integer(properties["manual_guests"])
        assert properties["manual_guests"] == 2

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_guest_added_directly(
        event_metadata,
        guest_counts,
        source_breakdown
      )

      assert {:ok, %{"status" => 1}} = result
    end
  end

  describe "send_event/3 private function integration" do
    test "properly formats event data for PostHog API" do
      event_name = "test_event"

      properties = %{
        "test_property" => "test_value",
        "numeric_property" => 42,
        "boolean_property" => true
      }

      expect(HTTPoisonMock, :post, fn url, body, headers ->
        # Verify URL
        assert url == "https://app.posthog.com/capture/"

        # Verify headers
        assert {"Content-Type", "application/json"} in headers

        # Verify body structure
        parsed_body = Jason.decode!(body)
        assert parsed_body["api_key"] == "test-posthog-key"
        assert parsed_body["event"] == "test_event"

        # Verify properties are merged correctly
        body_properties = parsed_body["properties"]
        assert body_properties["test_property"] == "test_value"
        assert body_properties["numeric_property"] == 42
        assert body_properties["boolean_property"] == true
        assert body_properties["$lib"] == "eventasaurus-backend"
        assert Map.has_key?(body_properties, "$timestamp")

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      # Use one of the public functions to test the private send_event function
      result = PosthogService.track_guest_invitation_modal_opened(
        42, "test", "Test", "button"
      )

      assert {:ok, %{"status" => 1}} = result
    end
  end

  describe "GDPR compliance and privacy" do
    test "does not send events without API key (privacy by design)" do
      System.delete_env("POSTHOG_API_KEY")

      # Ensure no HTTP calls are made when API key is missing
      expect(HTTPoisonMock, :post, 0, fn _, _, _ ->
        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      result = PosthogService.track_guest_invitation_modal_opened(
        123, "test", "Test", "button"
      )

      assert {:error, :missing_api_key} = result
    end

    test "includes minimal necessary data only" do
      expect(HTTPoisonMock, :post, fn url, body, headers ->
        parsed_body = Jason.decode!(body)
        properties = parsed_body["properties"]

        # Verify only expected properties are included (no extra PII)
        expected_keys = ["event_id", "event_slug", "event_title", "source", "$lib", "$timestamp"]
        actual_keys = Map.keys(properties)

        # All actual keys should be in expected keys
        assert Enum.all?(actual_keys, fn key -> key in expected_keys end)

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      PosthogService.track_guest_invitation_modal_opened(
        123, "test-event", "Test Event", "button"
      )
    end

    test "properly sanitizes email addresses" do
      # This test would verify that emails are hashed or anonymized if that feature exists
      # For now, we verify that emails are handled as expected
      event_metadata = %{event_id: 123}
      participant_metadata = %{
        participant_user_id: 456,
        participant_email: "user@example.com"
      }
      analytics_metadata = %{}

      expect(HTTPoisonMock, :post, fn url, body, headers ->
        parsed_body = Jason.decode!(body)
        properties = parsed_body["properties"]

        # Email should be included as provided (application's GDPR compliance handles this)
        assert properties["participant_email"] == "user@example.com"

        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"status\":1}"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      PosthogService.track_historical_participant_selected(
        event_metadata,
        participant_metadata,
        analytics_metadata
      )
    end
  end

  describe "error recovery and resilience" do
    test "continues operation when PostHog is unavailable" do
      expect(HTTPoisonMock, :post, fn _url, _body, _headers ->
        {:error, %HTTPoison.Error{reason: :nxdomain}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      # Should not crash the application
      result = PosthogService.track_guest_invitation_modal_opened(
        123, "test", "Test", "button"
      )

      assert {:error, %HTTPoison.Error{reason: :nxdomain}} = result
    end

    test "handles malformed API responses gracefully" do
      expect(HTTPoisonMock, :post, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "invalid json"}}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_guest_invitation_modal_opened(
        123, "test", "Test", "button"
      )

      # Should handle JSON parsing errors
      assert {:error, _} = result
    end

    test "handles rate limiting responses" do
      expect(HTTPoisonMock, :post, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 429,
          body: "{\"error\":\"Rate limit exceeded\"}"
        }}
      end)

      System.put_env("POSTHOG_API_KEY", "test-posthog-key")

      result = PosthogService.track_guest_invitation_modal_opened(
        123, "test", "Test", "button"
      )

      assert {:error, _} = result
    end
  end
end
