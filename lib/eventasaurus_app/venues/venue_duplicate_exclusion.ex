defmodule EventasaurusApp.Venues.VenueDuplicateExclusion do
  @moduledoc """
  Tracks venue pairs that have been explicitly marked as "not duplicates".

  When two venues are flagged as potential duplicates but an admin determines
  they are actually different venues, this exclusion prevents them from being
  shown as duplicates again.

  The venue_id_1 and venue_id_2 are always stored with venue_id_1 < venue_id_2
  to ensure consistent storage and prevent storing both (A, B) and (B, A).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Venues.Venue

  schema "venue_duplicate_exclusions" do
    # The two venues in the excluded pair (always venue_id_1 < venue_id_2)
    belongs_to(:venue_1, Venue, foreign_key: :venue_id_1)
    belongs_to(:venue_2, Venue, foreign_key: :venue_id_2)

    # Who marked them as not duplicates
    belongs_to(:excluded_by_user, User, foreign_key: :excluded_by_user_id)

    # Optional reason for the exclusion
    field(:reason, :string)

    timestamps()
  end

  @required_fields [:venue_id_1, :venue_id_2]
  @optional_fields [:excluded_by_user_id, :reason]

  def changeset(exclusion, attrs) do
    exclusion
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> normalize_venue_ids()
    |> foreign_key_constraint(:venue_id_1)
    |> foreign_key_constraint(:venue_id_2)
    |> foreign_key_constraint(:excluded_by_user_id)
    |> unique_constraint([:venue_id_1, :venue_id_2], name: :venue_duplicate_exclusions_pair_index)
  end

  # Ensure venue_id_1 < venue_id_2 for consistent storage
  defp normalize_venue_ids(changeset) do
    case {get_field(changeset, :venue_id_1), get_field(changeset, :venue_id_2)} do
      {id1, id2} when is_integer(id1) and is_integer(id2) and id1 > id2 ->
        changeset
        |> put_change(:venue_id_1, id2)
        |> put_change(:venue_id_2, id1)

      _ ->
        changeset
    end
  end

  @doc """
  Normalizes a pair of venue IDs so the smaller ID is first.
  """
  def normalize_pair(id1, id2) when id1 > id2, do: {id2, id1}
  def normalize_pair(id1, id2), do: {id1, id2}
end
