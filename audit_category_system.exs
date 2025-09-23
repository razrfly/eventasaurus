#!/usr/bin/env elixir

# Comprehensive audit of the category system with real scraped data

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
alias EventasaurusDiscovery.Categories.Category
alias EventasaurusDiscovery.Sources.Source
import Ecto.Query

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("CATEGORY SYSTEM AUDIT REPORT")
IO.puts(String.duplicate("=", 80))
IO.puts("Generated: #{DateTime.utc_now() |> DateTime.to_string()}")
IO.puts(String.duplicate("=", 80) <> "\n")

# 1. Overall Statistics
IO.puts("📊 OVERALL STATISTICS")
IO.puts(String.duplicate("-", 40))

total_events = Repo.one(from pe in PublicEvent, select: count(pe.id))
IO.puts("Total Events: #{total_events}")

events_with_categories = Repo.one(
  from pe in PublicEvent,
  join: pec in "public_event_categories", on: pec.event_id == pe.id,
  select: count(pe.id, :distinct)
)
IO.puts("Events with Categories: #{events_with_categories}")
IO.puts("Events without Categories: #{total_events - events_with_categories}")
IO.puts("Coverage: #{Float.round(events_with_categories / total_events * 100, 2)}%")

# 2. Category Distribution by Source
IO.puts("\n📈 CATEGORY DISTRIBUTION BY SOURCE")
IO.puts(String.duplicate("-", 40))

sources = ["ticketmaster", "karnet", "bandsintown"]
for source_slug <- sources do
  source_total = Repo.one(
    from pe in PublicEvent,
    join: pes in PublicEventSource, on: pes.event_id == pe.id,
    join: s in Source, on: s.id == pes.source_id,
    where: s.slug == ^source_slug,
    select: count(pe.id, :distinct)
  )

  source_with_cats = Repo.one(
    from pe in PublicEvent,
    join: pes in PublicEventSource, on: pes.event_id == pe.id,
    join: s in Source, on: s.id == pes.source_id,
    join: pec in "public_event_categories", on: pec.event_id == pe.id,
    where: s.slug == ^source_slug,
    select: count(pe.id, :distinct)
  )

  coverage = if source_total > 0, do: Float.round(source_with_cats / source_total * 100, 2), else: 0
  IO.puts("\n#{String.upcase(source_slug)}:")
  IO.puts("  Total: #{source_total}")
  IO.puts("  With Categories: #{source_with_cats}")
  IO.puts("  Coverage: #{coverage}%")
end

# 3. Most Common Categories
IO.puts("\n🏆 TOP 10 MOST COMMON CATEGORIES")
IO.puts(String.duplicate("-", 40))

top_categories = Repo.all(
  from c in Category,
  join: pec in "public_event_categories", on: pec.category_id == c.id,
  group_by: [c.id, c.name, c.slug],
  order_by: [desc: count(pec.id)],
  select: {c.name, c.slug, count(pec.id)},
  limit: 10
)

for {name, slug, count} <- top_categories do
  IO.puts("#{name} (#{slug}): #{count} events")
end

# 4. "Other" Category Usage
IO.puts("\n❓ 'OTHER' CATEGORY ANALYSIS")
IO.puts(String.duplicate("-", 40))

other_category = Repo.one(from c in Category, where: c.slug == "other", select: c)
if other_category do
  other_count = Repo.one(
    from pec in "public_event_categories",
    where: pec.category_id == ^other_category.id,
    select: count(pec.id)
  )

  other_as_primary = Repo.one(
    from pec in "public_event_categories",
    where: pec.category_id == ^other_category.id and pec.is_primary == true,
    select: count(pec.id)
  )

  IO.puts("'Other' category ID: #{other_category.id}")
  IO.puts("Total assignments: #{other_count}")
  IO.puts("As primary category: #{other_as_primary}")
  IO.puts("Percentage of all events: #{Float.round(other_count / total_events * 100, 2)}%")
else
  IO.puts("WARNING: 'Other' category not found!")
end

# 5. Primary vs Secondary Categories
IO.puts("\n🎯 PRIMARY VS SECONDARY CATEGORIES")
IO.puts(String.duplicate("-", 40))

primary_count = Repo.one(
  from pec in "public_event_categories",
  where: pec.is_primary == true,
  select: count(pec.id)
)

secondary_count = Repo.one(
  from pec in "public_event_categories",
  where: pec.is_primary == false,
  select: count(pec.id)
)

avg_cats_per_event = if events_with_categories > 0 do
  Float.round((primary_count + secondary_count) / events_with_categories, 2)
else
  0
end

IO.puts("Primary category assignments: #{primary_count}")
IO.puts("Secondary category assignments: #{secondary_count}")
IO.puts("Average categories per event: #{avg_cats_per_event}")

# 6. Sample Events Analysis
IO.puts("\n🔍 SAMPLE EVENT ANALYSIS")
IO.puts(String.duplicate("-", 40))

