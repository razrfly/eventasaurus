# Test full pipeline with Transformer
alias EventasaurusDiscovery.Sources.Sortiraparis.Client
alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor
alias EventasaurusDiscovery.Sources.Sortiraparis.Transformer

url = "https://www.sortiraparis.com/en/what-to-see-in-paris/concerts-music-festival/articles/326487-the-hives-in-concert-at-zenith-de-paris-in-november-2025"

IO.puts("\n🧪 Testing Full Pipeline: The Hives Concert")
IO.puts("=" <> String.duplicate("=", 70))

case Client.fetch_page(url) do
  {:ok, html} ->
    IO.puts("✅ Fetched HTML")
    
    case EventExtractor.extract(html, url) do
      {:ok, event_data} ->
        IO.puts("✅ Extracted event data")
        IO.puts("   Title: #{event_data["title"]}")
        IO.puts("   Date string: #{event_data["date_string"]}")
        
        case Transformer.transform_event(event_data) do
          {:ok, events} ->
            IO.puts("✅ Transformer succeeded!")
            IO.puts("   Created #{length(events)} event(s)")
            
            Enum.each(events, fn event ->
              IO.puts("\n   Event: #{event.title}")
              IO.puts("   Starts at: #{event.starts_at}")
              IO.puts("   External ID: #{event.external_id}")
            end)
            
          {:error, reason} ->
            IO.puts("❌ Transformer failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Extraction failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to fetch: #{inspect(reason)}")
end
