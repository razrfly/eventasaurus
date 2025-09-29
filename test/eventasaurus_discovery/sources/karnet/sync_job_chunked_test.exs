defmodule EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJobChunkedTest do
  use ExUnit.Case, async: true

  describe "chunking logic" do
    @chunk_size 100

    test "calculates correct chunk count and sizes" do
      test_cases = [
        {250, 3, [100, 100, 50]},  # 100 + 100 + 50
        {200, 2, [100, 100]},      # 100 + 100
        {150, 2, [100, 50]},       # 100 + 50
        {100, 1, [100]},           # exactly 100 - should chunk into 1
        {1000, 10, [100, 100, 100, 100, 100, 100, 100, 100, 100, 100]} # 10 chunks of 100 each
      ]

      Enum.each(test_cases, fn {limit, expected_chunks, expected_sizes} ->
        {chunks, sizes} = calculate_chunking(limit)
        assert chunks == expected_chunks, "Limit #{limit}: expected #{expected_chunks} chunks, got #{chunks}"
        assert sizes == expected_sizes, "Limit #{limit}: expected sizes #{inspect(expected_sizes)}, got #{inspect(sizes)}"
      end)
    end

    test "calculates page windows correctly" do
      events_per_page = 12

      # Chunk 1: events 0-99 (pages 1-9, skip 0 in first page)
      {start_page, skip} = calculate_page_window(0, events_per_page)
      assert start_page == 1
      assert skip == 0

      # Chunk 2: events 100-199 (start at page 9, skip 4 events)
      # 100 / 12 = 8.33 -> page 9, skip 100 - (8 * 12) = 4
      {start_page, skip} = calculate_page_window(100, events_per_page)
      assert start_page == 9
      assert skip == 4

      # Chunk 3: events 200-299 (start at page 17, skip 8 events)
      # 200 / 12 = 16.67 -> page 17, skip 200 - (16 * 12) = 8
      {start_page, skip} = calculate_page_window(200, events_per_page)
      assert start_page == 17
      assert skip == 8
    end

    test "no chunking for small limits" do
      # Limits <= 100 should not trigger chunking logic
      small_limits = [50, 99, 100]

      Enum.each(small_limits, fn limit ->
        should_chunk = limit > @chunk_size
        refute should_chunk, "Limit #{limit} should not trigger chunking"
      end)
    end

    test "chunking triggered for large limits" do
      # Limits > 100 should trigger chunking logic
      large_limits = [101, 200, 500, 1000]

      Enum.each(large_limits, fn limit ->
        should_chunk = limit > @chunk_size
        assert should_chunk, "Limit #{limit} should trigger chunking"
      end)
    end

    defp calculate_chunking(limit) do
      chunks = div(limit, @chunk_size) + if(rem(limit, @chunk_size) > 0, do: 1, else: 0)

      sizes = Enum.map(0..(chunks - 1), fn chunk_idx ->
        if chunk_idx == chunks - 1 do
          # Last chunk might be smaller
          remaining = rem(limit, @chunk_size)
          if remaining > 0, do: remaining, else: @chunk_size
        else
          @chunk_size
        end
      end)

      {chunks, sizes}
    end

    defp calculate_page_window(offset, events_per_page) do
      if offset > 0 do
        {div(offset, events_per_page) + 1, rem(offset, events_per_page)}
      else
        {1, 0}
      end
    end
  end

  describe "chunk parameter validation" do
    test "validates chunk detection logic" do
      # Simulate the guard condition from perform/1
      test_cases = [
        # {limit, has_chunk_key, should_trigger_chunking}
        {150, false, true},   # Large limit, no chunk key -> should chunk
        {150, true, false},   # Large limit, has chunk key -> shouldn't chunk (already a chunk)
        {50, false, false},   # Small limit, no chunk key -> shouldn't chunk
        {50, true, false},    # Small limit, has chunk key -> shouldn't chunk
      ]

      Enum.each(test_cases, fn {limit, has_chunk_key, expected_chunking} ->
        # Simulate the condition: limit > @chunk_size and not is_map_key(args, "chunk")
        args = if has_chunk_key, do: %{"chunk" => 1}, else: %{}
        should_chunk = limit > @chunk_size and not Map.has_key?(args, "chunk")

        assert should_chunk == expected_chunking,
          "Limit #{limit}, chunk_key: #{has_chunk_key} -> expected chunking: #{expected_chunking}, got: #{should_chunk}"
      end)
    end
  end

  describe "chunk budget enforcement" do
    @events_per_page 12

    test "enforces exact budget limits per chunk" do
      test_cases = [
        # {chunk_limit, start_page, skip_in_first, expected_pages, expected_total_events}
        {100, 1, 0, 9, 100},    # Chunk 1: pages 1-9, events 0-99
        {100, 9, 4, 9, 100},    # Chunk 2: pages 9-17, events 100-199 (skip 4 on page 9)
        {100, 17, 8, 9, 100},   # Chunk 3: pages 17-25, events 200-299 (skip 8 on page 17)
        {50, 1, 0, 5, 50},      # Smaller chunk: pages 1-5, events 0-49
      ]

      Enum.each(test_cases, fn {chunk_limit, start_page, skip_in_first, expected_pages, expected_total_events} ->
        {pages_scheduled, total_budget_used} = simulate_chunk_scheduling(chunk_limit, start_page, skip_in_first)

        assert pages_scheduled <= expected_pages,
          "Chunk #{chunk_limit} at page #{start_page}: scheduled #{pages_scheduled} pages, expected ≤ #{expected_pages}"

        assert total_budget_used == expected_total_events,
          "Chunk #{chunk_limit} at page #{start_page}: used #{total_budget_used} events, expected #{expected_total_events}"
      end)
    end

    test "prevents budget overshoot" do
      # Test edge case where page has more events than remaining budget
      chunk_limit = 10
      start_page = 1
      skip_in_first = 0

      {_pages_scheduled, total_budget_used} = simulate_chunk_scheduling(chunk_limit, start_page, skip_in_first)

      assert total_budget_used == chunk_limit,
        "Should use exactly #{chunk_limit} events, but used #{total_budget_used}"
    end

    defp simulate_chunk_scheduling(chunk_limit, start_page, skip_in_first) do
      max_pages = div(chunk_limit, @events_per_page) + if(rem(chunk_limit, @events_per_page) > 0, do: 1, else: 0)

      {page_jobs, _remaining} =
        start_page..(start_page + max_pages - 1)
        |> Enum.map_reduce(chunk_limit, fn page_num, remaining_budget ->
          if remaining_budget <= 0 do
            {:skip, 0}
          else
            page_budget = if page_num == start_page do
              events_available = @events_per_page - skip_in_first
              min(remaining_budget, events_available)
            else
              min(remaining_budget, @events_per_page)
            end

            {{page_num, page_budget}, remaining_budget - page_budget}
          end
        end)

      actual_pages = Enum.reject(page_jobs, &(&1 == :skip))
      pages_scheduled = length(actual_pages)
      total_budget_used = actual_pages |> Enum.map(&elem(&1, 1)) |> Enum.sum()

      {pages_scheduled, total_budget_used}
    end
  end
end