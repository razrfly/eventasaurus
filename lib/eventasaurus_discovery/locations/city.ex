defmodule EventasaurusDiscovery.Locations.City.Slug do
  use EctoAutoslugField.Slug, from: :name, to: :slug
  require Logger
  import Ecto.Query
  alias EventasaurusApp.Repo

  @doc """
  Build slug with smart collision handling.

  Strategy (following Venue.Slug pattern):
  1. Try base slug (city name only)
  2. If taken, append country code (e.g., "manchester-us")
  3. If taken (edge case), append timestamp

  This ensures globally unique slugs while keeping clean slugs for the first city with each name.
  """
  def build_slug(sources, changeset) do
    # Get base slug from EctoAutoslugField
    base_slug = super(sources, changeset)

    # Ensure uniqueness using progressive disambiguation
    ensure_unique_slug(base_slug, changeset)
  end

  # Ensure slug is unique using progressive disambiguation (like Venue.Slug)
  # Strategy: name -> name-countrycode -> name-timestamp
  defp ensure_unique_slug(base_slug, changeset) do
    existing_id = Ecto.Changeset.get_field(changeset, :id)

    cond do
      # Try base slug (city name only)
      !slug_exists?(base_slug, existing_id) ->
        base_slug

      # Try base slug + country code
      true ->
        country_code = get_country_code(changeset)
        slug_with_country = "#{base_slug}-#{country_code}"

        if !slug_exists?(slug_with_country, existing_id) do
          slug_with_country
        else
          # Fallback: base slug + timestamp (edge case, like Venue.Slug)
          # Use microsecond precision to avoid collisions
          "#{base_slug}-#{System.system_time(:microsecond)}"
        end
    end
  end

  # Get country code from city's country
  defp get_country_code(changeset) do
    country_id = Ecto.Changeset.get_field(changeset, :country_id)

    if country_id do
      case Repo.get(EventasaurusDiscovery.Locations.Country, country_id) do
        %{code: code} when is_binary(code) -> String.downcase(code)
        _ -> "unknown"
      end
    else
      "unknown"
    end
  end

  # Check if slug already exists (excluding current record if updating)
  defp slug_exists?(slug, existing_id) do
    query =
      from(c in EventasaurusDiscovery.Locations.City,
        where: c.slug == ^slug
      )

    query =
      if existing_id do
        from(c in query, where: c.id != ^existing_id)
      else
        query
      end

    Repo.exists?(query)
  end
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
    field(:unsplash_gallery, :map)
    field(:alternate_names, {:array, :string}, default: [])
    field(:event_count, :integer, virtual: true)
    # IANA timezone identifier (e.g., "Europe/Warsaw", "America/Chicago")
    # Pre-computed from coordinates to eliminate runtime TzWorld calls (Issue #3334)
    field(:timezone, :string)

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
      :discovery_config,
      :alternate_names,
      :timezone
    ])
    |> validate_required([:name, :country_id])
    |> Slug.maybe_generate_slug()
    |> foreign_key_constraint(:country_id)
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset specifically for updating a city's timezone.
  Used by the timezone population mix task.
  """
  def timezone_changeset(city, timezone) when is_binary(timezone) do
    city
    |> cast(%{timezone: timezone}, [:timezone])
  end

  @doc """
  Changeset for updating the Unsplash gallery.
  This is a dedicated, internal changeset to prevent mass-assignment vulnerabilities.

  Supports two formats:
  1. Legacy format: %{"images" => [...], "current_index" => 0, "last_refreshed_at" => "..."}
  2. Categorized format: %{"active_category" => "general", "categories" => %{"general" => %{...}}}
  """
  def gallery_changeset(city, gallery_map) when is_map(gallery_map) do
    city
    |> cast(%{}, [])
    |> put_change(:unsplash_gallery, gallery_map)
    |> validate_gallery_structure()
  end

  # Validate gallery structure (supports both legacy and categorized formats)
  defp validate_gallery_structure(changeset) do
    case get_change(changeset, :unsplash_gallery) do
      nil ->
        changeset

      gallery when is_map(gallery) ->
        cond do
          # New categorized format
          Map.has_key?(gallery, "categories") ->
            validate_categorized_gallery(changeset, gallery)

          # Legacy format (for backward compatibility)
          Map.has_key?(gallery, "images") ->
            validate_legacy_gallery(changeset, gallery)

          # Invalid format
          true ->
            add_error(
              changeset,
              :unsplash_gallery,
              "must contain either 'categories' (new format) or 'images' (legacy format)"
            )
        end

      _ ->
        add_error(changeset, :unsplash_gallery, "must be a map")
    end
  end

  defp validate_categorized_gallery(changeset, gallery) do
    changeset =
      if not Map.has_key?(gallery, "active_category") do
        add_error(changeset, :unsplash_gallery, "categorized gallery must have 'active_category'")
      else
        changeset
      end

    changeset =
      if not is_map(gallery["categories"]) do
        add_error(changeset, :unsplash_gallery, "'categories' must be a map")
      else
        # Validate each category
        Enum.reduce(gallery["categories"], changeset, fn {category_name, category_data}, acc ->
          validate_category(acc, category_name, category_data)
        end)
      end

    changeset
  end

  defp validate_category(changeset, category_name, category_data) do
    cond do
      not is_map(category_data) ->
        add_error(
          changeset,
          :unsplash_gallery,
          "category '#{category_name}' must be a map"
        )

      not Map.has_key?(category_data, "images") or not is_list(category_data["images"]) ->
        add_error(
          changeset,
          :unsplash_gallery,
          "category '#{category_name}' must have 'images' as a list"
        )

      not Map.has_key?(category_data, "search_terms") or
          not is_list(category_data["search_terms"]) ->
        add_error(
          changeset,
          :unsplash_gallery,
          "category '#{category_name}' must have 'search_terms' as a list"
        )

      true ->
        changeset
    end
  end

  defp validate_legacy_gallery(changeset, gallery) do
    cond do
      not is_list(gallery["images"]) ->
        add_error(changeset, :unsplash_gallery, "'images' must be a list")

      not Map.has_key?(gallery, "last_refreshed_at") ->
        add_error(changeset, :unsplash_gallery, "legacy gallery must have 'last_refreshed_at'")

      true ->
        changeset
    end
  end

  @doc """
  Changeset for manually updating a city's slug.

  Use this when you need to override the auto-generated slug,
  such as when fixing duplicate city slugs.

  ## Examples

      iex> slug_changeset(city, %{slug: "warsaw"})
      %Ecto.Changeset{}
  """
  def slug_changeset(city, attrs) do
    city
    |> cast(attrs, [:slug])
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 1, max: 255)
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for deleting a city.
  Adds constraint to prevent deletion when city has venues.
  """
  def delete_changeset(city) do
    city
    |> cast(%{}, [])
    |> check_constraint(:id,
      name: :venues_city_id_required_for_non_regional,
      message: "has venues"
    )
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

  @doc """
  Get an image from a specific category in the city's gallery.

  Supports both legacy and categorized gallery formats.

  ## Parameters
    - city: City struct (must have unsplash_gallery preloaded)
    - category_name: Category to get image from (e.g., "general", "architecture")

  ## Returns
    - {:ok, image_map} - Image with url, attribution, etc.
    - {:error, :no_gallery} - City has no gallery
    - {:error, :no_categories} - Gallery is legacy format (no categories)
    - {:error, :category_not_found} - Category doesn't exist
    - {:error, :no_images} - Category has no images

  ## Examples

      iex> City.get_category_image(city, "architecture")
      {:ok, %{"url" => "https://...", "attribution" => %{...}}}

      iex> City.get_category_image(city, "nonexistent")
      {:error, :category_not_found}
  """
  def get_category_image(%__MODULE__{unsplash_gallery: nil}, _category_name) do
    {:error, :no_gallery}
  end

  def get_category_image(%__MODULE__{unsplash_gallery: gallery}, category_name)
      when is_map(gallery) do
    cond do
      # Categorized format
      Map.has_key?(gallery, "categories") ->
        categories = gallery["categories"]

        # Handle both string and atom keys if necessary, but usually string from JSON
        category_data =
          Map.get(categories, category_name) || Map.get(categories, to_string(category_name))

        case category_data do
          nil ->
            {:error, :category_not_found}

          category_data ->
            images = Map.get(category_data, "images", [])

            if Enum.empty?(images) do
              {:error, :no_images}
            else
              # Get daily rotating image (day_of_year returns 1-365, normalize to 0-based)
              day_of_year = Date.utc_today() |> Date.day_of_year()
              index = rem(day_of_year - 1, length(images))
              image = Enum.at(images, index)
              {:ok, image}
            end
        end

      # Legacy format - no categories
      true ->
        {:error, :no_categories}
    end
  end

  @doc """
  Get the active category for a city's gallery.

  Returns the category name that should be used by default.

  ## Examples

      iex> City.get_active_category(city)
      "general"

      iex> City.get_active_category(legacy_city)
      nil
  """
  def get_active_category(%__MODULE__{unsplash_gallery: nil}), do: nil

  def get_active_category(%__MODULE__{unsplash_gallery: gallery}) when is_map(gallery) do
    if Map.has_key?(gallery, "categories") do
      Map.get(gallery, "active_category", "general")
    else
      nil
    end
  end

  @doc """
  Check if a city has a categorized gallery (vs legacy format).

  ## Examples

      iex> City.has_categorized_gallery?(city)
      true

      iex> City.has_categorized_gallery?(legacy_city)
      false
  """
  def has_categorized_gallery?(%__MODULE__{unsplash_gallery: nil}), do: false

  def has_categorized_gallery?(%__MODULE__{unsplash_gallery: gallery}) when is_map(gallery) do
    Map.has_key?(gallery, "categories")
  end

  @doc """
  Get all available categories for a city.

  Returns list of category names.

  ## Examples

      iex> City.get_available_categories(city)
      ["general", "architecture", "historic"]

      iex> City.get_available_categories(legacy_city)
      []
  """
  def get_available_categories(%__MODULE__{unsplash_gallery: nil}), do: []

  def get_available_categories(%__MODULE__{unsplash_gallery: gallery}) when is_map(gallery) do
    if Map.has_key?(gallery, "categories") do
      gallery["categories"]
      |> Map.keys()
      |> Enum.sort()
    else
      []
    end
  end
end
