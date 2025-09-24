defmodule Eventasaurus.TestPosthog do
  @moduledoc """
  Test module for verifying PostHog analytics integration
  """

  alias Eventasaurus.Services.PosthogService

  def run_tests do
    IO.puts("\n🧪 Testing PostHog Analytics Integration...")
    IO.puts("==========================================\n")

    # Test 1: Send a test event
    IO.puts("1. Sending test event...")

    case PosthogService.send_event("test_analytics_event", "test-user-123", %{
           test_property: "test_value",
           environment: "development",
           timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, response} ->
        IO.puts("✅ Event sent successfully!")
        IO.inspect(response, label: "Response")

      {:error, reason} ->
        IO.puts("❌ Failed to send event")
        IO.inspect(reason, label: "Error")
    end

    # Test 2: Track guest invitation modal
    IO.puts("\n2. Testing guest invitation tracking...")

    case PosthogService.track_guest_invitation_modal_opened("test-user-123", "test-event-123", %{
           test_mode: true
         }) do
      {:ok, _} ->
        IO.puts("✅ Guest invitation event tracked!")

      {:error, reason} ->
        IO.puts("❌ Failed to track guest invitation")
        IO.inspect(reason)
    end

    # Test 3: Get analytics (this will test the private API key)
    IO.puts("\n3. Testing analytics query...")

    case PosthogService.get_analytics("test-event-123", 7) do
      {:ok, analytics} ->
        IO.puts("✅ Analytics query successful!")
        IO.inspect(analytics, label: "Analytics Data")

      {:error, reason} ->
        IO.puts("❌ Failed to get analytics")
        IO.inspect(reason, label: "Error")
    end

    IO.puts("\n📊 To verify in PostHog Dashboard:")
    IO.puts("1. Go to https://eu.i.posthog.com")
    IO.puts("2. Check the 'Events' section")
    IO.puts("3. Look for 'test_analytics_event' with user ID 'test-user-123'")
    IO.puts("4. Check 'guest_invitation_modal_opened' event")

    :ok
  end
end
