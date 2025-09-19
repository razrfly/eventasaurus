# Expanded category mappings for better coverage
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Categories.{Category, CategoryMapping}
import Ecto.Query

# Get all categories for mapping
categories = Repo.all(Category) |> Enum.map(&{&1.slug, &1}) |> Map.new()

# Comprehensive Ticketmaster mappings
ticketmaster_mappings = [
  # Music segment and genres
  %{source: "ticketmaster", type: "segment", value: "Music", slug: "concerts", priority: 10},
  %{source: "ticketmaster", type: "genre", value: "Rock", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Pop", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Classical", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Jazz", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Country", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Alternative", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "R&B", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Hip-Hop/Rap", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Electronic", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "World", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Reggae", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Blues", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Folk", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Metal", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Dance/Electronic", slug: "concerts", priority: 8},
  %{source: "ticketmaster", type: "subGenre", value: "Festival", slug: "festivals", priority: 15},
  %{source: "ticketmaster", type: "subGenre", value: "Music Festival", slug: "festivals", priority: 15},

  # Arts & Theatre segment
  %{source: "ticketmaster", type: "segment", value: "Arts & Theatre", slug: "performances", priority: 10},
  %{source: "ticketmaster", type: "genre", value: "Theatre", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Musical", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Opera", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Dance", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Ballet", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Comedy", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Circus & Specialty Acts", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Performance Art", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Cabaret", slug: "performances", priority: 8},

  # Film segment
  %{source: "ticketmaster", type: "segment", value: "Film", slug: "film", priority: 10},
  %{source: "ticketmaster", type: "genre", value: "Film", slug: "film", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Film Festival", slug: "film", priority: 8},

  # Miscellaneous segment (often includes exhibitions, special events)
  %{source: "ticketmaster", type: "segment", value: "Miscellaneous", slug: "exhibitions", priority: 5},
  %{source: "ticketmaster", type: "genre", value: "Museum", slug: "exhibitions", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Exhibition", slug: "exhibitions", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Gallery", slug: "exhibitions", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Literary", slug: "literature", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Lecture", slug: "literature", priority: 8},

  # Sports segment (some cultural sports events might be included)
  %{source: "ticketmaster", type: "segment", value: "Sports", slug: "performances", priority: 3},

  # Family segment (often cultural events for families)
  %{source: "ticketmaster", type: "segment", value: "Family", slug: "performances", priority: 5},
  %{source: "ticketmaster", type: "genre", value: "Children's Theatre", slug: "performances", priority: 8},
  %{source: "ticketmaster", type: "genre", value: "Children's Music", slug: "concerts", priority: 8},
]

# Comprehensive Karnet mappings (Polish categories)
karnet_mappings = [
  # Main categories
  %{source: "karnet", type: nil, value: "koncerty", slug: "concerts", priority: 10},
  %{source: "karnet", type: nil, value: "koncert", slug: "concerts", priority: 10},
  %{source: "karnet", type: nil, value: "festiwale", slug: "festivals", priority: 10},
  %{source: "karnet", type: nil, value: "festiwal", slug: "festivals", priority: 10},
  %{source: "karnet", type: nil, value: "spektakle", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "spektakl", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "teatr", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "wystawy", slug: "exhibitions", priority: 10},
  %{source: "karnet", type: nil, value: "wystawa", slug: "exhibitions", priority: 10},
  %{source: "karnet", type: nil, value: "literatura", slug: "literature", priority: 10},
  %{source: "karnet", type: nil, value: "spotkanie autorskie", slug: "literature", priority: 10},
  %{source: "karnet", type: nil, value: "film", slug: "film", priority: 10},
  %{source: "karnet", type: nil, value: "kino", slug: "film", priority: 10},
  %{source: "karnet", type: nil, value: "seans", slug: "film", priority: 10},

  # Additional Polish categories that might appear
  %{source: "karnet", type: nil, value: "opera", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "balet", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "taniec", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "kabaret", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "stand-up", slug: "performances", priority: 10},
  %{source: "karnet", type: nil, value: "muzeum", slug: "exhibitions", priority: 10},
  %{source: "karnet", type: nil, value: "galeria", slug: "exhibitions", priority: 10},
  %{source: "karnet", type: nil, value: "wernisaż", slug: "exhibitions", priority: 10},
  %{source: "karnet", type: nil, value: "warsztaty", slug: "exhibitions", priority: 8},
  %{source: "karnet", type: nil, value: "spotkanie", slug: "literature", priority: 8},
]

# Insert all mappings
all_mappings = ticketmaster_mappings ++ karnet_mappings

Enum.each(all_mappings, fn mapping ->
  if category = categories[mapping.slug] do
    %CategoryMapping{}
    |> CategoryMapping.changeset(%{
      external_source: mapping.source,
      external_type: mapping[:type],
      external_value: mapping.value,
      category_id: category.id,
      priority: mapping.priority,
      external_locale: "en"
    })
    |> Repo.insert(on_conflict: :nothing)
  end
end)

IO.puts("✅ Expanded category mappings created successfully!")

# Show statistics
tm_count = Repo.one(from m in CategoryMapping, where: m.external_source == "ticketmaster", select: count(m.id))
karnet_count = Repo.one(from m in CategoryMapping, where: m.external_source == "karnet", select: count(m.id))

IO.puts("📊 Statistics:")
IO.puts("  - Ticketmaster mappings: #{tm_count}")
IO.puts("  - Karnet mappings: #{karnet_count}")
IO.puts("  - Total mappings: #{tm_count + karnet_count}")