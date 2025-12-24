defmodule EventasaurusApp.Follows.UserPerformerFollow do
  @moduledoc """
  Schema representing a user following a performer.

  This is a join table that creates a many-to-many relationship between
  users and performers. Each record represents one user following one performer.

  ## Fields

  - `user_id` - The ID of the user who is following
  - `performer_id` - The ID of the performer being followed
  - `inserted_at` - When the follow relationship was created
  - `updated_at` - When the record was last updated

  ## Constraints

  - Unique constraint on `[user_id, performer_id]` prevents duplicate follows
  - Foreign key constraints ensure referential integrity
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          performer_id: integer() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_performer_follows" do
    belongs_to(:user, EventasaurusApp.Accounts.User)
    belongs_to(:performer, EventasaurusDiscovery.Performers.Performer)

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating a user-performer follow.

  ## Parameters

  - `follow` - The `%UserPerformerFollow{}` struct
  - `attrs` - Map of attributes with `:user_id` and `:performer_id`

  ## Validations

  - `user_id` is required
  - `performer_id` is required
  - Foreign key constraints on both IDs
  - Unique constraint on the combination of user_id and performer_id
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:user_id, :performer_id])
    |> validate_required([:user_id, :performer_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:performer_id)
    |> unique_constraint([:user_id, :performer_id])
  end
end