# Get sample events from each source
for source_slug <- sources do
  IO.puts("\n#{String.upcase(source_slug)} Sample:")

  sample_events = Repo.all(
    from pe in PublicEvent,
    join: pes in PublicEventSource, on: pes.event_id == pe.id,
    join: s in Source, on: s.id == pes.source_id,
    where: s.slug == ^source_slug,
    limit: 3,
    preload: [:categories, sources: :source]
  )

  for event <- sample_events do
    # Get metadata from the source
    event_source = Enum.find(event.sources, fn s -> s.source && s.source.slug == source_slug end)
    metadata = if event_source, do: event_source.metadata || %{}, else: %{}

    raw_categories = case source_slug do
      "ticketmaster" ->
        get_in(metadata, ["ticketmaster_data", "classifications"]) ||
        get_in(metadata, ["raw_event_data", "classifications"]) || []
      "karnet" ->
        metadata["category"] || "none"
      "bandsintown" ->
        metadata["tags"] || []
    end

    IO.puts("\n  Event: #{String.slice(event.title || "Untitled", 0, 50)}")
    IO.puts("  Raw categories: #{inspect(raw_categories, limit: :infinity, pretty: true)}")
    IO.puts("  Mapped categories: #{event.categories |> Enum.map(& &1.name) |> Enum.join(", ")}")

    primary = Enum.find(event.categories, fn cat ->
      pec = Repo.one(
        from pec in "public_event_categories",
        where: pec.event_id == ^event.id and pec.category_id == ^cat.id,
        select: pec.is_primary
      )
      pec == true
    end)

    if primary do
      IO.puts("  Primary: #{primary.name}")
    end
  end
end

# 7. Events with Multiple Categories
IO.puts("\n🌈 EVENTS WITH MULTIPLE CATEGORIES")
IO.puts(String.duplicate("-", 40))

multi_cat_events = Repo.all(
  from pe in PublicEvent,
  join: pec in "public_event_categories", on: pec.event_id == pe.id,
  group_by: pe.id,
  having: count(pec.id) > 1,
  select: {pe.id, count(pec.id)},
  limit: 10
)

IO.puts("Events with multiple categories: #{length(multi_cat_events)}")
if length(multi_cat_events) > 0 do
  IO.puts("\nExamples:")
  for {event_id, cat_count} <- Enum.take(multi_cat_events, 5) do
    event = Repo.get!(PublicEvent, event_id) |> Repo.preload(:categories)
    cats = event.categories |> Enum.map(& &1.name) |> Enum.join(", ")
    IO.puts("  #{String.slice(event.title || "Untitled", 0, 40)}: #{cat_count} categories (#{cats})")
  end
end

# 8. Unmapped Categories Check
IO.puts("\n⚠️  UNMAPPED CATEGORIES CHECK")
IO.puts(String.duplicate("-", 40))

# Sample events that only have "Other" as category
other_only_events = if other_category do
  Repo.all(
    from pe in PublicEvent,
    join: pec in "public_event_categories", on: pec.event_id == pe.id,
    where: pec.category_id == ^other_category.id and pec.is_primary == true,
    group_by: pe.id,
    having: count(pec.id) == 1,
    select: pe,
    limit: 5,
    preload: [:categories]
  )
else
  []
end

if length(other_only_events) > 0 do
  IO.puts("Found #{length(other_only_events)} events with ONLY 'Other' category")
  IO.puts("\nExamples of unmapped categories:")
  for event <- Repo.preload(other_only_events, sources: :source) do
    # Get the first source to determine type
    first_source = List.first(event.sources)
    source_slug = if first_source && first_source.source, do: first_source.source.slug, else: "unknown"
    metadata = if first_source, do: first_source.metadata || %{}, else: %{}

    raw = case source_slug do
      "ticketmaster" ->
        classifications = get_in(metadata, ["ticketmaster_data", "classifications"]) || []
        Enum.map(classifications, fn c ->
          [
            get_in(c, ["segment", "name"]),
            get_in(c, ["genre", "name"]),
            get_in(c, ["subGenre", "name"])
          ] |> Enum.filter(&(&1))
        end) |> List.flatten()
      "karnet" ->
        [metadata["category"]] |> Enum.filter(&(&1))
      "bandsintown" ->
        metadata["tags"] || []
      _ ->
        []
    end

    IO.puts("\n  Event: #{String.slice(event.title || "Untitled", 0, 50)}")
    IO.puts("  Source: #{source_slug}")
    IO.puts("  Raw categories that didn't map: #{inspect(raw)}")
  end
else
  IO.puts("✅ No events found with only 'Other' category - good mapping coverage!")
end

# Final Grade
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("🎓 FINAL GRADE")
IO.puts(String.duplicate("=", 80))

# Calculate grade based on metrics
coverage_score = events_with_categories / total_events * 100
other_percentage = if other_category do
  other_count = Repo.one(
    from pec in "public_event_categories",
    where: pec.category_id == ^other_category.id,
    select: count(pec.id)
  )
  other_count / total_events * 100
else
  100 # Worst case if Other doesn't exist
end

multi_cat_percentage = length(multi_cat_events) / events_with_categories * 100

grade = cond do
  coverage_score == 100 and other_percentage < 5 and multi_cat_percentage > 20 -> "A+"
  coverage_score >= 95 and other_percentage < 10 and multi_cat_percentage > 15 -> "A"
  coverage_score >= 90 and other_percentage < 15 and multi_cat_percentage > 10 -> "B+"
  coverage_score >= 85 and other_percentage < 20 -> "B"
  coverage_score >= 80 -> "C"
  true -> "D"
end

IO.puts("\n📊 Metrics Summary:")
IO.puts("  • Coverage: #{Float.round(coverage_score, 2)}%")
IO.puts("  • 'Other' usage: #{Float.round(other_percentage, 2)}%")
IO.puts("  • Multi-category events: #{Float.round(multi_cat_percentage, 2)}%")
IO.puts("\n🏆 GRADE: #{grade}")

if coverage_score < 100 do
  IO.puts("\n⚠️  ISSUE: Not all events have categories!")
end

if other_percentage > 10 do
  IO.puts("\n⚠️  ISSUE: High 'Other' category usage - improve YAML mappings")
end

if multi_cat_percentage < 10 do
  IO.puts("\n⚠️  ISSUE: Low multi-category assignment - check secondary category logic")
end

IO.puts("\n" <> String.duplicate("=", 80))