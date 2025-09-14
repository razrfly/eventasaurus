defmodule EventasaurusDiscovery.Locations.City.Slug do
  use EctoAutoslugField.Slug, from: :name, to: :slug
end

defmodule EventasaurusDiscovery.Locations.City do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.Locations.City.Slug

  schema "cities" do
    field :name, :string
    field :slug, Slug.Type
    field :latitude, :decimal
    field :longitude, :decimal

    belongs_to :country, EventasaurusDiscovery.Locations.Country
    has_many :venues, EventasaurusApp.Venues.Venue

    timestamps()
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [:name, :country_id, :latitude, :longitude])
    |> validate_required([:name, :country_id])
    |> Slug.maybe_generate_slug()
    |> foreign_key_constraint(:country_id)
    |> unique_constraint([:country_id, :slug])
  end
end