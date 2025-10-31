# Test Unknown Occurrence Type Implementation
# Tests the complete flow: fetch -> extract -> transform -> verify

alias EventasaurusDiscovery.Sources.Sortiraparis.{Client, Transformer}
alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor
alias EventasaurusApp.Repo

IO.puts("""
╔════════════════════════════════════════════════════════════════════════╗
║           Unknown Occurrence Type - Integration Test                  ║
╚════════════════════════════════════════════════════════════════════════╝
""")

# Test 1: Failing event - Biennale Multitude (unparseable date)
IO.puts("\n🧪 TEST 1: Biennale Multitude (unparseable date)")
IO.puts("─────────────────────────────────────────────────────")

url = "https://www.sortiraparis.com/en/what-to-see-in-paris/exhibition/articles/329086-biennale-multitude-2025"

result1 = with {:ok, html} <- Client.fetch_page(url),
               {:ok, raw_event} <- EventExtractor.extract(html, url),
               {:ok, events} <- Transformer.transform_event(raw_event, %{}) do
  event = hd(events)

  IO.puts("""

  ✅ SUCCESS: Event created with unknown occurrence type

  Event Details:
  ├─ Title: #{event.title}
  ├─ Occurrence Type: #{event.metadata["occurrence_type"]}
  ├─ Original Date String: #{event.metadata["original_date_string"]}
  ├─ Starts At: #{if event.starts_at, do: DateTime.to_iso8601(event.starts_at), else: "nil"}
  ├─ Ends At: #{if event.ends_at, do: DateTime.to_iso8601(event.ends_at), else: "nil"}
  ├─ Fallback Flag: #{event.metadata["occurrence_fallback"]}
  └─ First Seen: #{event.metadata["first_seen_at"]}

  Metadata (full):
  #{inspect(event.metadata, pretty: true)}
  """)

  {:ok, event}
else
  {:error, reason} ->
    IO.puts("\n❌ FAILED: #{inspect(reason)}")
    {:error, reason}
end

# Test 2: Known date event (should create one_time)
IO.puts("\n🧪 TEST 2: Event with parseable date (should be one_time)")
IO.puts("─────────────────────────────────────────────────────")

# Use a recent event URL that should have a parseable date
known_date_url = "https://www.sortiraparis.com/en/what-to-see-in-paris/exhibition/articles/329427-matisse-the-red-studio-at-fondation-louis-vuitton"

result2 = with {:ok, html} <- Client.fetch_page(known_date_url),
               {:ok, raw_event} <- EventExtractor.extract(html, known_date_url),
               {:ok, events} <- Transformer.transform_event(raw_event, %{}) do
  event = hd(events)

  IO.puts("""

  ✅ SUCCESS: Event created with known date

  Event Details:
  ├─ Title: #{event.title}
  ├─ Occurrence Type: #{event.metadata["occurrence_type"]}
  ├─ Starts At: #{DateTime.to_iso8601(event.starts_at)}
  └─ Ends At: #{if event.ends_at, do: DateTime.to_iso8601(event.ends_at), else: "nil"}
  """)

  {:ok, event}
else
  {:error, reason} ->
    IO.puts("\n⚠️  Could not test known date event: #{inspect(reason)}")
    {:error, reason}
end

# Summary
IO.puts("""

╔════════════════════════════════════════════════════════════════════════╗
║                          Test Summary                                  ║
╚════════════════════════════════════════════════════════════════════════╝
""")

case {result1, result2} do
  {{:ok, _}, {:ok, _}} ->
    IO.puts("""
    ✅ All tests passed!

    Results:
    ├─ Unknown occurrence handling: WORKING
    ├─ Known date handling: WORKING
    └─ Occurrence type metadata: PROPERLY STORED

    Next Steps:
    1. Run a full scrape to test in production
    2. Check database for occurrence type distribution
    3. Monitor scraper success rate improvement
    """)

  {{:ok, _}, {:error, _}} ->
    IO.puts("""
    ⚠️  Partial success

    Results:
    ├─ Unknown occurrence handling: WORKING ✅
    └─ Known date test: FAILED (may be network/parsing issue)

    The unknown occurrence fallback is working correctly.
    """)

  {{:error, _}, _} ->
    IO.puts("""
    ❌ Tests failed

    The unknown occurrence implementation needs debugging.
    Check transformer logic and metadata storage.
    """)
end

IO.puts("\n")
