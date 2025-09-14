defmodule EventasaurusApp.Venues.Venue.Slug do
  use EctoAutoslugField.Slug, to: :slug

  def get_sources(_changeset, _opts) do
    # Use name as primary source, but also include city_id for uniqueness
    [:name, :city_id]
  end

  def build_slug(sources, changeset) do
    # Get the default slug from name and city_id
    slug = super(sources, changeset)

    # Add some randomness to ensure uniqueness even for identical names + city_ids
    random_suffix = :rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")

    # Combine with random suffix
    "#{slug}-#{random_suffix}"
  end
end

defmodule EventasaurusApp.Venues.Venue do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Venues.Venue.Slug

  schema "venues" do
    field :name, :string
    field :normalized_name, :string
    field :slug, Slug.Type
    field :address, :string
    field :latitude, :float
    field :longitude, :float
    field :venue_type, :string, default: "venue"
    field :place_id, :string
    field :source, :string, default: "user"

    belongs_to :city_ref, EventasaurusDiscovery.Locations.City, foreign_key: :city_id
    has_many :events, EventasaurusApp.Events.Event
    has_many :public_events, EventasaurusDiscovery.PublicEvents.PublicEvent

    timestamps()
  end

  @valid_venue_types ["venue", "city", "region", "online", "tbd"]

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :address, :latitude, :longitude,
                    :venue_type, :place_id, :source, :city_id])
    |> validate_required([:name, :venue_type])
    |> validate_inclusion(:venue_type, @valid_venue_types, message: "must be one of: #{Enum.join(@valid_venue_types, ", ")}")
    |> update_change(:source, fn s -> if is_binary(s), do: String.downcase(s), else: s end)
    |> validate_inclusion(:source, ["user", "scraper", "google"])
    |> validate_length(:place_id, max: 255)
    |> validate_place_id_source()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    |> unique_constraint([:normalized_name, :city_id])
    |> unique_constraint(:place_id)
    |> foreign_key_constraint(:city_id)
  end


  defp validate_place_id_source(changeset) do
    source = get_field(changeset, :source)
    place_id = get_field(changeset, :place_id)

    cond do
      source == "google" and is_nil(place_id) ->
        add_error(changeset, :place_id, "is required when source is 'google'")
      not is_nil(place_id) and source == "user" ->
        add_error(changeset, :source, "cannot be 'user' when place_id is present")
      true ->
        changeset
    end
  end

  @doc """
  Returns the list of valid venue types.
  """
  def valid_venue_types, do: @valid_venue_types

  @doc """
  Returns user-friendly labels for venue types.
  """
  def venue_type_options do
    [
      {"Physical Venue", "venue"},
      {"City", "city"},
      {"Region", "region"},
      {"Online", "online"},
      {"To Be Determined", "tbd"}
    ]
  end

  @doc """
  Gets the city name, preferring the normalized city relationship over the string field.
  """
  def city_name(%{city_ref: %EventasaurusDiscovery.Locations.City{name: name}}), do: name
  def city_name(_), do: nil

  @doc """
  Gets the country name, preferring the normalized relationship over the string field.
  """
  def country_name(%{city_ref: %EventasaurusDiscovery.Locations.City{} = city}) do
    case city do
      %{country: %EventasaurusDiscovery.Locations.Country{name: name}} -> name
      _ -> nil
    end
  end
  def country_name(_), do: nil

  @doc """
  Gets the full location string (city, country) using the best available data.
  """
  def location_string(venue) do
    city = city_name(venue)
    country = country_name(venue)

    parts = [city, country]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end
end