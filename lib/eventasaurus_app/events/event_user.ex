defmodule EventasaurusApp.Events.EventUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_users" do
    field :role, :string

    belongs_to :event, EventasaurusApp.Events.Event
    belongs_to :user, EventasaurusApp.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(event_user, attrs) do
    event_user
    |> cast(attrs, [:event_id, :user_id, :role])
    |> validate_required([:event_id, :user_id])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:event_id, :user_id])
  end
end
