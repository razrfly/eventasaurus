# Category seeds for EventasaurusDiscovery

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Categories.Category

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
  },
  %{
    name: "Trivia",
    slug: "trivia",
    description: "Trivia nights, pub quizzes, and knowledge competitions",
    icon: "🧠",
    color: "#9B59B6",
    display_order: 14
  },
  %{
    name: "Other",
    slug: "other",
    description: "Uncategorized events",
    icon: "📌",
    color: "#808080",
    display_order: 999
  }
]

Enum.each(categories, fn category_attrs ->
  # Use insert with on_conflict option to avoid conflicts with migration data
  # Only replace the fields we're actually setting to avoid NULLing translations, is_active, parent_id
  %Category{}
  |> Category.changeset(category_attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:name, :description, :icon, :color, :display_order, :updated_at]},
    conflict_target: :slug
  )
  IO.puts("✅ Category ready: #{category_attrs.name}")
end)

IO.puts("\n✅ Categories seeded successfully!")

# Note: Category mappings are seeded from priv/category_mappings_archived/
# See: category_mappings.exs for the seed logic