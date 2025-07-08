defmodule Eventasaurus.Repo.Migrations.CreateGenericPollingSystem do
  use Ecto.Migration

  def up do
    # Create polls table for generic polling framework
    create table(:polls) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all), null: false

      # Poll metadata
      add :title, :string, null: false
      add :description, :text

            # Poll type determines the content being polled
      # No constraints - flexible to add new types: movie, book, restaurant, activity, music, custom, etc.
      add :poll_type, :string, null: false

      # Voting system determines how users vote
      # No constraints - flexible to add new systems: binary, approval, ranked, star, etc.
      add :voting_system, :string, null: false

      # Poll lifecycle
      add :phase, :string, null: false, default: "list_building"  # list_building, voting, closed
      add :list_building_deadline, :utc_datetime
      add :voting_deadline, :utc_datetime
      add :finalized_date, :date

      # Configuration
      add :max_options_per_user, :integer  # limit suggestions per user during list building
      # All users must be authenticated - no anonymous functionality

      # Results and moderation
      add :auto_finalize, :boolean, default: false
      add :finalized_option_ids, {:array, :integer}  # IDs of winning options

      timestamps()
    end

    # Create poll_options table for individual poll choices
    create table(:poll_options) do
      add :poll_id, references(:polls, on_delete: :delete_all), null: false
      add :suggested_by_id, references(:users, on_delete: :nilify_all), null: false  # user required

            # Option content - completely generic text-based options
      add :title, :string, null: false
      add :description, :text

      # API integration for rich content (movies, books, restaurants, etc)
      add :external_id, :string      # TMDb ID, Google Books ID, Yelp ID, etc
      add :external_data, :map       # JSON data from external APIs
      add :image_url, :string
      add :metadata, :map            # Additional structured data

      # Lifecycle and ordering
      add :status, :string, null: false, default: "active"  # active, hidden, removed
      add :order_index, :integer, default: 0  # for manual ordering

      timestamps()
    end

    # Create poll_votes table for user votes
    create table(:poll_votes) do
      add :poll_option_id, references(:poll_options, on_delete: :delete_all), null: false
      add :voter_id, references(:users, on_delete: :delete_all), null: false  # user required
      add :poll_id, references(:polls, on_delete: :delete_all), null: false  # denormalized for performance

      # Vote value depends on voting system
      # binary: "yes", "no"
      # approval: "selected"
      # ranked: "1", "2", "3", etc (rank number)
      # star: "1", "2", "3", "4", "5" (star rating)
      add :vote_value, :string, null: false

      # For ranked voting, track the rank order
      add :rank_order, :integer

      # For star rating, numeric value for easier aggregation
      add :rating_value, :decimal, precision: 3, scale: 2

      # Metadata
      add :voted_at, :utc_datetime, null: false

      timestamps()
    end

    # Indexes for performance
    create index(:polls, [:event_id])
    create index(:polls, [:created_by_id])
    create index(:polls, [:poll_type])
    create index(:polls, [:phase])
    create index(:polls, [:list_building_deadline])
    create index(:polls, [:voting_deadline])
    create index(:polls, [:poll_type, :phase])

    create index(:poll_options, [:poll_id])
    create index(:poll_options, [:suggested_by_id])
    create index(:poll_options, [:external_id])
    create index(:poll_options, [:status])
    create index(:poll_options, [:poll_id, :status])
    create index(:poll_options, [:poll_id, :order_index])

    create index(:poll_votes, [:poll_option_id])
    create index(:poll_votes, [:voter_id])
    create index(:poll_votes, [:poll_id])
    create index(:poll_votes, [:poll_id, :voter_id])
    create index(:poll_votes, [:voted_at])

        # Constraints
    # Prevent multiple active polls of same type per event (date polling uses separate system)
    create unique_index(:polls, [:event_id, :poll_type],
      name: :polls_event_poll_type_unique,
      where: "phase != 'closed'"
    )

    # Prevent duplicate suggestions per user per poll
    create unique_index(:poll_options, [:poll_id, :suggested_by_id, :title],
      name: :poll_options_unique_per_user
    )

        # Check constraints for core system values only (flexible poll_type and voting_system)
    # Note: poll_type and voting_system have no constraints to allow easy addition of new types

    execute """
    ALTER TABLE polls ADD CONSTRAINT valid_phase
    CHECK (phase IN ('list_building', 'voting', 'closed'))
    """

    execute """
    ALTER TABLE poll_options ADD CONSTRAINT valid_status
    CHECK (status IN ('active', 'hidden', 'removed'))
    """
  end

    def down do
    # Drop constraints first
    execute "ALTER TABLE polls DROP CONSTRAINT valid_phase"
    execute "ALTER TABLE poll_options DROP CONSTRAINT valid_status"

    drop table(:poll_votes)
    drop table(:poll_options)
    drop table(:polls)
  end
end
