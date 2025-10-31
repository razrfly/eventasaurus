#!/usr/bin/env elixir

# Test script to investigate why 54% of bilingual fetches fail
# Manually tests French page fetches for events that don't have French translations

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.PublicEvents.PublicEventSource
alias EventasaurusDiscovery.Sources.Source
alias EventasaurusDiscovery.Sources.Sortiraparis.Client
alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor

import Ecto.Query

IO.puts("\n🔍 Testing French Page Fetch Failures\n")
IO.puts("=" <> String.duplicate("=", 79))

# Get events with English URLs that are missing French translations
query = from pes in PublicEventSource,
  join: s in Source, on: s.id == pes.source_id,
  where: s.slug == "sortiraparis",
  where: fragment("source_url LIKE ?", "%/en/%"),
  where: not fragment("description_translations \\? ?", "fr"),
  select: %{
    id: pes.id,
    source_url: pes.source_url
  },
  limit: 10

failed_events = Repo.all(query)

IO.puts("\n📊 Found #{length(failed_events)} events with English URLs missing French translations")
IO.puts("Testing first 10...\n")

# Test each failed event
results = Enum.map(failed_events, fn event ->
  en_url = event.source_url
  fr_url = String.replace(en_url, "/en/", "/")

  IO.puts("\n#{String.duplicate("-", 80)}")
  IO.puts("Event ID: #{event.id}")
  IO.puts("EN URL: #{en_url}")
  IO.puts("FR URL: #{fr_url}")

  # Test French page fetch
  fetch_result = case Client.fetch_page(fr_url) do
    {:ok, html} ->
      IO.puts("✅ Fetch succeeded (#{byte_size(html)} bytes)")

      # Try extracting event data
      case EventExtractor.extract(html, fr_url) do
        {:ok, event_data} ->
          description = event_data["description"]
          desc_length = if description, do: String.length(description), else: 0
          IO.puts("✅ Extraction succeeded")
          IO.puts("   Description length: #{desc_length} chars")
          IO.puts("   Description preview: #{String.slice(description || "", 0..100)}...")
          {:success, :extracted, desc_length}

        {:error, reason} ->
          IO.puts("❌ Extraction failed: #{inspect(reason)}")
          {:success, :extraction_failed, reason}
      end

    {:error, :bot_protection} ->
      IO.puts("🚫 Bot protection (401)")
      {:failed, :bot_protection}

    {:error, :not_found} ->
      IO.puts("❌ Page not found (404)")
      {:failed, :not_found}

    {:error, :timeout} ->
      IO.puts("⏱️ Timeout")
      {:failed, :timeout}

    {:error, reason} ->
      IO.puts("❌ Fetch failed: #{inspect(reason)}")
      {:failed, reason}
  end

  # Sleep to respect rate limiting
  Process.sleep(5000)

  {event.id, fetch_result}
end)

# Analyze results
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("📊 RESULTS SUMMARY\n")

success_count = Enum.count(results, fn {_, {status, _, _}} -> status == :success end)
bot_protection_count = Enum.count(results, fn {_, {_, reason}} -> reason == :bot_protection end)
not_found_count = Enum.count(results, fn {_, {_, reason}} -> reason == :not_found end)
timeout_count = Enum.count(results, fn {_, {_, reason}} -> reason == :timeout end)
extraction_failed_count = Enum.count(results, fn {_, {_, reason, _}} -> reason == :extraction_failed end)
extracted_count = Enum.count(results, fn {_, {_, reason, _}} -> reason == :extracted end)

IO.puts("Total tested: #{length(results)}")
IO.puts("\nFetch Results:")
IO.puts("  ✅ Fetch succeeded: #{success_count}")
IO.puts("  🚫 Bot protection (401): #{bot_protection_count}")
IO.puts("  ❌ Not found (404): #{not_found_count}")
IO.puts("  ⏱️ Timeout: #{timeout_count}")

IO.puts("\nExtraction Results (for successful fetches):")
IO.puts("  ✅ Extracted successfully: #{extracted_count}")
IO.puts("  ❌ Extraction failed: #{extraction_failed_count}")

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("🔍 ANALYSIS\n")

cond do
  bot_protection_count > length(results) * 0.5 ->
    IO.puts("⚠️  PRIMARY ISSUE: Bot Protection (401)")
    IO.puts("   > 50% of requests blocked by bot protection")
    IO.puts("   Recommendation: Implement Playwright fallback for French pages")

  not_found_count > length(results) * 0.5 ->
    IO.puts("⚠️  PRIMARY ISSUE: French Pages Don't Exist (404)")
    IO.puts("   > 50% of French URLs return 404")
    IO.puts("   Recommendation: Some articles may not have French versions")

  extraction_failed_count > extracted_count ->
    IO.puts("⚠️  PRIMARY ISSUE: HTML Extraction Fails")
    IO.puts("   French pages fetch successfully but extraction fails")
    IO.puts("   Recommendation: Debug EventExtractor patterns for French pages")

  timeout_count > length(results) * 0.3 ->
    IO.puts("⚠️  PRIMARY ISSUE: Timeouts")
    IO.puts("   > 30% of requests timeout")
    IO.puts("   Recommendation: Increase timeout for French page fetches")

  extracted_count == success_count ->
    IO.puts("✅ NO ISSUES DETECTED")
    IO.puts("   All French pages fetch and extract successfully")
    IO.puts("   This suggests the bilingual fetch failures may be intermittent")

  true ->
    IO.puts("⚠️  MIXED ISSUES")
    IO.puts("   Multiple failure modes detected")
    IO.puts("   Recommendation: Implement robust retry logic with fallbacks")
end

IO.puts("\n" <> String.duplicate("=", 80))
