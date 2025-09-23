alias EventasaurusDiscovery.Categories.CategoryExtractor
alias EventasaurusApp.Repo
import Ecto.Query

# Get a Karnet event without categories
query = from pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
  left_join: pec in EventasaurusDiscovery.Categories.PublicEventCategory, on: pec.event_id == pe.id,
  join: pes in EventasaurusDiscovery.PublicEvents.PublicEventSource, on: pes.event_id == pe.id,
  where: is_nil(pec.id) and pes.source_id == 4,
  limit: 1,
  select: {pe, pes.metadata}

event = Repo.one(query)

if event do
  {pe, metadata} = event
  IO.puts("Testing category assignment for: #{pe.slug}")
  IO.puts("Title: #{pe.title}")
  IO.puts("")

  # Show metadata
  IO.puts("Metadata category: #{metadata["category"]}")
  IO.puts("")

  # Try to assign categories
  IO.puts("Attempting to assign categories...")
  result = CategoryExtractor.assign_categories_to_event(pe.id, "karnet", metadata)

  case result do
    {:ok, categories} ->
      IO.puts("SUCCESS! Assigned #{length(categories)} categories")
      Enum.each(categories, fn cat ->
        IO.puts("  - #{cat.category.name} (#{if cat.is_primary, do: "primary", else: "secondary"})")
      end)
    {:error, reason} ->
      IO.puts("ERROR: #{inspect(reason)}")
  end

  # Check if categories were saved
  saved_categories = Repo.all(
    from pec in EventasaurusDiscovery.Categories.PublicEventCategory,
    join: c in assoc(pec, :category),
    where: pec.event_id == ^pe.id,
    select: {c.name, pec.is_primary}
  )

  IO.puts("")
  IO.puts("Categories in database:")
  Enum.each(saved_categories, fn {name, is_primary} ->
    IO.puts("  - #{name} (#{if is_primary, do: "primary", else: "secondary"})")
  end)
else
  IO.puts("No Karnet events without categories found")
end