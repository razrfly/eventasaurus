defmodule EventasaurusApp.Venues.Venue.Slug do
  use EctoAutoslugField.Slug, to: :slug
  require Logger
  import Ecto.Query
  alias EventasaurusApp.Repo

  def get_sources(_changeset, _opts) do
    # Use name as primary source for slug generation
    [:name]
  end

  def build_slug(sources, changeset) do
    # Universal UTF-8 protection for venue slugs
    # This handles the same issues as PublicEvent slugs
    safe_sources = sources |> Enum.map(&ensure_safe_string/1)

    # Only proceed if we have valid content
    case safe_sources do
      ["" | _] ->
        # Fallback slug if name is empty/invalid after cleaning
        "venue-#{DateTime.utc_now() |> DateTime.to_unix()}"

      _ ->
        # Get the base slug from cleaned sources
        base_slug = super(safe_sources, changeset)

        # Ensure uniqueness using progressive disambiguation
        ensure_unique_slug(base_slug, changeset)
    end
  end

  # Ensure slug is unique using progressive disambiguation
  # Strategy: name -> name-city -> name-timestamp
  defp ensure_unique_slug(base_slug, changeset) do
    existing_id = Ecto.Changeset.get_field(changeset, :id)

    cond do
      # Try base slug (name only)
      !slug_exists?(base_slug, existing_id) ->
        base_slug

      # Try name + city
      true ->
        city_slug = get_city_slug(changeset)
        slug_with_city = "#{base_slug}-#{city_slug}"

        if !slug_exists?(slug_with_city, existing_id) do
          slug_with_city
        else
          # Fallback: name + timestamp
          "#{base_slug}-#{System.system_time(:second)}"
        end
    end
  end

  # Get city slug from venue's city_ref
  defp get_city_slug(changeset) do
    city_id = Ecto.Changeset.get_field(changeset, :city_id)

    if city_id do
      case Repo.get(EventasaurusDiscovery.Locations.City, city_id) do
        %{slug: slug} when is_binary(slug) -> slug
        _ -> "city"
      end
    else
      "city"
    end
  end

  # Check if slug already exists (excluding current record if updating)
  defp slug_exists?(slug, existing_id) do
    query =
      from(v in EventasaurusApp.Venues.Venue,
        where: v.slug == ^slug
      )

    query =
      if existing_id do
        from(v in query, where: v.id != ^existing_id)
      else
        query
      end

    Repo.exists?(query)
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
    field(:source, :string, default: "user")
    # Explicit public/private distinction:
    # - true: Public venues (theaters, bars, concert halls) - created by scrapers
    # - false: Private venues (user homes, private addresses) - created by users
    field(:is_public, :boolean, default: false)
    field(:metadata, :map)
    field(:geocoding_performance, :map)
    field(:provider_ids, :map, default: %{})
    # venue_images removed - now using cached_images table (Issue #2977)
    field(:image_enrichment_metadata, :map)

    belongs_to(:city_ref, EventasaurusDiscovery.Locations.City, foreign_key: :city_id)
    has_many(:events, EventasaurusApp.Events.Event)
    has_many(:public_events, EventasaurusDiscovery.PublicEvents.PublicEvent)

    # PostHog popularity tracking (synced by PostHogPopularitySyncWorker)
    field(:posthog_view_count, :integer, default: 0)
    field(:posthog_synced_at, :utc_datetime)

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
      :source,
      :is_public,
      :city_id,
      :metadata,
      :geocoding_performance,
      :provider_ids,
      :image_enrichment_metadata
    ])
    |> validate_required_by_type()
    |> validate_inclusion(:venue_type, @valid_venue_types,
      message: "must be one of: #{Enum.join(@valid_venue_types, ", ")}"
    )
    |> update_change(:source, fn s -> if is_binary(s), do: String.downcase(s), else: s end)
    |> validate_source()
    |> validate_utf8_fields()
    |> validate_gps_coordinates()
    |> validate_no_duplicate()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:city_id)
  end

  # Validate source against allowed values: user, scraper, provided, and geocoding providers
  # Uses ETS cache to avoid database query on every validation
  defp validate_source(changeset) do
    source = get_field(changeset, :source)

    if source do
      # Get allowed sources from ETS cache (no database query)
      allowed_sources = EventasaurusApp.Venues.VenueSourceCache.get_allowed_sources()

      if source in allowed_sources do
        changeset
      else
        add_error(changeset, :source, "must be one of: #{Enum.join(allowed_sources, ", ")}")
      end
    else
      changeset
    end
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

  # Duplicate Detection Validation (Phase 1)
  # Prevents creation of duplicate venues based on proximity and name similarity
  # Uses distance-based similarity thresholds via DuplicateDetection module
  defp validate_no_duplicate(changeset) do
    # Only check for duplicates on new venue creation (not updates)
    # Skip if changeset already has errors
    if changeset.data.id || !changeset.valid? do
      changeset
    else
      lat = get_field(changeset, :latitude)
      lng = get_field(changeset, :longitude)
      name = get_field(changeset, :name)
      city_id = get_field(changeset, :city_id)

      # Only perform duplicate check if we have all required fields
      if lat && lng && name && city_id do
        alias EventasaurusApp.Venues

        case Venues.check_duplicate(%{
               latitude: lat,
               longitude: lng,
               name: name,
               city_id: city_id
             }) do
          {:ok, nil} ->
            # No duplicate found
            changeset

          {:error, reason, opts} ->
            # Duplicate found - add error to changeset with structured opts
            add_error(changeset, :base, reason, opts)
        end
      else
        # Missing required fields for duplicate check - skip validation
        # (required field validation will catch this separately)
        changeset
      end
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

  @doc """
  Find venue by provider-specific ID.

  ## Parameters
  - `provider_name` - Name of the provider (e.g., "google_places", "foursquare")
  - `provider_id` - Provider-specific place identifier

  ## Examples

      iex> Venue.find_by_provider_id("google_places", "ChIJN1t_tDeuEmsRUsoyG83frY4")
      %Venue{...}

      iex> Venue.find_by_provider_id("foursquare", "4b1234abcd...")
      %Venue{...}
  """
  def find_by_provider_id(provider_name, provider_id) do
    import Ecto.Query
    alias EventasaurusApp.Repo

    from(v in __MODULE__,
      where: fragment("? @> ?", v.provider_ids, ^%{provider_name => provider_id})
    )
    |> Repo.one()
  end

  @doc """
  Check if venue has an ID from a specific provider.

  ## Parameters
  - `venue` - Venue struct
  - `provider_name` - Name of the provider to check

  ## Examples

      iex> Venue.has_provider_id?(venue, "google_places")
      true

      iex> Venue.has_provider_id?(venue, "foursquare")
      false
  """
  def has_provider_id?(%__MODULE__{provider_ids: provider_ids}, provider_name)
      when is_map(provider_ids) do
    Map.has_key?(provider_ids, provider_name) ||
      Map.has_key?(provider_ids, String.to_atom(provider_name))
  end

  def has_provider_id?(_, _), do: false

  @doc """
  Get provider ID for a specific provider.

  ## Parameters
  - `venue` - Venue struct
  - `provider_name` - Name of the provider

  ## Examples

      iex> Venue.get_provider_id(venue, "google_places")
      "ChIJN1t_tDeuEmsRUsoyG83frY4"

      iex> Venue.get_provider_id(venue, "unknown_provider")
      nil
  """
  def get_provider_id(%__MODULE__{provider_ids: provider_ids}, provider_name)
      when is_map(provider_ids) do
    Map.get(provider_ids, provider_name) || Map.get(provider_ids, String.to_atom(provider_name))
  end

  def get_provider_id(_, _), do: nil

  @doc """
  Add or update a provider ID for a venue.

  Returns a changeset with the updated provider_ids map.

  ## Parameters
  - `venue` - Venue struct or changeset
  - `provider_name` - Name of the provider
  - `provider_id` - Provider-specific place identifier

  ## Examples

      iex> venue |> Venue.put_provider_id("foursquare", "4b1234abcd...") |> Repo.update()
      {:ok, %Venue{...}}
  """
  def put_provider_id(%Ecto.Changeset{} = changeset, provider_name, provider_id) do
    current_ids = Ecto.Changeset.get_field(changeset, :provider_ids) || %{}
    updated_ids = Map.put(current_ids, provider_name, provider_id)
    Ecto.Changeset.put_change(changeset, :provider_ids, updated_ids)
  end

  def put_provider_id(%__MODULE__{} = venue, provider_name, provider_id) do
    changeset(venue, %{})
    |> put_provider_id(provider_name, provider_id)
  end

  @doc """
  Get the best cover image for a venue with smart fallback chain.

  Fallback priority:
  1. Venue's cached images from R2 (via cached_images table)
  2. City's categorized gallery (category determined by CategoryMapper)
  3. City's "general" category (if primary category has no images)
  4. nil (caller can provide placeholder)

  All image URLs are wrapped with CDN optimization.

  ## Parameters
  - `venue` - Venue struct (must have city_ref preloaded if using city fallback)
  - `opts` - CDN options (width, height, quality, etc.)

  ## Returns
  - `{:ok, image_url, source}` - Success with CDN-wrapped URL and source indicator
  - `{:error, :no_image}` - No image available

  ## Examples

      iex> Venue.get_cover_image(venue)
      {:ok, "https://cdn.wombie.com/cdn-cgi/image/...", :venue}

      iex> Venue.get_cover_image(venue, width: 800, quality: 90)
      {:ok, "https://cdn.wombie.com/cdn-cgi/image/w=800,q=90/...", :city_category}

      iex> Venue.get_cover_image(venue_without_images)
      {:error, :no_image}
  """
  def get_cover_image(%__MODULE__{} = venue, opts \\ []) do
    alias EventasaurusApp.Images.VenueImages

    cond do
      # Priority 1: Venue's cached images from R2
      # Uses VenueImages which handles production vs dev/test environment
      image_url = VenueImages.get_url(venue.id) ->
        cdn_url = Eventasaurus.CDN.url(image_url, opts)
        {:ok, cdn_url, :venue}

      # Priority 2: City category images
      has_city_with_gallery?(venue) ->
        get_city_category_image(venue, opts)

      # No images available
      true ->
        {:error, :no_image}
    end
  end

  # Check if venue has city with categorized gallery
  defp has_city_with_gallery?(%__MODULE__{
         city_ref: %EventasaurusDiscovery.Locations.City{} = city
       }) do
    alias EventasaurusDiscovery.Locations.City
    City.has_categorized_gallery?(city)
  end

  defp has_city_with_gallery?(_), do: false

  # Get image from city's categorized gallery
  defp get_city_category_image(
         %__MODULE__{city_ref: %EventasaurusDiscovery.Locations.City{} = city} = venue,
         opts
       ) do
    alias EventasaurusApp.Venues.CategoryMapper
    alias EventasaurusDiscovery.Locations.City

    # Determine best category for this venue
    category = CategoryMapper.determine_category(venue)

    # Try primary category first, then fallback to general
    case City.get_category_image(city, category) do
      {:ok, image} ->
        image_url = Map.get(image, "url")
        cdn_url = Eventasaurus.CDN.url(image_url, opts)
        {:ok, cdn_url, :city_category}

      {:error, _} when category != "general" ->
        # Fallback to general category
        case City.get_category_image(city, "general") do
          {:ok, image} ->
            image_url = Map.get(image, "url")
            cdn_url = Eventasaurus.CDN.url(image_url, opts)
            {:ok, cdn_url, :city_general}

          {:error, _} ->
            {:error, :no_image}
        end

      {:error, _} ->
        {:error, :no_image}
    end
  end
end
