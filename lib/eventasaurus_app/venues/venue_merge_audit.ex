defmodule EventasaurusApp.Venues.VenueMergeAudit do
  @moduledoc """
  Audit trail for venue merge operations.

  Records all venue merges with full context for:
  - Tracking who merged what and when
  - Analyzing merge patterns for algorithm improvement
  - Potential rollback capability (via source_venue_snapshot)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Venues.Venue

  schema "venue_merge_audit" do
    # The venue that was deleted (ID stored since venue no longer exists)
    field(:source_venue_id, :integer)

    # The venue that received all the merged data
    belongs_to(:target_venue, Venue)

    # Who performed the merge (optional - could be system/automated)
    belongs_to(:merged_by_user, User, foreign_key: :merged_by_user_id)

    # Reason for the merge (e.g., "automatic", "manual", "geocoding_drift")
    field(:merge_reason, :string)

    # Similarity metrics at time of merge
    field(:similarity_score, :float)
    field(:distance_meters, :float)

    # Count of reassigned items
    field(:events_reassigned, :integer, default: 0)
    field(:public_events_reassigned, :integer, default: 0)

    # Full snapshot of source venue data for potential rollback
    field(:source_venue_snapshot, :map)

    timestamps()
  end

  @required_fields [:source_venue_id, :target_venue_id, :source_venue_snapshot]
  @optional_fields [
    :merged_by_user_id,
    :merge_reason,
    :similarity_score,
    :distance_meters,
    :events_reassigned,
    :public_events_reassigned
  ]

  def changeset(audit, attrs) do
    audit
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:target_venue_id)
    |> foreign_key_constraint(:merged_by_user_id)
  end

  @doc """
  Creates a snapshot of a venue for audit purposes.
  """
  def venue_snapshot(%Venue{} = venue) do
    %{
      id: venue.id,
      name: venue.name,
      normalized_name: venue.normalized_name,
      address: venue.address,
      city_id: venue.city_id,
      latitude: venue.latitude,
      longitude: venue.longitude,
      provider_ids: venue.provider_ids,
      slug: venue.slug,
      inserted_at: venue.inserted_at,
      updated_at: venue.updated_at
    }
  end
end
