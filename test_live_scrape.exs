# Test Live Sortiraparis Scrape with Unknown Occurrence Implementation
# Direct synchronous scraping to test new transformer code

alias EventasaurusDiscovery.Sources.Sortiraparis.{Client, Transformer, ListingsFetcher}
alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor
alias EventasaurusApp.Repo

IO.puts("""
╔════════════════════════════════════════════════════════════════════════╗
║        Live Sortiraparis Scrape - Unknown Occurrence Test             ║
╚════════════════════════════════════════════════════════════════════════╝
""")

# Fetch event listings
IO.puts("\n🔍 Fetching Sortiraparis event listings...")

case ListingsFetcher.fetch_events() do
  {:ok, events} ->
    IO.puts("✅ Found #{length(events)} event listings")

    # Test first 5 events
    test_events = Enum.take(events, 5)

    IO.puts("\n🧪 Testing first 5 events with new transformer:\n")

    results = Enum.map(test_events, fn event_data ->
      url = event_data[:url]
      IO.puts("─────────────────────────────────────────────────────")
      IO.puts("Testing: #{event_data[:title]}")
      IO.puts("URL: #{url}")

      with {:ok, html} <- Client.fetch_page(url),
           {:ok, raw_event} <- EventExtractor.extract(html, url),
           {:ok, transformed} <- Transformer.transform_event(raw_event, %{}) do

        event = hd(transformed)
        occurrence_type = event.metadata["occurrence_type"]

        IO.puts("""

        ✅ Event transformed successfully
        ├─ Title: #{event.title}
        ├─ Occurrence Type: #{occurrence_type || "nil"}
        ├─ Original Date String: #{event.metadata["original_date_string"] || "N/A"}
        ├─ Starts At: #{if event.starts_at, do: DateTime.to_iso8601(event.starts_at), else: "nil"}
        ├─ Ends At: #{if event.ends_at, do: DateTime.to_iso8601(event.ends_at), else: "nil"}
        └─ Fallback Used: #{event.metadata["occurrence_fallback"] || "false"}
        """)

        {:ok, occurrence_type}
      else
        {:error, reason} ->
          IO.puts("\n❌ FAILED: #{inspect(reason)}")
          {:error, reason}
      end
    end)

    # Summary
    successes = Enum.count(results, fn {status, _} -> status == :ok end)
    failures = length(results) - successes

    unknown_count = Enum.count(results, fn
      {:ok, "unknown"} -> true
      _ -> false
    end)

    known_count = Enum.count(results, fn
      {:ok, type} when type in ["one_time", "recurring", "multi_day"] -> true
      _ -> false
    end)

    IO.puts("""

    ╔════════════════════════════════════════════════════════════════════════╗
    ║                          Test Results                                  ║
    ╚════════════════════════════════════════════════════════════════════════╝

    Total Tested: #{length(results)}
    ├─ ✅ Successes: #{successes}
    ├─ ❌ Failures: #{failures}
    ├─ 🔍 Unknown Occurrence: #{unknown_count}
    └─ 📅 Known Dates: #{known_count}

    Success Rate: #{Float.round(successes / length(results) * 100, 1)}%
    Unknown Rate: #{Float.round(unknown_count / length(results) * 100, 1)}%
    """)

  {:error, reason} ->
    IO.puts("❌ Failed to fetch listings: #{inspect(reason)}")
end

IO.puts("\n")
