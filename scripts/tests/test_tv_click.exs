# Test script to debug TV show click functionality
alias EventasaurusWeb.Services.TmdbRichDataProvider
alias EventasaurusWeb.Services.RichDataManager

IO.puts "\n=== Testing TV Show Search and Selection ==="

# 1. Test searching for TV shows
IO.puts "\n1. Testing TV show search..."
case TmdbRichDataProvider.search("Breaking Bad", %{content_type: :tv}) do
  {:ok, results} ->
    IO.puts "   ✅ Search returned #{length(results)} results"
    
    if length(results) > 0 do
      first_result = List.first(results)
      IO.puts "   First result:"
      IO.puts "   - ID: #{first_result.id}"
      IO.puts "   - Type: #{first_result.type}"
      IO.puts "   - Title: #{first_result.title}"
      IO.puts "   - Has image_url: #{Map.has_key?(first_result, :image_url)}"
      
      # 2. Test getting detailed data
      IO.puts "\n2. Testing detailed data retrieval..."
      case TmdbRichDataProvider.get_cached_details(first_result.id, :tv) do
        {:ok, detailed} ->
          IO.puts "   ✅ Detailed data retrieved successfully"
          IO.puts "   - Title: #{detailed.title}"
          IO.puts "   - Type: #{detailed.type}"
          IO.puts "   - Has image_url: #{Map.has_key?(detailed, :image_url)}"
          IO.puts "   - Image URL: #{inspect detailed.image_url}"
        {:error, reason} ->
          IO.puts "   ❌ Failed to get detailed data: #{inspect reason}"
      end
    end
  {:error, reason} ->
    IO.puts "   ❌ Search failed: #{inspect reason}"
end

# 3. Test through RichDataManager (as the component uses it)
IO.puts "\n3. Testing through RichDataManager..."
search_options = %{
  providers: [:tmdb],
  limit: 10,
  content_type: :tv
}

case RichDataManager.search("Breaking Bad", search_options) do
  {:ok, results_by_provider} ->
    case Map.get(results_by_provider, :tmdb) do
      {:ok, results} when is_list(results) ->
        IO.puts "   ✅ RichDataManager search returned #{length(results)} results"
        
        if length(results) > 0 do
          first = List.first(results)
          IO.puts "   First result type: #{first.type}"
          
          # Test getting cached details
          case RichDataManager.get_cached_details(:tmdb, first.id, :tv) do
            {:ok, detailed} ->
              IO.puts "   ✅ RichDataManager cached details work"
              IO.puts "   - Retrieved: #{detailed.title}"
            {:error, reason} ->
              IO.puts "   ❌ RichDataManager cached details failed: #{inspect reason}"
          end
        end
      _ ->
        IO.puts "   ❌ No results from TMDB provider"
    end
  {:error, reason} ->
    IO.puts "   ❌ RichDataManager search failed: #{inspect reason}"
end

IO.puts "\n=== Test Complete ==="