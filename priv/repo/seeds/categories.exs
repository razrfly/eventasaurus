# Category seeds for EventasaurusDiscovery

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Categories.{Category, CategoryMapping}
import Ecto.Query

categories = [
  %{
    name: "Concerts",
    slug: "concerts",
    description: "Live music performances and shows",
    icon: "🎵",
    color: "#4ECDC4",
    display_order: 1
  },
  %{
    name: "Festivals",
    slug: "festivals",
    description: "Music festivals, cultural festivals, and multi-day events",
    icon: "🎪",
    color: "#FF6B6B",
    display_order: 2
  },
  %{
    name: "Theatre",
    slug: "theatre",
    description: "Theater, musicals, and stage performances",
    icon: "🎭",
    color: "#95E77E",
    display_order: 3
  },
  %{
    name: "Sports",
    slug: "sports",
    description: "Sporting events and competitions",
    icon: "⚽",
    color: "#FFA500",
    display_order: 4
  },
  %{
    name: "Comedy",
    slug: "comedy",
    description: "Stand-up comedy and humor shows",
    icon: "😂",
    color: "#FFD700",
    display_order: 5
  },
  %{
    name: "Arts",
    slug: "arts",
    description: "Art exhibitions, galleries, and cultural events",
    icon: "🎨",
    color: "#C7B8FF",
    display_order: 6
  },
  %{
    name: "Film",
    slug: "film",
    description: "Movie screenings, film festivals, and cinema events",
    icon: "🎬",
    color: "#A8E6CF",
    display_order: 7
  },
  %{
    name: "Family",
    slug: "family",
    description: "Family-friendly and children's events",
    icon: "👨‍👩‍👧‍👦",
    color: "#FFB6C1",
    display_order: 8
  },
  %{
    name: "Food & Drink",
    slug: "food-drink",
    description: "Food festivals, tastings, and culinary events",
    icon: "🍽️",
    color: "#98D8C8",
    display_order: 9
  },
  %{
    name: "Nightlife",
    slug: "nightlife",
    description: "Club events, parties, and night entertainment",
    icon: "🌃",
    color: "#6A0DAD",
    display_order: 10
  },
  %{
    name: "Community",
    slug: "community",
    description: "Community gatherings and local events",
    icon: "👥",
    color: "#87CEEB",
    display_order: 11
  },
  %{
    name: "Education",
    slug: "education",
    description: "Workshops, lectures, and educational events",
    icon: "🎓",
    color: "#4169E1",
    display_order: 12
  },
  %{
    name: "Business",
    slug: "business",
    description: "Conferences, networking, and business events",
    icon: "💼",
    color: "#708090",
    display_order: 13
  }
]

Enum.each(categories, fn category_attrs ->
  case Repo.get_by(Category, slug: category_attrs.slug) do
    nil ->
      %Category{}
      |> Category.changeset(category_attrs)
      |> Repo.insert!()
      IO.puts("Created category: #{category_attrs.name}")

    existing ->
      existing
      |> Category.changeset(category_attrs)
      |> Repo.update!()
      IO.puts("Updated category: #{category_attrs.name}")
  end
end)

IO.puts("\n✅ Categories seeded successfully!")

# Seed category mappings
IO.puts("\n🗺️ Seeding category mappings...")

# Build a map of category slugs to IDs for easy lookup
category_map = Repo.all(Category)
|> Enum.map(fn cat -> {cat.slug, cat.id} end)
|> Map.new()

# Ticketmaster mappings (3-tier: segment -> genre -> subgenre)
ticketmaster_mappings = [
  # Music mappings
  {"Music", "segment", category_map["concerts"], 100},
  {"Rock", "genre", category_map["concerts"], 90},
  {"Pop", "genre", category_map["concerts"], 90},
  {"Alternative", "genre", category_map["concerts"], 90},
  {"Country", "genre", category_map["concerts"], 90},
  {"Hip-Hop/Rap", "genre", category_map["concerts"], 90},
  {"R&B", "genre", category_map["concerts"], 90},
  {"Electronic", "genre", category_map["concerts"], 90},
  {"Jazz", "genre", category_map["concerts"], 90},
  {"Blues", "genre", category_map["concerts"], 90},
  {"Classical", "genre", category_map["concerts"], 90},
  {"Metal", "genre", category_map["concerts"], 90},
  {"Indie", "genre", category_map["concerts"], 90},

  # Sports mappings
  {"Sports", "segment", category_map["sports"], 100},
  {"Basketball", "genre", category_map["sports"], 90},
  {"Football", "genre", category_map["sports"], 90},
  {"Baseball", "genre", category_map["sports"], 90},
  {"Hockey", "genre", category_map["sports"], 90},
  {"Soccer", "genre", category_map["sports"], 90},

  # Arts & Theatre mappings
  {"Arts & Theatre", "segment", category_map["theatre"], 100},
  {"Theatre", "genre", category_map["theatre"], 90},
  {"Musical", "genre", category_map["theatre"], 90},
  {"Opera", "genre", category_map["arts"], 90},
  {"Dance", "genre", category_map["arts"], 90},
  {"Comedy", "genre", category_map["comedy"], 90},

  # Family mappings
  {"Family", "segment", category_map["family"], 100},
  {"Children's Theatre", "genre", category_map["family"], 90},

  # Film mappings
  {"Film", "segment", category_map["film"], 100}
]

