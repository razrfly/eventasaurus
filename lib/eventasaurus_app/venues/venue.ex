defmodule EventasaurusApp.Venues.Venue.Slug do
  use EctoAutoslugField.Slug, to: :slug
  require Logger

  def get_sources(_changeset, _opts) do
    # Use name as primary source, but also include city_id for uniqueness
    [:name, :city_id]
  end

  def build_slug(sources, changeset) do
    # Universal UTF-8 protection for venue slugs
    # This handles the same issues as PublicEvent slugs
    safe_sources = sources |> Enum.map(&ensure_safe_string/1)

    # Only proceed if we have valid content
    case safe_sources do
      ["" | _] ->
        # Fallback slug if name is empty/invalid after cleaning
        "venue-#{DateTime.utc_now() |> DateTime.to_unix()}-#{random_suffix()}"

      _ ->
        # Get the default slug from cleaned sources
        slug = super(safe_sources, changeset)

        # Add some randomness to ensure uniqueness
        "#{slug}-#{random_suffix()}"
    end
  end

  # Universal UTF-8 safety function (same as PublicEvent.Slug)
  defp ensure_safe_string(value) do
    case value do
      # Handle error tuples from failed UTF-8 conversions
      {:error, _, invalid_bytes} ->
        Logger.warning("""
        Invalid UTF-8 detected in venue slug source
        Error tuple: #{inspect(value)}
        Invalid bytes: #{inspect(invalid_bytes, limit: 50)}
        """)

        ""

      # Handle valid binary strings
      str when is_binary(str) ->
        EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(str)

      # Handle nil values
      nil ->
        ""

      # Convert other types to string and ensure UTF-8
      other ->
        other
        |> to_string()
        |> EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8()
    end
  rescue
    # Catch any conversion errors and return empty string
    error ->
      Logger.error("Error in ensure_safe_string: #{inspect(error)}")
      ""
  end

  defp random_suffix do
    :rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")
  end
end

defmodule EventasaurusApp.Venues.Venue do
  @moduledoc """
  Venues represent physical locations where events take place.

  ## Venue Types
  - "venue": Specific locations (theaters, clubs, arenas) - REQUIRES city_id
  - "city": City-wide events (festivals, marathons) - REQUIRES city_id
  - "region": Regional events (Bay Area, Greater London) - city_id OPTIONAL

  ## Required Fields
  All venues MUST have:
  - GPS coordinates (latitude/longitude) - enforced at database level
  - city_id - required for "venue" and "city" types, optional for "region" type
    (enforced via CHECK constraint: venue_type = 'region' OR city_id IS NOT NULL)

  ## Virtual Events
  Virtual events do NOT use the Venue table. Instead, they use:
  - Event.is_virtual = true
  - Event.virtual_venue_url = "https://zoom.us/..."
  - Event.venue_id = NULL

  ## Events Without Determined Location
  Events where location is TBD should have:
  - Event.is_virtual = false
  - Event.venue_id = NULL (will be set later)
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Venues.Venue.Slug

  schema "venues" do
    field(:name, :string)
    field(:normalized_name, :string)
    field(:slug, Slug.Type)
    field(:address, :string)
    field(:latitude, :float)
    field(:longitude, :float)
    field(:venue_type, :string, default: "venue")
    field(:place_id, :string)
    field(:source, :string, default: "user")
    field(:metadata, :map)

    belongs_to(:city_ref, EventasaurusDiscovery.Locations.City, foreign_key: :city_id)
    has_many(:events, EventasaurusApp.Events.Event)
    has_many(:public_events, EventasaurusDiscovery.PublicEvents.PublicEvent)

    timestamps()
  end

  @valid_venue_types ["venue", "city", "region"]

  @doc false
  def changeset(venue, attrs) do
    # Universal UTF-8 protection for all venue data
    # This ensures clean data from all sources (Ticketmaster, Karnet, Bandsintown, etc.)
    cleaned_attrs = sanitize_attrs(attrs)

    venue
    |> cast(cleaned_attrs, [
      :name,
      :address,
      :latitude,
      :longitude,
      :venue_type,
      :place_id,
      :source,
      :city_id,
      :metadata
    ])
    |> validate_required_by_type()
    |> validate_inclusion(:venue_type, @valid_venue_types,
      message: "must be one of: #{Enum.join(@valid_venue_types, ", ")}"
    )
    |> update_change(:source, fn s -> if is_binary(s), do: String.downcase(s), else: s end)
    |> validate_inclusion(:source, ["user", "scraper", "google"])
    |> validate_length(:place_id, max: 255)
    |> validate_utf8_fields()
    |> validate_gps_coordinates()
    |> validate_place_id_source()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:place_id, name: :venues_place_id_unique_index)
    |> foreign_key_constraint(:city_id)
  end

  # All venues are physical locations requiring GPS coordinates
  # Virtual events use Event.is_virtual + Event.virtual_venue_url instead
  defp validate_required_by_type(changeset) do
    venue_type = get_field(changeset, :venue_type)

    case venue_type do
      "region" ->
        # Regional venues span multiple cities, city_id optional
        validate_required(changeset, [:name, :venue_type, :latitude, :longitude])

      _ ->
        # Physical venues (venue, city) require city_id
        validate_required(changeset, [:name, :venue_type, :latitude, :longitude, :city_id])
    end
  end

  # Universal UTF-8 sanitization for all venue attributes
  defp sanitize_attrs(attrs) when is_map(attrs) do
    EventasaurusDiscovery.Utils.UTF8.validate_map_strings(attrs)
  end

  defp sanitize_attrs(attrs), do: attrs

  # Validate that string fields contain valid UTF-8
  defp validate_utf8_fields(changeset) do
    changeset
    |> validate_change(:name, fn
      :name, name when is_binary(name) ->
        if String.valid?(name) do
          []
        else
          [name: "contains invalid UTF-8 characters after sanitization"]
        end

      :name, _ ->
        []
    end)
    |> validate_change(:address, fn
      :address, address when is_binary(address) ->
        if String.valid?(address) do
          []
        else
          [address: "contains invalid UTF-8 characters after sanitization"]
        end

      :address, _ ->
        []
    end)
  end

  defp validate_gps_coordinates(changeset) do
    lat = get_change(changeset, :latitude) || get_field(changeset, :latitude)
    lng = get_change(changeset, :longitude) || get_field(changeset, :longitude)

    cond do
      is_nil(lat) && is_nil(lng) ->
        changeset
        |> add_error(:latitude, "GPS coordinates are required for physical venues")
        |> add_error(:longitude, "GPS coordinates are required for physical venues")

      is_nil(lat) ->
        add_error(changeset, :latitude, "is required when longitude is provided")

      is_nil(lng) ->
        add_error(changeset, :longitude, "is required when latitude is provided")

      not is_number(lat) ->
        add_error(changeset, :latitude, "must be a number")

      not is_number(lng) ->
        add_error(changeset, :longitude, "must be a number")

      lat < -90 or lat > 90 ->
        add_error(changeset, :latitude, "must be between -90 and 90 degrees")

      lng < -180 or lng > 180 ->
        add_error(changeset, :longitude, "must be between -180 and 180 degrees")

      true ->
        changeset
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

  Note: All venue types represent physical locations requiring GPS coordinates.
  Virtual events use Event.is_virtual instead of creating a venue.
  """
  def venue_type_options do
    [
      {"Physical Venue", "venue"},
      {"City", "city"},
      {"Region", "region"}
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

    parts =
      [city, country]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end
end
