defmodule EventasaurusApp.Events.EventParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_participants" do
    field :role, Ecto.Enum, values: [:invitee, :poll_voter, :ticket_holder]
    field :status, Ecto.Enum, values: [:pending, :accepted, :declined]
    field :source, :string
    field :metadata, :map

    belongs_to :event, EventasaurusApp.Events.Event
    belongs_to :user, EventasaurusApp.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(event_participant, attrs) do
    event_participant
    |> cast(attrs, [:role, :status, :source, :metadata, :event_id, :user_id])
    |> validate_required([:role, :status, :event_id, :user_id])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:event_id, :user_id])
  end
end
