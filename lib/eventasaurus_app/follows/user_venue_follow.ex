defmodule EventasaurusApp.Follows.UserVenueFollow do
  @moduledoc """
  Schema representing a user following a venue.

  This is a join table that creates a many-to-many relationship between
  users and venues. Each record represents one user following one venue.

  ## Fields

  - `user_id` - The ID of the user who is following
  - `venue_id` - The ID of the venue being followed
  - `inserted_at` - When the follow relationship was created
  - `updated_at` - When the record was last updated

  ## Constraints

  - Unique constraint on `[user_id, venue_id]` prevents duplicate follows
  - Foreign key constraints ensure referential integrity
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          venue_id: integer() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_venue_follows" do
    belongs_to(:user, EventasaurusApp.Accounts.User)
    belongs_to(:venue, EventasaurusApp.Venues.Venue)

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a user-venue follow.

  ## Parameters

  - `follow` - The `%UserVenueFollow{}` struct
  - `attrs` - Map of attributes with `:user_id` and `:venue_id`

  ## Validations

  - `user_id` is required
  - `venue_id` is required
  - Foreign key constraints on both IDs
  - Unique constraint on the combination of user_id and venue_id
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:user_id, :venue_id])
    |> validate_required([:user_id, :venue_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint([:user_id, :venue_id])
  end
end
