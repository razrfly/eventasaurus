#!/usr/bin/env elixir
# Script to check why categories aren't displaying on the city page
# Run with: mix run check_categories_display.exs

require Logger
alias EventasaurusDiscovery.PublicEventsEnhanced
alias EventasaurusWeb.Helpers.CategoryHelpers

IO.puts("\n=== Checking Category Display Issue ===\n")

# Get some events as they would be loaded on the city page
events = PublicEventsEnhanced.list_events(
  page: 1,
  page_size: 10,
  language: "en"
)

IO.puts("Loaded #{length(events)} events\n")

# Check each event
for {event, idx} <- Enum.with_index(events, 1) do
  IO.puts("Event #{idx}: #{String.slice(event.title || "No title", 0, 50)}")
  
  # Check categories field
  categories = Map.get(event, :categories)
  IO.puts("  Categories field: #{inspect(categories != nil)}")
  
  if categories do
    IO.puts("  Number of categories: #{length(categories)}")
    
    # Check if any category has required fields
    for cat <- categories do
      has_name = Map.get(cat, :name) != nil
      has_color = Map.get(cat, :color) != nil
      IO.puts("    - #{Map.get(cat, :name, "NO NAME")} | Color: #{Map.get(cat, :color, "NO COLOR")}")
    end
    
    # Test CategoryHelper
    preferred = CategoryHelpers.get_preferred_category(categories)
    if preferred do
      IO.puts("  Preferred category: #{preferred.name} (color: #{preferred.color})")
    else
      IO.puts("  ❌ No preferred category found!")
    end
  else
    IO.puts("  ❌ No categories loaded!")
  end
  
  IO.puts("")
end

IO.puts("\n=== Summary ===")

# Count events with/without categories
events_with_categories = Enum.count(events, fn e -> 
  cats = Map.get(e, :categories)
  cats != nil && cats != []
end)

events_with_displayable_category = Enum.count(events, fn e ->
  cats = Map.get(e, :categories)
  if cats && cats != [] do
    preferred = CategoryHelpers.get_preferred_category(cats)
    preferred != nil && preferred.color != nil
  else
    false
  end
end)

IO.puts("Events with categories: #{events_with_categories}/#{length(events)}")
IO.puts("Events with displayable category: #{events_with_displayable_category}/#{length(events)}")

if events_with_displayable_category == 0 do
  IO.puts("\n❌ PROBLEM FOUND: No events have displayable categories!")
  IO.puts("   This explains why categories aren't showing on the page.")
else
  IO.puts("\n✅ Categories are properly loaded and displayable.")
end
