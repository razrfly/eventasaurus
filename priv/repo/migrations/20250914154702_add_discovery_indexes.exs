defmodule EventasaurusApp.Repo.Migrations.AddDiscoveryIndexes do
  use Ecto.Migration

  def change do
    # Composite index for city-based event discovery queries
    # Optimizes: "upcoming events in a specific city"
    create index(:public_events, [:venue_id, :starts_at],
      name: :public_events_venue_upcoming_idx
    )

    # Index for upcoming events across all cities
    # Optimizes: "all upcoming events"
    create index(:public_events, [:starts_at],
      name: :public_events_upcoming_idx
    )

    # Composite index for venue-city-country queries
    # Optimizes joins from events -> venues -> cities -> countries
    create index(:venues, [:city_id, :id],
      name: :venues_city_lookup_idx
    )

    # Index for city-country joins
    # Optimizes city -> country lookups for location display
    create index(:cities, [:country_id, :id],
      name: :cities_country_lookup_idx
    )

    # Compound index for event discovery with venue preloading
    # Optimizes: event queries that need venue and location data
    create index(:public_events, [:starts_at, :venue_id],
      name: :public_events_discovery_idx
    )

    # Additional indexes for efficient discovery queries
    create index(:public_events, [:venue_id, :starts_at, :id],
      name: :public_events_venue_time_id_idx
    )
  end
end
