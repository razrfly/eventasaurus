# Debug failing article
alias EventasaurusDiscovery.Sources.Sortiraparis.Client
alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor

url = "https://www.sortiraparis.com/en/what-to-see-in-paris/concerts-music-festival/articles/326487-the-hives-in-concert-at-zenith-de-paris-in-november-2025"

IO.puts("\n🔍 Debugging failing article: The Hives concert")
IO.puts("=" <> String.duplicate("=", 70))

case Client.fetch_page(url) do
  {:ok, html} ->
    IO.puts("✅ Fetched HTML (#{byte_size(html)} bytes)")
    
    # Try to extract date string
    case EventExtractor.extract_date_string(html) do
      {:ok, date_string} ->
        IO.puts("✅ Date string extracted: #{inspect(date_string)}")
        
      {:error, reason} ->
        IO.puts("❌ Date string extraction failed: #{inspect(reason)}")
    end
    
    # Try full extraction
    case EventExtractor.extract(html, url) do
      {:ok, event_data} ->
        IO.puts("✅ Event extracted successfully")
        IO.puts("   Title: #{event_data["title"]}")
        IO.puts("   Date: #{event_data["date_string"]}")
        
      {:error, reason} ->
        IO.puts("❌ Extraction failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to fetch: #{inspect(reason)}")
end
