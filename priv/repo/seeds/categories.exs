# Category seeds for EventasaurusDiscovery

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Categories.Category

categories = [
  %{
    name: "Festivals",
    slug: "festivals",
    description: "Music festivals, cultural festivals, and multi-day events",
    icon: "🎪",
    color: "#FF6B6B",
    display_order: 1
  },
  %{
    name: "Concerts",
    slug: "concerts",
    description: "Live music performances and shows",
    icon: "🎵",
    color: "#4ECDC4",
    display_order: 2
  },
  %{
    name: "Performances",
    slug: "performances",
    description: "Theater, dance, comedy, and other live performances",
    icon: "🎭",
    color: "#95E77E",
    display_order: 3
  },
  %{
    name: "Literature",
    slug: "literature",
    description: "Book readings, author talks, and literary events",
    icon: "📚",
    color: "#FFE66D",
    display_order: 4
  },
  %{
    name: "Film",
    slug: "film",
    description: "Movie screenings, film festivals, and cinema events",
    icon: "🎬",
    color: "#A8E6CF",
    display_order: 5
  },
  %{
    name: "Exhibitions",
    slug: "exhibitions",
    description: "Art exhibitions, museum shows, and gallery events",
    icon: "🖼️",
    color: "#C7B8FF",
    display_order: 6
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