tm_count = Enum.reduce(ticketmaster_mappings, 0, fn {value, type, category_id, priority}, acc ->
  if category_id do
    attrs = %{
      external_source: "ticketmaster",
      external_type: type,
      external_value: value,
      external_locale: "en",
      category_id: category_id,
      priority: priority,
      metadata: %{"source" => "seed", "created_at" => DateTime.utc_now()}
    }

    case Repo.get_by(CategoryMapping,
      external_source: attrs.external_source,
      external_type: attrs.external_type,
      external_value: attrs.external_value
    ) do
      nil ->
        %CategoryMapping{} |> CategoryMapping.changeset(attrs) |> Repo.insert!()
        acc + 1
      _ ->
        acc
    end
  else
    acc
  end
end)

IO.puts("  Created #{tm_count} Ticketmaster mappings")

# Karnet mappings (Polish language)
karnet_mappings = [
  {"koncerty", category_map["concerts"], "pl", 100},
  {"teatr", category_map["theatre"], "pl", 100},
  {"spektakle", category_map["theatre"], "pl", 90},
  {"kabaret", category_map["comedy"], "pl", 100},
  {"stand-up", category_map["comedy"], "pl", 100},
  {"festiwale", category_map["festivals"], "pl", 100},
  {"imprezy", category_map["nightlife"], "pl", 80},
  {"sport", category_map["sports"], "pl", 100},
  {"film", category_map["film"], "pl", 100},
  {"kino", category_map["film"], "pl", 100},
  {"sztuka", category_map["arts"], "pl", 100},
  {"wystawa", category_map["arts"], "pl", 90},
  {"muzyka", category_map["concerts"], "pl", 90},
  {"opera", category_map["arts"], "pl", 100},
  {"balet", category_map["arts"], "pl", 100},
  {"taniec", category_map["arts"], "pl", 90},
  {"dla-dzieci", category_map["family"], "pl", 100},
  {"warsztaty", category_map["education"], "pl", 100},
  {"konferencje", category_map["business"], "pl", 100}
]

karnet_count = Enum.reduce(karnet_mappings, 0, fn {value, category_id, locale, priority}, acc ->
  if category_id do
    attrs = %{
      external_source: "karnet",
      external_type: nil,
      external_value: value,
      external_locale: locale,
      category_id: category_id,
      priority: priority,
      metadata: %{"source" => "seed", "created_at" => DateTime.utc_now()}
    }

    case Repo.get_by(CategoryMapping,
      external_source: attrs.external_source,
      external_value: attrs.external_value
    ) do
      nil ->
        %CategoryMapping{} |> CategoryMapping.changeset(attrs) |> Repo.insert!()
        acc + 1
      _ ->
        acc
    end
  else
    acc
  end
end)

IO.puts("  Created #{karnet_count} Karnet mappings")

# Bandsintown mappings (always concerts/music)
bandsintown_mappings = [
  {"concert", category_map["concerts"], 100},
  {"festival", category_map["festivals"], 100},
  {"music", category_map["concerts"], 100},
  {"rock", category_map["concerts"], 90},
  {"pop", category_map["concerts"], 90},
  {"metal", category_map["concerts"], 90},
  {"jazz", category_map["concerts"], 90},
  {"electronic", category_map["concerts"], 90},
  {"hip-hop", category_map["concerts"], 90},
  {"indie", category_map["concerts"], 90},
  {"punk", category_map["concerts"], 90},
  {"alternative", category_map["concerts"], 90},
  {"country", category_map["concerts"], 90},
  {"folk", category_map["concerts"], 90},
  {"blues", category_map["concerts"], 90},
  {"classical", category_map["concerts"], 90}
]

bit_count = Enum.reduce(bandsintown_mappings, 0, fn {value, category_id, priority}, acc ->
  if category_id do
    attrs = %{
      external_source: "bandsintown",
      external_type: nil,
      external_value: value,
      external_locale: "en",
      category_id: category_id,
      priority: priority,
      metadata: %{"source" => "seed", "created_at" => DateTime.utc_now()}
    }

    case Repo.get_by(CategoryMapping,
      external_source: attrs.external_source,
      external_value: attrs.external_value
    ) do
      nil ->
        %CategoryMapping{} |> CategoryMapping.changeset(attrs) |> Repo.insert!()
        acc + 1
      _ ->
        acc
    end
  else
    acc
  end
end)

IO.puts("  Created #{bit_count} Bandsintown mappings")

total_mappings = Repo.one(from cm in CategoryMapping, select: count(cm.id))
IO.puts("\n✅ Category mappings seeded! Total mappings: #{total_mappings}")