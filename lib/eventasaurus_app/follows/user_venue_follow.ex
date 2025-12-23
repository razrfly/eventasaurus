defmodule EventasaurusApp.Follows.UserVenueFollow do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_venue_follows" do
    belongs_to(:user, EventasaurusApp.Accounts.User)
    belongs_to(:venue, EventasaurusApp.Venues.Venue)

    timestamps()
  end

  @doc false
  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:user_id, :venue_id])
    |> validate_required([:user_id, :venue_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint([:user_id, :venue_id])
  end
end
