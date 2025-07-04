defmodule EventasaurusWeb.Services.RecentLocationsCacheTest do
  use ExUnit.Case, async: true
  use EventasaurusApp.DataCase

  alias EventasaurusWeb.Services.RecentLocationsCache
  alias EventasaurusApp.{Events, Venues}

  import EventasaurusApp.Factory

  describe "RecentLocationsCache" do
    setup do
      # Start a test cache process
      {:ok, cache_pid} = start_supervised({RecentLocationsCache, [name: :test_cache, ttl: 1000]})

      # Create test data
      user = insert(:user)
      venue = insert(:venue)
      event = insert(:event, venue: venue)

      # Associate user with event
      insert(:event_user, event: event, user: user)

      %{
        user: user,
        venue: venue,
        event: event,
        cache_pid: cache_pid
      }
    end

    test "caches and retrieves recent locations successfully", %{user: user} do
      # First call should miss cache and fetch from database
      {:ok, locations_1} = RecentLocationsCache.get_recent_locations(user.id, limit: 5)

      # Second call should hit cache
      {:ok, locations_2} = RecentLocationsCache.get_recent_locations(user.id, limit: 5)

      # Should return same data
      assert locations_1 == locations_2
      assert length(locations_1) > 0

      # Check cache stats
      stats = RecentLocationsCache.get_stats()
      assert stats.hits >= 1
      assert stats.misses >= 1
    end

    test "handles cache key variations correctly", %{user: user} do
      # Different limits should create different cache keys
      {:ok, locations_3} = RecentLocationsCache.get_recent_locations(user.id, limit: 3)
      {:ok, locations_5} = RecentLocationsCache.get_recent_locations(user.id, limit: 5)

      # Should return different amounts
      assert length(locations_3) <= 3
      assert length(locations_5) <= 5
    end

    test "invalidates cache for specific user", %{user: user} do
      # Cache some data
      {:ok, _locations} = RecentLocationsCache.get_recent_locations(user.id, limit: 5)

      # Verify cache has data
      initial_stats = RecentLocationsCache.get_stats()
      assert initial_stats.cache_size > 0

      # Invalidate cache for user
      RecentLocationsCache.invalidate_user_cache(user.id)

      # Check cache size decreased
      final_stats = RecentLocationsCache.get_stats()
      assert final_stats.cache_size < initial_stats.cache_size
    end

    test "clears all cache", %{user: user} do
      # Cache some data
      {:ok, _locations} = RecentLocationsCache.get_recent_locations(user.id, limit: 5)

      # Clear all cache
      RecentLocationsCache.clear_cache()

      # Check cache is empty
      stats = RecentLocationsCache.get_stats()
      assert stats.cache_size == 0
    end

    test "handles cache misses gracefully", %{user: user} do
      # Kill the cache process to simulate failure
      Process.exit(Process.whereis(:test_cache), :kill)

      # Should still return data by falling back to database
      {:ok, locations} = RecentLocationsCache.get_recent_locations(user.id, limit: 5)
      assert is_list(locations)
    end

    test "cache expiration works correctly" do
      # Start cache with very short TTL
      {:ok, _pid} = start_supervised({RecentLocationsCache, [name: :short_ttl_cache, ttl: 10]})

      user = insert(:user)
      venue = insert(:venue)
      event = insert(:event, venue: venue)
      insert(:event_user, event: event, user: user)

      # Cache data
      {:ok, _locations} = RecentLocationsCache.get_recent_locations(user.id, limit: 5)

      # Wait for expiration
      Process.sleep(50)

      # Should have expired
      stats = RecentLocationsCache.get_stats()
      assert stats.evictions > 0
    end
  end

  describe "Performance comparison" do
    test "cache provides performance improvement" do
      user = insert(:user)

      # Create multiple events and venues for user
      for _i <- 1..10 do
        venue = insert(:venue)
        event = insert(:event, venue: venue)
        insert(:event_user, event: event, user: user)
      end

      # Measure direct database query time
      {db_time, _result} = :timer.tc(fn ->
        Events.get_recent_locations_for_user(user.id, limit: 5)
      end)

      # Measure cache miss time (first call)
      {cache_miss_time, _result} = :timer.tc(fn ->
        RecentLocationsCache.get_recent_locations(user.id, limit: 5)
      end)

      # Measure cache hit time (second call)
      {cache_hit_time, _result} = :timer.tc(fn ->
        RecentLocationsCache.get_recent_locations(user.id, limit: 5)
      end)

      # Cache hit should be significantly faster than database query
      assert cache_hit_time < db_time * 0.5  # At least 50% faster

      # Cache miss should be comparable to database query (small overhead)
      assert cache_miss_time < db_time * 1.5  # At most 50% slower due to cache overhead
    end
  end
end
