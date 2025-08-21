defmodule EventasaurusApp.Events.EventActivity do
  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Groups.Group
  alias EventasaurusApp.Accounts.User

  schema "event_activities" do
    field :activity_type, :string
    field :metadata, :map, default: %{}
    field :occurred_at, :utc_datetime
    field :source, :string

    belongs_to :event, Event
    belongs_to :group, Group
    belongs_to :created_by, User, foreign_key: :created_by_id

    timestamps()
  end

  @required_fields [:event_id, :activity_type, :metadata, :created_by_id]
  @optional_fields [:group_id, :occurred_at, :source]

  @doc false
  def changeset(event_activity, attrs) do
    event_activity
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_activity_type()
    |> validate_metadata()
    |> maybe_set_occurred_at()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:created_by_id)
  end

  defp validate_activity_type(changeset) do
    changeset
    |> validate_inclusion(:activity_type, [
      "movie_watched",
      "tv_watched",
      "game_played",
      "book_read",
      "restaurant_visited",
      "place_visited",
      "activity_completed",
      "custom"
    ])
  end

  defp validate_metadata(changeset) do
    changeset
    |> validate_change(:metadata, fn :metadata, metadata ->
      if is_map(metadata) do
        []
      else
        [metadata: "must be a map"]
      end
    end)
  end

  defp maybe_set_occurred_at(changeset) do
    if get_change(changeset, :occurred_at) == nil do
      put_change(changeset, :occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      changeset
    end
  end
end