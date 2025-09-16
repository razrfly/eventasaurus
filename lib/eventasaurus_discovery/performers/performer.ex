defmodule EventasaurusDiscovery.Performers.Performer.Slug do
  use EctoAutoslugField.Slug, from: :name, to: :slug
end

defmodule EventasaurusDiscovery.Performers.Performer do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.Performers.Performer.Slug

  schema "performers" do
    field :name, :string
    field :slug, Slug.Type
    field :image_url, :string
    field :metadata, :map, default: %{}
    field :source_id, :integer  # Reference to scraping source

    many_to_many :public_events, EventasaurusDiscovery.PublicEvents.PublicEvent,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
      on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(performer, attrs) do
    performer
    |> cast(attrs, [:name, :image_url, :metadata, :source_id])
    |> validate_required([:name])
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
  end
end