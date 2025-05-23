defmodule EventasaurusApp.Events.EventParticipant do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

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
    |> validate_not_event_user()
  end

  defp validate_not_event_user(changeset) do
    event_id = get_field(changeset, :event_id)
    user_id = get_field(changeset, :user_id)

    if event_id && user_id do
      # Check if user is already an event_user (organizer/admin) for this event
      query = from eu in EventasaurusApp.Events.EventUser,
              where: eu.event_id == ^event_id and eu.user_id == ^user_id

      case EventasaurusApp.Repo.one(query) do
        nil ->
          # User is not an event_user, validation passes
          changeset
        _event_user ->
          # User is already an event_user, add error
          add_error(changeset, :user_id, "cannot be a participant because they are already an organizer/admin for this event")
      end
    else
      changeset
    end
  end
end
