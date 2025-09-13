defmodule EventasaurusApp.PublicEvents.PublicEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "public_events" do
    field :external_id, :string
    field :title, :string
    field :slug, :string
    field :description, :string
    field :start_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :venue, EventasaurusApp.Venues.Venue
    belongs_to :city, EventasaurusApp.Locations.City

    has_many :public_event_sources, EventasaurusApp.PublicEvents.PublicEventSource, foreign_key: :event_id
    many_to_many :performers, EventasaurusApp.Performers.Performer,
      join_through: EventasaurusApp.PublicEvents.PublicEventPerformer

    timestamps()
  end

  @doc false
  def changeset(public_event, attrs) do
    public_event
    |> cast(attrs, [:external_id, :title, :slug, :description, :venue_id, :city_id,
                    :start_at, :ends_at, :status, :metadata])
    |> validate_required([:title, :slug, :city_id, :start_at])
    |> validate_inclusion(:status, ["active", "cancelled", "postponed"])
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:city_id)
  end
end