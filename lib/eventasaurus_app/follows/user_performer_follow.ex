defmodule EventasaurusApp.Follows.UserPerformerFollow do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_performer_follows" do
    belongs_to(:user, EventasaurusApp.Accounts.User)
    belongs_to(:performer, EventasaurusDiscovery.Performers.Performer)

    timestamps()
  end

  @doc false
  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:user_id, :performer_id])
    |> validate_required([:user_id, :performer_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:performer_id)
    |> unique_constraint([:user_id, :performer_id])
  end
end
