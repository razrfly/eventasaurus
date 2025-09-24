defmodule EventasaurusApp.Events.EventUser do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.SoftDelete.Schema

  schema "event_users" do
    field(:role, :string)

    belongs_to(:event, EventasaurusApp.Events.Event)
    belongs_to(:user, EventasaurusApp.Accounts.User)

    # Deletion metadata fields
    field(:deletion_reason, :string)
    belongs_to(:deleted_by_user, EventasaurusApp.Accounts.User, foreign_key: :deleted_by_user_id)

    timestamps()
    soft_delete_schema()
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
