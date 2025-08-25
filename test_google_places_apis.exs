#!/usr/bin/env elixir

# Test script for Google Places API refactoring
# Run with: mix run test_google_places_apis.exs

alias EventasaurusWeb.Services.GooglePlacesRichDataProvider

defmodule GooglePlacesAPITest do
  def run do
    IO.puts("\n=== Testing Google Places API Implementation ===\n")
    
    # Test 1: Search for places (default behavior)
    IO.puts("1. Testing place search (restaurants in New York)...")
    test_search("restaurants", %{location_scope: "place"})
    
    # Test 2: Search for cities
    IO.puts("\n2. Testing city search (Paris)...")
    test_search("Paris", %{location_scope: "city"})
    
    # Test 3: Search for regions/states
    IO.puts("\n3. Testing region search (California)...")
    test_search("California", %{location_scope: "region"})
    
    # Test 4: Search for countries
    IO.puts("\n4. Testing country search (Japan)...")
    test_search("Japan", %{location_scope: "country"})
    
    IO.puts("\n=== All tests completed ===\n")
  end
  
  defp test_search(query, options) do
    case GooglePlacesRichDataProvider.search(query, options) do
      {:ok, results} when is_list(results) ->
        IO.puts("  ✓ Success! Found #{length(results)} results")
        
        if length(results) > 0 do
          first = List.first(results)
          IO.puts("  First result:")
          IO.puts("    - Title: #{first.title}")
          IO.puts("    - Type: #{first.type}")
          IO.puts("    - Description: #{first.description || "N/A"}")
          IO.puts("    - ID: #{first.id}")
        end
        
      {:error, reason} ->
        IO.puts("  ✗ Error: #{inspect(reason)}")
    end
  end
end

# Ensure the cache is started
if !Process.whereis(:google_places_cache) do
  IO.puts("Starting cache...")
  {:ok, _} = Cachex.start_link(:google_places_cache)
end

# Run the tests
GooglePlacesAPITest.run()