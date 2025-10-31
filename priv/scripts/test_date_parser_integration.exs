# Test DateParser integration with EventExtractor

alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor
alias EventasaurusDiscovery.Sources.Sortiraparis.Client

# Test URLs with different date patterns
test_urls = [
  # English single date
  {"https://www.sortiraparis.com/en/what-to-see-in-paris/shows/articles/335322-lyoom-comedy-souk-le-marche-du-rire", "recurring"},
  # French date range (exhibition)
  {"https://www.sortiraparis.com/en/what-to-see-in-paris/shows/articles/335327-casse-noisette-magic-show-noel-grand-rex-theatre-13e-art", "exhibition"},
  # Add more as needed
]

IO.puts("\n🧪 Testing DateParser Integration with EventExtractor\n")
IO.puts("=" <> String.duplicate("=", 70))

results = Enum.map(test_urls, fn {url, expected_type} ->
  IO.puts("\n📄 Testing: #{url}")
  
  case Client.fetch_page(url) do
    {:ok, html} ->
      case EventExtractor.extract(html, url) do
        {:ok, event_data} ->
          IO.puts("✅ Event extracted: #{event_data["title"]}")
          IO.puts("   📅 Date string: #{event_data["date_string"]}")
          IO.puts("   🎭 Event type: #{event_data["event_type"]} (expected: #{expected_type})")
          
          if event_data["event_type"] == String.to_atom(expected_type) do
            IO.puts("   ✅ Event type matches expected!")
            {:ok, event_data}
          else
            IO.puts("   ⚠️  Event type mismatch!")
            {:warning, event_data}
          end
          
        {:error, reason} ->
          IO.puts("❌ Extraction failed: #{inspect(reason)}")
          {:error, reason}
      end
      
    {:error, reason} ->
      IO.puts("❌ Failed to fetch: #{inspect(reason)}")
      {:error, reason}
  end
end)

# Summary
successful = Enum.count(results, fn {status, _} -> status == :ok end)
warnings = Enum.count(results, fn {status, _} -> status == :warning end)
failed = Enum.count(results, fn {status, _} -> status == :error end)

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("\n📊 Summary:")
IO.puts("   ✅ Successful: #{successful}/#{length(test_urls)}")
IO.puts("   ⚠️  Warnings: #{warnings}/#{length(test_urls)}")
IO.puts("   ❌ Failed: #{failed}/#{length(test_urls)}")

if failed == 0 do
  IO.puts("\n🎉 All tests passed!")
else
  IO.puts("\n⚠️  Some tests failed")
end
