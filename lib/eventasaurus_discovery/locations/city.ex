defmodule EventasaurusDiscovery.Locations.City.Slug do
  use EctoAutoslugField.Slug, from: :name, to: :slug
end

defmodule EventasaurusDiscovery.Locations.City do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.Locations.City.Slug

  schema "cities" do
    field(:name, :string)
    field(:slug, Slug.Type)
    field(:latitude, :decimal)
    field(:longitude, :decimal)
    field(:discovery_enabled, :boolean, default: false)
    field(:discovery_config, :map)

    belongs_to(:country, EventasaurusDiscovery.Locations.Country)
    has_many(:venues, EventasaurusApp.Venues.Venue)

    timestamps()
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [
      :name,
      :country_id,
      :latitude,
      :longitude,
      :discovery_enabled,
      :discovery_config
    ])
    |> validate_required([:name, :country_id])
    |> Slug.maybe_generate_slug()
    |> foreign_key_constraint(:country_id)
    |> unique_constraint([:country_id, :slug])
  end

  @doc """
  Changeset for deleting a city.
  Adds constraint to prevent deletion when city has venues.
  """
  def delete_changeset(city) do
    city
    |> cast(%{}, [])
    |> check_constraint(:id, name: :venues_city_id_required_for_non_regional, message: "has venues")
  end

  @doc """
  Changeset for enabling discovery on a city.
  """
  def enable_discovery_changeset(city, attrs \\ %{}) do
    default_config = %{
      schedule: %{cron: "0 0 * * *", timezone: "UTC", enabled: true},
      sources: []
    }

    city
    |> cast(attrs, [:discovery_enabled])
    |> put_change(:discovery_enabled, true)
    |> put_change(:discovery_config, default_config)
  end

  @doc """
  Changeset for disabling discovery on a city.
  """
  def disable_discovery_changeset(city) do
    city
    |> cast(%{}, [])
    |> put_change(:discovery_enabled, false)
  end
end
