defmodule EventasaurusDiscovery.PublicEvents.PublicEvent.Slug do
  use EctoAutoslugField.Slug, from: :title, to: :slug
end

defmodule EventasaurusDiscovery.PublicEvents.PublicEvent do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.PublicEvents.PublicEvent.Slug

  schema "public_events" do
    field :title, :string
    field :slug, Slug.Type
    field :description, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :source_id, :integer
    field :external_id, :string
    field :ticket_url, :string
    field :min_price, :decimal
    field :max_price, :decimal
    field :currency, :string
    field :metadata, :map, default: %{}

    belongs_to :venue, EventasaurusApp.Venues.Venue
    belongs_to :category, EventasaurusDiscovery.Categories.Category

    many_to_many :performers, EventasaurusDiscovery.Performers.Performer,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
      join_keys: [event_id: :id, performer_id: :id]

    timestamps()
  end

  @doc false
  def changeset(public_event, attrs) do
    public_event
    |> cast(attrs, [:title, :description, :starts_at, :ends_at, :venue_id,
                    :source_id, :external_id, :ticket_url, :min_price,
                    :max_price, :currency, :metadata, :category_id])
    |> validate_required([:title])
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    |> unique_constraint([:external_id, :source_id])
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:category_id)
  end
end