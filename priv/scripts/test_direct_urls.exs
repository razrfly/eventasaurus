# Test Direct Sortiraparis URLs with Unknown Occurrence Implementation

alias EventasaurusDiscovery.Sources.Sortiraparis.{Client, Transformer}
alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor

IO.puts("""
╔════════════════════════════════════════════════════════════════════════╗
║     Direct URL Test - Unknown Occurrence Implementation                ║
╚════════════════════════════════════════════════════════════════════════╝
""")

# Test URLs - mix of events with parseable and unparseable dates
test_urls = [
  # This one has the unparseable "du 19 mars au 7 juillet 2025" format
  "https://www.sortiraparis.com/en/what-to-see-in-paris/exhibition/articles/329086-biennale-multitude-2025",

  # Try some current events
  "https://www.sortiraparis.com/en/what-to-see-in-paris/exhibition/articles/329427-matisse-the-red-studio-at-fondation-louis-vuitton",
  "https://www.sortiraparis.com/en/arts-culture/shows/articles/328976-cirque-phenix-2024-2025-the-program",
]

results = Enum.map(test_urls, fn url ->
  IO.puts("\n" <> String.duplicate("─", 72))
  IO.puts("Testing: #{url}")

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
    ├─ Starts At: #{DateTime.to_iso8601(event.starts_at)}
    ├─ Ends At: #{if event.ends_at, do: DateTime.to_iso8601(event.ends_at), else: "nil"}
    └─ Fallback Used: #{event.metadata["occurrence_fallback"] || "false"}

    Metadata (occurrence-related):
    #{inspect(Map.take(event.metadata, ["occurrence_type", "original_date_string", "occurrence_fallback", "first_seen_at"]), pretty: true)}
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

nil_count = Enum.count(results, fn
  {:ok, nil} -> true
  _ -> false
end)

IO.puts("""

╔════════════════════════════════════════════════════════════════════════╗
║                          Test Summary                                  ║
╚════════════════════════════════════════════════════════════════════════╝

Total Tested: #{length(results)}
├─ ✅ Transformations Successful: #{successes}
├─ ❌ Transformations Failed: #{failures}
│
├─ Occurrence Type Distribution:
│  ├─ 🔍 Unknown: #{unknown_count}
│  ├─ 📅 Known (one_time/recurring/multi_day): #{known_count}
│  └─ ❓ Nil: #{nil_count}
│
├─ Success Rate: #{Float.round(successes / length(results) * 100, 1)}%
└─ Unknown Rate: #{Float.round(unknown_count / length(results) * 100, 1)}%

Expected Results:
- Biennale event should have occurrence_type = "unknown"
- Other events should have known occurrence types (one_time, multi_day, etc.)
- All events should have occurrence_fallback = "true" or "false" indicating if fallback was used
""")

IO.puts("\n")
