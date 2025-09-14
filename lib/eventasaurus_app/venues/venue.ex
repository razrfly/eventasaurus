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
  import Ecto.Query
  alias EventasaurusApp.Venues.Venue.Slug

  schema "venues" do
    field :name, :string
    field :normalized_name, :string
    field :slug, Slug.Type
    field :address, :string
    field :city, :string  # Legacy field for backwards compatibility
    field :state, :string
    field :country, :string  # Legacy field for backwards compatibility
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
    |> cast(attrs, [:name, :address, :city, :state, :country, :latitude, :longitude,
                    :venue_type, :place_id, :source, :city_id])
    |> validate_required([:name, :venue_type])
    |> validate_inclusion(:venue_type, @valid_venue_types, message: "must be one of: #{Enum.join(@valid_venue_types, ", ")}")
    |> update_change(:source, fn s -> if is_binary(s), do: String.downcase(s), else: s end)
    |> validate_inclusion(:source, ["user", "scraper", "google"])
    |> validate_length(:place_id, max: 255)
    |> validate_place_id_source()
    |> maybe_set_city_id_from_strings()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    |> unique_constraint([:normalized_name, :city_id])
    |> unique_constraint(:place_id)
    |> foreign_key_constraint(:city_id)
  end

  # Dual support: if city/country strings are provided but no city_id,
  # try to find or create the normalized city record
  defp maybe_set_city_id_from_strings(changeset) do
    city_id = get_field(changeset, :city_id)
    city_name = get_change(changeset, :city) || get_field(changeset, :city)
    country_name = get_change(changeset, :country) || get_field(changeset, :country)

    cond do
      # If city_id already set, use it
      not is_nil(city_id) ->
        changeset

      # If we have city and country strings, try to find/create normalized record
      not is_nil(city_name) and not is_nil(country_name) and city_name != "" and country_name != "" ->
        case find_or_create_city_from_strings(city_name, country_name) do
          {:ok, city} ->
            require Logger
            Logger.info("✅ Created/found city_id #{city.id} for #{city_name}, #{country_name}")
            put_change(changeset, :city_id, city.id)
          {:error, reason} ->
            # Log the error but don't fail the changeset - fall back to string fields
            require Logger
            Logger.warning("Could not normalize city: #{city_name}, #{country_name} - #{inspect(reason)}")
            changeset
        end

      # Log if we have partial city information
      not is_nil(city_name) or not is_nil(country_name) ->
        require Logger
        Logger.warning("Incomplete city data - city: #{inspect(city_name)}, country: #{inspect(country_name)}")
        changeset

      # No city information - leave as is
      true ->
        changeset
    end
  end

  # Helper to find or create city from string inputs
  defp find_or_create_city_from_strings(city_name, country_name) do
    try do
      case find_or_create_country(country_name) do
        nil -> {:error, :unknown_country}
        country ->
          city = find_or_create_city(city_name, country)
          {:ok, city}
      end
    rescue
      e ->
        require Logger
        Logger.error("Failed to create city/country: #{Exception.message(e)}")
        {:error, :city_creation_failed}
    end
  end

  defp find_or_create_country(country_name) when is_binary(country_name) do
    # Use the Countries library to properly handle country lookups
    country_data = find_country_data(country_name)

    if country_data do
      # Try to find existing country in our DB
      country = EventasaurusApp.Repo.get_by(EventasaurusDiscovery.Locations.Country, code: country_data.alpha2) ||
                EventasaurusApp.Repo.get_by(EventasaurusDiscovery.Locations.Country, name: country_data.name)

      if country do
        country
      else
        # Create new country with proper data from Countries library
        %EventasaurusDiscovery.Locations.Country{}
        |> EventasaurusDiscovery.Locations.Country.changeset(%{
          name: country_data.name,
          code: country_data.alpha2
        })
        |> EventasaurusApp.Repo.insert!()
      end
    else
      # Country not found in library - this shouldn't happen for real countries
      require Logger
      Logger.error("Unknown country: #{country_name}")
      nil  # Return nil to signal failure
    end
  end
  defp find_or_create_country(_), do: nil

  defp find_country_data(country_input) when is_binary(country_input) do
    input = String.trim(country_input)

    # Try multiple strategies to find the country
    # 1. Try as country code (2 or 3 letter)
    country = if String.length(input) <= 3 do
      Countries.get(String.upcase(input))
    end

    # 2. Try by exact name
    country = country || case Countries.filter_by(:name, input) do
      [c | _] -> c
      _ -> nil
    end

    # 3. Try by unofficial names (aliases)
    country = country || case Countries.filter_by(:unofficial_names, input) do
      [c | _] -> c
      _ -> nil
    end

    country
  end

  defp find_or_create_city(city_name, country) do
    normalized_name = String.trim(city_name)

    # Try to find existing city in the same country
    city = from(c in EventasaurusDiscovery.Locations.City,
      where: c.name == ^normalized_name and c.country_id == ^country.id
    ) |> EventasaurusApp.Repo.one()

    if city do
      city
    else
      # Create new city (let changeset handle slug generation)
      %EventasaurusDiscovery.Locations.City{}
      |> EventasaurusDiscovery.Locations.City.changeset(%{
        name: normalized_name,
        country_id: country.id
      })
      |> EventasaurusApp.Repo.insert!()
    end
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
  def city_name(%{city: city}) when is_binary(city), do: city
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
  def country_name(%{country: country}) when is_binary(country), do: country
  def country_name(_), do: nil

  @doc """
  Gets the full location string (city, country) using the best available data.
  """
  def location_string(venue) do
    city = city_name(venue)
    country = country_name(venue)
    state = venue.state

    parts = [city, state, country]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end
end