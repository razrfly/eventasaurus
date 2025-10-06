defmodule EventasaurusApp.Repo.Migrations.CreatePublicEventContainers do
  use Ecto.Migration

  def change do
    # Create enum for container types
    execute(
      """
      CREATE TYPE container_type AS ENUM (
        'festival',
        'conference',
        'tour',
        'series',
        'exhibition',
        'tournament',
        'unknown'
      )
      """,
      "DROP TYPE container_type"
    )

    # Create public_event_containers table
    create table(:public_event_containers) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :container_type, :container_type, null: false, default: "unknown"
      add :description, :text

      # Temporal scope
      add :start_date, :utc_datetime, null: false
      add :end_date, :utc_datetime

      # If container came from scraped umbrella event (optional)
      add :source_event_id, references(:public_events, on_delete: :nilify_all)
      add :source_id, references(:sources, on_delete: :nilify_all)

      # Pattern matching data for auto-association
      add :title_pattern, :string
      add :venue_pattern, :string

      # Additional metadata from source
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    # Indexes for performance
    create unique_index(:public_event_containers, [:slug])
    create index(:public_event_containers, [:title_pattern])
    create index(:public_event_containers, [:start_date, :end_date])
    create index(:public_event_containers, [:container_type])
    create index(:public_event_containers, [:source_event_id])
    create index(:public_event_containers, [:source_id])

    # Create enum for association methods
    execute(
      """
      CREATE TYPE association_method AS ENUM (
        'explicit',
        'title_match',
        'date_range',
        'artist_overlap',
        'venue_pattern',
        'manual'
      )
      """,
      "DROP TYPE association_method"
    )

    # Create public_event_container_memberships table
    create table(:public_event_container_memberships) do
      add :container_id, references(:public_event_containers, on_delete: :delete_all), null: false
      add :event_id, references(:public_events, on_delete: :delete_all), null: false

      # How was this association determined?
      add :association_method, :association_method, null: false
      add :confidence_score, :decimal, precision: 3, scale: 2, default: 1.0, null: false

      timestamps()
    end

    # Ensure unique container-event pairs
    create unique_index(:public_event_container_memberships, [:container_id, :event_id])

    # Indexes for queries
    create index(:public_event_container_memberships, [:container_id])
    create index(:public_event_container_memberships, [:event_id])
    create index(:public_event_container_memberships, [:confidence_score])
    create index(:public_event_container_memberships, [:association_method])

    # Check constraint for confidence score
    create constraint(:public_event_container_memberships, :confidence_score_range,
             check: "confidence_score >= 0 AND confidence_score <= 1"
           )
  end
end
