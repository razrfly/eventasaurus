# Seeds for category mappings and translations
# Run with: mix run priv/repo/category_seeds.exs

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Categories
alias EventasaurusDiscovery.Categories.{Category, CategoryMapping}

IO.puts("🌱 Starting category seed data...")

# Create category mappings
IO.puts("\n📝 Creating category mappings...")
mappings = [
  # Ticketmaster mappings
  %{external_source: "ticketmaster", external_type: "segment", external_value: "Music", category_slug: "concerts", priority: 10},
  %{external_source: "ticketmaster", external_type: "genre", external_value: "Rock", category_slug: "concerts", priority: 8},
  %{external_source: "ticketmaster", external_type: "genre", external_value: "Pop", category_slug: "concerts", priority: 8},
  %{external_source: "ticketmaster", external_type: "genre", external_value: "Classical", category_slug: "concerts", priority: 8},
  %{external_source: "ticketmaster", external_type: "genre", external_value: "Jazz", category_slug: "concerts", priority: 8},
  %{external_source: "ticketmaster", external_type: "genre", external_value: "Electronic", category_slug: "festivals", priority: 7},
  %{external_source: "ticketmaster", external_type: "segment", external_value: "Arts & Theatre", category_slug: "performances", priority: 10},
  %{external_source: "ticketmaster", external_type: "genre", external_value: "Theatre", category_slug: "performances", priority: 8},
  %{external_source: "ticketmaster", external_type: "segment", external_value: "Film", category_slug: "film", priority: 10},
  %{external_source: "ticketmaster", external_type: "segment", external_value: "Sports", category_slug: "concerts", priority: 3},
  %{external_source: "ticketmaster", external_type: "subGenre", external_value: "Festival", category_slug: "festivals", priority: 9},

  # Karnet mappings (Polish)
  %{external_source: "karnet", external_type: nil, external_value: "koncerty", category_slug: "concerts", priority: 10},
  %{external_source: "karnet", external_type: nil, external_value: "festiwale", category_slug: "festivals", priority: 10},
  %{external_source: "karnet", external_type: nil, external_value: "spektakle", category_slug: "performances", priority: 10},
  %{external_source: "karnet", external_type: nil, external_value: "wystawy", category_slug: "exhibitions", priority: 10},
  %{external_source: "karnet", external_type: nil, external_value: "literatura", category_slug: "literature", priority: 10},
  %{external_source: "karnet", external_type: nil, external_value: "film", category_slug: "film", priority: 10},
  %{external_source: "karnet", external_type: nil, external_value: "festival", category_slug: "festivals", priority: 10},

  # Bandsintown mappings
  %{external_source: "bandsintown", external_type: nil, external_value: "concert", category_slug: "concerts", priority: 10},
  %{external_source: "bandsintown", external_type: nil, external_value: "music", category_slug: "concerts", priority: 10}
]

created_mappings = 0
Enum.each(mappings, fn mapping ->
  category = Repo.get_by(Category, slug: mapping.category_slug)

  if category do
    case Repo.insert(%CategoryMapping{
      external_source: mapping.external_source,
      external_type: mapping.external_type,
      external_value: mapping.external_value,
      category_id: category.id,
      priority: mapping.priority
    }, on_conflict: :nothing, conflict_target: [:external_source, :external_type, :external_value]) do
      {:ok, _} ->
        IO.puts("  ✅ Created mapping: #{mapping.external_source}/#{mapping.external_value} → #{mapping.category_slug}")
        created_mappings = created_mappings + 1
      _ ->
        IO.puts("  ⏭️  Mapping already exists: #{mapping.external_source}/#{mapping.external_value}")
    end
  else
    IO.puts("  ⚠️  Category not found: #{mapping.category_slug}")
  end
end)

IO.puts("Created #{created_mappings} new mappings")

# Add Polish translations
IO.puts("\n🌍 Adding Polish translations to categories...")
translations = %{
  "concerts" => %{
    "pl" => %{
      "name" => "Koncerty",
      "description" => "Wydarzenia muzyczne na żywo"
    }
  },
  "festivals" => %{
    "pl" => %{
      "name" => "Festiwale",
      "description" => "Duże wydarzenia wielodniowe"
    }
  },
  "performances" => %{
    "pl" => %{
      "name" => "Spektakle",
      "description" => "Przedstawienia teatralne i występy"
    }
  },
  "exhibitions" => %{
    "pl" => %{
      "name" => "Wystawy",
      "description" => "Wystawy sztuki i muzealne"
    }
  },
  "film" => %{
    "pl" => %{
      "name" => "Film",
      "description" => "Pokazy filmowe i kino"
    }
  },
  "conferences" => %{
    "pl" => %{
      "name" => "Konferencje",
      "description" => "Wydarzenia biznesowe i edukacyjne"
    }
  }
}

updated_categories = 0
Enum.each(translations, fn {slug, trans} ->
  category = Repo.get_by(Category, slug: slug)
  if category do
    case Categories.update_category(category, %{translations: trans}) do
      {:ok, _} ->
        IO.puts("  ✅ Added Polish translation for: #{slug}")
        updated_categories = updated_categories + 1
      {:error, reason} ->
        IO.puts("  ❌ Failed to update #{slug}: #{inspect(reason)}")
    end
  else
    IO.puts("  ⚠️  Category not found: #{slug}")
  end
end)

IO.puts("\nUpdated #{updated_categories} categories with Polish translations")

IO.puts("\n✨ Category seed data complete!")