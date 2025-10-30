defmodule EventasaurusWeb.SocialCardPerformanceTest do
  use EventasaurusWeb.ConnCase, async: false

  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusApp.Events
  alias EventasaurusApp.Polls
  alias EventasaurusApp.Geo

  @moduledoc """
  Performance benchmarking for social card generation.

  Targets:
  - First request (generation): < 500ms
  - Cached requests: < 50ms
  - Hash validation: < 10ms
  - Image size: < 200KB optimal, < 500KB acceptable

  Run with:
    mix test test/eventasaurus_web/controllers/social_card_performance_test.exs
  """

  describe "Event Social Card Performance" do
    setup do
      # Create test event
      event =
        insert(:event,
          title: "Performance Test Event",
          description: "Testing social card generation performance",
          slug: "perf-test-#{:rand.uniform(10000)}"
        )

      hash = HashGenerator.generate_hash(event, :event)
      {:ok, event: event, hash: hash}
    end

    test "first request generation time < 500ms", %{conn: conn, event: event, hash: hash} do
      {time_microseconds, response} =
        :timer.tc(fn ->
          get(conn, "/#{event.slug}/social-card-#{hash}.png")
        end)

      time_ms = time_microseconds / 1000

      assert response.status == 200

      assert time_ms < 500,
             "Generation took #{Float.round(time_ms, 2)}ms (target: <500ms)"

      IO.puts("\n  ⏱️  Event social card generation: #{Float.round(time_ms, 2)}ms")
    end

    test "cached request time < 50ms", %{conn: conn, event: event, hash: hash} do
      # Warm up cache
      get(conn, "/#{event.slug}/social-card-#{hash}.png")

      # Measure cached request
      {time_microseconds, response} =
        :timer.tc(fn ->
          get(conn, "/#{event.slug}/social-card-#{hash}.png")
        end)

      time_ms = time_microseconds / 1000

      assert response.status == 200
      assert time_ms < 50, "Cached request took #{Float.round(time_ms, 2)}ms (target: <50ms)"

      IO.puts("  ⚡ Event cached request: #{Float.round(time_ms, 2)}ms")
    end

    test "generated image size < 500KB", %{conn: conn, event: event, hash: hash} do
      response = get(conn, "/#{event.slug}/social-card-#{hash}.png")

      assert response.status == 200

      size_bytes = byte_size(response.resp_body)
      size_kb = size_bytes / 1024

      assert size_kb < 500, "Image size #{Float.round(size_kb, 2)}KB (target: <500KB)"

      # Warn if over optimal size
      if size_kb > 200 do
        IO.puts(
          "  ⚠️  Image size #{Float.round(size_kb, 2)}KB (optimal: <200KB, acceptable: <500KB)"
        )
      else
        IO.puts("  ✅ Image size #{Float.round(size_kb, 2)}KB (optimal)")
      end
    end

    test "hash validation time < 10ms", %{event: event, hash: hash} do
      {time_microseconds, result} =
        :timer.tc(fn ->
          HashGenerator.validate_hash(event, hash, :event)
        end)

      time_ms = time_microseconds / 1000

      assert result == true
      assert time_ms < 10, "Hash validation took #{Float.round(time_ms, 2)}ms (target: <10ms)"

      IO.puts("  🔍 Hash validation: #{Float.round(time_ms, 2)}ms")
    end

    test "hash generation time < 5ms", %{event: event} do
      {time_microseconds, hash} =
        :timer.tc(fn ->
          HashGenerator.generate_hash(event, :event)
        end)

      time_ms = time_microseconds / 1000

      assert is_binary(hash)
      assert String.length(hash) == 8
      assert time_ms < 5, "Hash generation took #{Float.round(time_ms, 2)}ms (target: <5ms)"

      IO.puts("  #️⃣  Hash generation: #{Float.round(time_ms, 2)}ms")
    end

    test "concurrent requests don't degrade performance", %{conn: conn, event: event, hash: hash} do
      # Make 10 concurrent requests
      parent = self()

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(EventasaurusApp.Repo, parent, self())

            {time, response} =
              :timer.tc(fn ->
                get(conn, "/#{event.slug}/social-card-#{hash}.png")
              end)

            {time / 1000, response.status}
          end)
        end

      results = Task.await_many(tasks, 30_000)

      # All should succeed
      assert Enum.all?(results, fn {_time, status} -> status == 200 end)

      # Average time should still be reasonable
      avg_time =
        results
        |> Enum.map(fn {time, _status} -> time end)
        |> Enum.sum()
        |> Kernel./(10)

      assert avg_time < 1000,
             "Average concurrent request time: #{Float.round(avg_time, 2)}ms (target: <1000ms)"

      IO.puts("  🔀 Concurrent requests average: #{Float.round(avg_time, 2)}ms (10 requests)")
    end
  end

  describe "Poll Social Card Performance" do
    setup do
      event = insert(:event, slug: "poll-perf-test-#{:rand.uniform(10000)}")
      poll = insert(:poll, event: event, poll_number: :rand.uniform(100))
      hash = HashGenerator.generate_hash(poll, :poll)

      {:ok, event: event, poll: poll, hash: hash}
    end

    test "first request generation time < 500ms", %{
      conn: conn,
      event: event,
      poll: poll,
      hash: hash
    } do
      {time_microseconds, response} =
        :timer.tc(fn ->
          get(conn, "/#{event.slug}/polls/#{poll.poll_number}/social-card-#{hash}.png")
        end)

      time_ms = time_microseconds / 1000

      assert response.status == 200

      assert time_ms < 500,
             "Generation took #{Float.round(time_ms, 2)}ms (target: <500ms)"

      IO.puts("\n  ⏱️  Poll social card generation: #{Float.round(time_ms, 2)}ms")
    end

    test "generated image size < 500KB", %{conn: conn, event: event, poll: poll, hash: hash} do
      response = get(conn, "/#{event.slug}/polls/#{poll.poll_number}/social-card-#{hash}.png")

      assert response.status == 200

      size_bytes = byte_size(response.resp_body)
      size_kb = size_bytes / 1024

      assert size_kb < 500, "Image size #{Float.round(size_kb, 2)}KB (target: <500KB)"

      if size_kb > 200 do
        IO.puts("  ⚠️  Image size #{Float.round(size_kb, 2)}KB (optimal: <200KB)")
      else
        IO.puts("  ✅ Image size #{Float.round(size_kb, 2)}KB (optimal)")
      end
    end
  end

  describe "City Social Card Performance" do
    setup do
      city = insert(:city, slug: "city-perf-test-#{:rand.uniform(10000)}")

      # Add stats for realistic testing
      city_with_stats = %{
        city
        | stats: %{
            events_count: 150,
            venues_count: 45,
            categories_count: 12
          }
      }

      hash = HashGenerator.generate_hash(city_with_stats, :city)

      {:ok, city: city_with_stats, hash: hash}
    end

    test "first request generation time < 500ms", %{conn: conn, city: city, hash: hash} do
      {time_microseconds, response} =
        :timer.tc(fn ->
          get(conn, "/social-cards/city/#{city.slug}/#{hash}.png")
        end)

      time_ms = time_microseconds / 1000

      assert response.status == 200

      assert time_ms < 500,
             "Generation took #{Float.round(time_ms, 2)}ms (target: <500ms)"

      IO.puts("\n  ⏱️  City social card generation: #{Float.round(time_ms, 2)}ms")
    end

    test "generated image size < 500KB", %{conn: conn, city: city, hash: hash} do
      response = get(conn, "/social-cards/city/#{city.slug}/#{hash}.png")

      assert response.status == 200

      size_bytes = byte_size(response.resp_body)
      size_kb = size_bytes / 1024

      assert size_kb < 500, "Image size #{Float.round(size_kb, 2)}KB (target: <500KB)"

      if size_kb > 200 do
        IO.puts("  ⚠️  Image size #{Float.round(size_kb, 2)}KB (optimal: <200KB)")
      else
        IO.puts("  ✅ Image size #{Float.round(size_kb, 2)}KB (optimal)")
      end
    end
  end

  describe "Hash Mismatch Redirect Performance" do
    setup do
      event = insert(:event, slug: "redirect-perf-test-#{:rand.uniform(10000)}")
      hash = HashGenerator.generate_hash(event, :event)
      {:ok, event: event, hash: hash}
    end

    test "redirect response time < 100ms", %{conn: conn, event: event} do
      wrong_hash = "wrong123"

      {time_microseconds, response} =
        :timer.tc(fn ->
          get(conn, "/#{event.slug}/social-card-#{wrong_hash}.png")
        end)

      time_ms = time_microseconds / 1000

      assert redirected_to(response, 301) =~ "social-card-"
      assert time_ms < 100, "Redirect took #{Float.round(time_ms, 2)}ms (target: <100ms)"

      IO.puts("\n  🔄 Hash mismatch redirect: #{Float.round(time_ms, 2)}ms")
    end
  end

  describe "Memory Usage" do
    test "generation doesn't leak memory" do
      event = insert(:event, slug: "memory-test-#{:rand.uniform(10000)}")
      hash = HashGenerator.generate_hash(event, :event)

      # Get initial memory
      initial_memory = :erlang.memory(:total)

      # Generate 100 social cards
      for _ <- 1..100 do
        conn = build_conn()
        get(conn, "/#{event.slug}/social-card-#{hash}.png")
      end

      # Force garbage collection
      :erlang.garbage_collect()

      # Check final memory
      final_memory = :erlang.memory(:total)

      memory_diff_mb = (final_memory - initial_memory) / (1024 * 1024)

      # Memory should not increase by more than 50MB
      assert memory_diff_mb < 50,
             "Memory increased by #{Float.round(memory_diff_mb, 2)}MB (target: <50MB)"

      IO.puts("\n  💾 Memory increase after 100 generations: #{Float.round(memory_diff_mb, 2)}MB")
    end
  end

  describe "Error Handling Performance" do
    test "404 response for missing event is fast", %{conn: conn} do
      {time_microseconds, response} =
        :timer.tc(fn ->
          get(conn, "/nonexistent-event/social-card-abc12345.png")
        end)

      time_ms = time_microseconds / 1000

      assert response.status == 404
      assert time_ms < 50, "404 response took #{Float.round(time_ms, 2)}ms (target: <50ms)"

      IO.puts("\n  🚫 404 response time: #{Float.round(time_ms, 2)}ms")
    end
  end

  describe "Stress Testing" do
    @tag :stress
    test "handles 1000 sequential requests without degradation" do
      event = insert(:event, slug: "stress-test-#{:rand.uniform(10000)}")
      hash = HashGenerator.generate_hash(event, :event)

      times =
        for i <- 1..1000 do
          conn = build_conn()

          {time, response} =
            :timer.tc(fn ->
              get(conn, "/#{event.slug}/social-card-#{hash}.png")
            end)

          if rem(i, 100) == 0 do
            IO.write(".")
          end

          assert response.status == 200
          time / 1000
        end

      IO.puts("")

      avg_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)
      min_time = Enum.min(times)

      IO.puts("\n  📊 Stress Test Results (1000 requests):")
      IO.puts("    Average: #{Float.round(avg_time, 2)}ms")
      IO.puts("    Min: #{Float.round(min_time, 2)}ms")
      IO.puts("    Max: #{Float.round(max_time, 2)}ms")

      # Average should stay reasonable
      assert avg_time < 500, "Average time degraded to #{Float.round(avg_time, 2)}ms"
    end
  end

  describe "Performance Summary Report" do
    test "generate performance report" do
      IO.puts("\n")
      IO.puts("=" |> String.duplicate(70))
      IO.puts("📊 SOCIAL CARD PERFORMANCE REPORT")
      IO.puts("=" |> String.duplicate(70))

      # Event card
      event = insert(:event, slug: "report-event-#{:rand.uniform(10000)}")
      event_hash = HashGenerator.generate_hash(event, :event)
      conn = build_conn()

      {event_gen_time, event_response} =
        :timer.tc(fn -> get(conn, "/#{event.slug}/social-card-#{event_hash}.png") end)

      {event_cached_time, _} =
        :timer.tc(fn -> get(conn, "/#{event.slug}/social-card-#{event_hash}.png") end)

      event_size_kb = byte_size(event_response.resp_body) / 1024

      IO.puts("\n📅 Event Social Cards:")
      IO.puts("  Generation Time: #{Float.round(event_gen_time / 1000, 2)}ms")
      IO.puts("  Cached Time: #{Float.round(event_cached_time / 1000, 2)}ms")
      IO.puts("  Image Size: #{Float.round(event_size_kb, 2)}KB")
      IO.puts("  Status: #{if event_gen_time / 1000 < 500, do: "✅ PASS", else: "❌ FAIL"}")

      # Poll card
      poll_event = insert(:event, slug: "report-poll-event-#{:rand.uniform(10000)}")
      poll = insert(:poll, event: poll_event, poll_number: 1)
      poll_hash = HashGenerator.generate_hash(poll, :poll)

      {poll_gen_time, poll_response} =
        :timer.tc(fn ->
          get(conn, "/#{poll_event.slug}/polls/#{poll.poll_number}/social-card-#{poll_hash}.png")
        end)

      poll_size_kb = byte_size(poll_response.resp_body) / 1024

      IO.puts("\n📊 Poll Social Cards:")
      IO.puts("  Generation Time: #{Float.round(poll_gen_time / 1000, 2)}ms")
      IO.puts("  Image Size: #{Float.round(poll_size_kb, 2)}KB")
      IO.puts("  Status: #{if poll_gen_time / 1000 < 500, do: "✅ PASS", else: "❌ FAIL"}")

      # City card
      city = insert(:city, slug: "report-city-#{:rand.uniform(10000)}")

      city_with_stats = %{
        city
        | stats: %{events_count: 100, venues_count: 30, categories_count: 10}
      }

      city_hash = HashGenerator.generate_hash(city_with_stats, :city)

      {city_gen_time, city_response} =
        :timer.tc(fn -> get(conn, "/social-cards/city/#{city.slug}/#{city_hash}.png") end)

      city_size_kb = byte_size(city_response.resp_body) / 1024

      IO.puts("\n🏙️  City Social Cards:")
      IO.puts("  Generation Time: #{Float.round(city_gen_time / 1000, 2)}ms")
      IO.puts("  Image Size: #{Float.round(city_size_kb, 2)}KB")
      IO.puts("  Status: #{if city_gen_time / 1000 < 500, do: "✅ PASS", else: "❌ FAIL"}")

      # Hash operations
      {hash_gen_time, _} = :timer.tc(fn -> HashGenerator.generate_hash(event, :event) end)

      {hash_val_time, _} =
        :timer.tc(fn -> HashGenerator.validate_hash(event, event_hash, :event) end)

      IO.puts("\n🔐 Hash Operations:")
      IO.puts("  Generation Time: #{Float.round(hash_gen_time / 1000, 2)}ms")
      IO.puts("  Validation Time: #{Float.round(hash_val_time / 1000, 2)}ms")

      IO.puts(
        "  Status: #{if hash_gen_time / 1000 < 5 and hash_val_time / 1000 < 10, do: "✅ PASS", else: "❌ FAIL"}"
      )

      IO.puts("\n" <> ("=" |> String.duplicate(70)))
      IO.puts("✅ Performance Report Complete")
      IO.puts("=" |> String.duplicate(70))
      IO.puts("")
    end
  end
end
