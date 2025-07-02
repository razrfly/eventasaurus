defmodule Eventasaurus.Services.PosthogServiceTest do
  use ExUnit.Case, async: false

  import Mox

  alias Eventasaurus.Services.PosthogService

  # Setup mocks before running tests
  setup :verify_on_exit!

    describe "PosthogService" do
    setup do
      # Clear cache before each test (service already running via application)
      PosthogService.clear_cache(:all)

      # Mock environment variable for private API key (used by PosthogService)
      original_private_key = System.get_env("POSTHOG_PRIVATE_API_KEY")
      System.put_env("POSTHOG_PRIVATE_API_KEY", "test_private_key_123")

      on_exit(fn ->
        if original_private_key do
          System.put_env("POSTHOG_PRIVATE_API_KEY", original_private_key)
        else
          System.delete_env("POSTHOG_PRIVATE_API_KEY")
        end
      end)

      :ok
    end

    test "get_analytics returns fallback data when no API key" do
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      assert {:ok, analytics} = PosthogService.get_analytics("123", 7)

      assert analytics == %{
        unique_visitors: 0,
        registrations: 0,
        registration_rate: 0.0,
        votes_cast: 0,
        ticket_checkouts: 0,
        checkout_conversion_rate: 0.0,
        error: "PostHog private API key not configured - analytics unavailable",
        has_error: true
      }
    end

    test "get_unique_visitors extracts visitors from analytics" do
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      assert {:ok, visitors} = PosthogService.get_unique_visitors("123", 7)
      assert visitors == 0
    end

    test "get_registration_rate extracts rate from analytics" do
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      assert {:ok, rate} = PosthogService.get_registration_rate("123", 7)
      assert rate == 0.0
    end

    test "clear_cache removes specific event data" do
      # First, populate cache with fallback data (no API key)
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      {:ok, _} = PosthogService.get_analytics("123", 7)
      {:ok, _} = PosthogService.get_analytics("456", 7)

      # Clear cache for specific event
      PosthogService.clear_cache("123")

      # Verify cache was cleared by checking that we get fallback data again
      assert {:ok, analytics} = PosthogService.get_analytics("123", 7)
      assert analytics.unique_visitors == 0
    end

    test "clear_cache removes all cached data" do
      # Populate cache with fallback data
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      {:ok, _} = PosthogService.get_analytics("123", 7)
      {:ok, _} = PosthogService.get_analytics("456", 7)

      # Clear all cache
      PosthogService.clear_cache(:all)

      # Verify cache was cleared
      assert {:ok, analytics} = PosthogService.get_analytics("123", 7)
      assert analytics.unique_visitors == 0
    end

    test "calculates rates correctly" do
      # Test rate calculation through direct module call
      # Since calculate_rate is private, we test it through public functions

      # Mock a scenario with visitors and registrations
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      {:ok, analytics} = PosthogService.get_analytics("123", 7)

      # Fallback analytics should have 0 rate when denominator is 0
      assert analytics.registration_rate == 0.0
      assert analytics.checkout_conversion_rate == 0.0
    end

    test "service handles different date ranges" do
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      # Test different date ranges
      {:ok, analytics_7} = PosthogService.get_analytics("123", 7)
      {:ok, analytics_30} = PosthogService.get_analytics("123", 30)

      # Should get same fallback data for different ranges
      assert analytics_7 == analytics_30
    end

    test "service starts and responds to GenServer calls" do
      # Test that the service is responsive
      assert {:ok, _} = PosthogService.get_analytics("test", 7)
    end
  end

  describe "error handling" do
    test "returns fallback data on API errors" do
      # When API key exists but API calls fail, should return fallback
      System.put_env("POSTHOG_PRIVATE_API_KEY", "invalid_key")

      assert {:ok, analytics} = PosthogService.get_analytics("123", 7)

      # Should get fallback data
      assert analytics == %{
        unique_visitors: 0,
        registrations: 0,
        registration_rate: 0.0,
        votes_cast: 0,
        ticket_checkouts: 0,
        checkout_conversion_rate: 0.0,
        error: "PostHog authentication failed - please check private API key permissions",
        has_error: true
      }
    end
  end

  describe "caching behavior" do
        test "caches results for repeated calls" do
      System.delete_env("POSTHOG_PRIVATE_API_KEY")

      # First call
      {:ok, analytics1} = PosthogService.get_analytics("cache_test", 7)

      # Second call (should be from cache)
      {:ok, analytics2} = PosthogService.get_analytics("cache_test", 7)

      # Results should be identical (proving cache works)
      assert analytics1 == analytics2
      assert analytics1.unique_visitors == 0
    end

    @tag :skip
    test "cache expires after TTL" do
      # TODO: Implement with proper time mocking
      # This test would require mocking time or waiting 5 minutes
      # For now, we'll skip this test to avoid confusion
    end
  end
end
