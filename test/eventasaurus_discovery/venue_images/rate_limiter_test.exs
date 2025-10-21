defmodule EventasaurusDiscovery.VenueImages.RateLimiterTest do
  use ExUnit.Case, async: false

  alias EventasaurusDiscovery.VenueImages.RateLimiter

  setup do
    # Reset rate limiter state between tests
    RateLimiter.reset_limits("test_provider")
    :ok
  end

  describe "check_rate_limit/1" do
    test "allows request when no rate limits configured" do
      provider = %{
        name: "test_provider",
        metadata: %{}
      }

      assert RateLimiter.check_rate_limit(provider) == :ok
    end

    test "allows request when under per_second limit" do
      provider = %{
        name: "test_provider",
        metadata: %{
          "rate_limits" => %{
            "per_second" => 10
          }
        }
      }

      # Make 5 requests - should all pass
      for _ <- 1..5 do
        RateLimiter.record_request("test_provider")
      end

      assert RateLimiter.check_rate_limit(provider) == :ok
    end

    test "blocks request when per_second limit exceeded" do
      provider = %{
        name: "test_provider",
        metadata: %{
          "rate_limits" => %{
            "per_second" => 5
          }
        }
      }

      # Make 5 requests to hit limit
      for _ <- 1..5 do
        RateLimiter.record_request("test_provider")
      end

      # Next check should fail
      assert RateLimiter.check_rate_limit(provider) == {:error, :rate_limited}
    end

    test "allows request when under per_minute limit" do
      provider = %{
        name: "test_provider",
        metadata: %{
          "rate_limits" => %{
            "per_minute" => 100
          }
        }
      }

      # Make 50 requests - should pass
      for _ <- 1..50 do
        RateLimiter.record_request("test_provider")
      end

      assert RateLimiter.check_rate_limit(provider) == :ok
    end

    test "blocks request when per_minute limit exceeded" do
      provider = %{
        name: "test_provider",
        metadata: %{
          "rate_limits" => %{
            "per_minute" => 10
          }
        }
      }

      # Make 10 requests to hit limit
      for _ <- 1..10 do
        RateLimiter.record_request("test_provider")
      end

      # Next check should fail
      assert RateLimiter.check_rate_limit(provider) == {:error, :rate_limited}
    end

    test "checks all configured limits" do
      provider = %{
        name: "test_provider",
        metadata: %{
          "rate_limits" => %{
            "per_second" => 5,
            "per_minute" => 100,
            "per_hour" => 1000
          }
        }
      }

      # Make 3 requests - all limits should pass
      for _ <- 1..3 do
        RateLimiter.record_request("test_provider")
      end

      assert RateLimiter.check_rate_limit(provider) == :ok
    end

    test "fails on first exceeded limit" do
      provider = %{
        name: "test_provider",
        metadata: %{
          "rate_limits" => %{
            "per_second" => 3,
            "per_minute" => 1000
          }
        }
      }

      # Make 3 requests to hit per_second limit
      for _ <- 1..3 do
        RateLimiter.record_request("test_provider")
      end

      # Should fail on per_second even though per_minute is fine
      assert RateLimiter.check_rate_limit(provider) == {:error, :rate_limited}
    end
  end

  describe "get_stats/1" do
    test "returns zero counts for new provider" do
      stats = RateLimiter.get_stats("new_provider")

      assert stats.last_second == 0
      assert stats.last_minute == 0
      assert stats.last_hour == 0
    end

    test "tracks requests in last second" do
      for _ <- 1..5 do
        RateLimiter.record_request("test_provider")
      end

      stats = RateLimiter.get_stats("test_provider")
      assert stats.last_second == 5
    end

    test "tracks requests in last minute" do
      for _ <- 1..10 do
        RateLimiter.record_request("test_provider")
      end

      stats = RateLimiter.get_stats("test_provider")
      assert stats.last_minute == 10
    end

    test "tracks requests in last hour" do
      for _ <- 1..25 do
        RateLimiter.record_request("test_provider")
      end

      stats = RateLimiter.get_stats("test_provider")
      assert stats.last_hour == 25
    end
  end

  describe "reset_limits/1" do
    test "clears all request history for provider" do
      # Make some requests
      for _ <- 1..10 do
        RateLimiter.record_request("test_provider")
      end

      # Verify requests were recorded
      stats_before = RateLimiter.get_stats("test_provider")
      assert stats_before.last_second > 0

      # Reset
      RateLimiter.reset_limits("test_provider")

      # Verify reset
      stats_after = RateLimiter.get_stats("test_provider")
      assert stats_after.last_second == 0
      assert stats_after.last_minute == 0
      assert stats_after.last_hour == 0
    end
  end

  describe "record_request/1" do
    test "increments request count" do
      stats_before = RateLimiter.get_stats("test_provider")
      assert stats_before.last_second == 0

      RateLimiter.record_request("test_provider")

      stats_after = RateLimiter.get_stats("test_provider")
      assert stats_after.last_second == 1
    end

    test "handles multiple concurrent requests" do
      # Simulate concurrent requests
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            RateLimiter.record_request("test_provider")
          end)
        end

      Task.await_many(tasks)

      stats = RateLimiter.get_stats("test_provider")
      assert stats.last_second == 20
    end
  end
end
