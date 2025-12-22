defmodule EventasaurusDiscovery.PublicEvents.PublicEvent.Slug do
  use EctoAutoslugField.Slug, to: :slug
  require Logger
  import Ecto.Query
  alias EventasaurusApp.Repo

  def get_sources(_changeset, _opts) do
    # Use title as primary source for slug generation
    [:title]
  end

  def build_slug(sources, changeset) do
    # Universal UTF-8 protection for all scrapers
    # This ensures that regardless of which scraper (Karnet, Ticketmaster, Bandsintown, etc.)
    # provides the data, we handle UTF-8 issues consistently
    safe_sources = sources |> Enum.map(&ensure_safe_string/1)

    # Only proceed if we have valid content
    case safe_sources do
      ["" | _] ->
        # Fallback slug if title is empty/invalid after cleaning
        # This prevents slug generation errors when UTF-8 cleaning results in empty string
        "event-#{DateTime.utc_now() |> DateTime.to_unix()}"

      _ ->
        # Get the default slug from cleaned sources
        base_slug = super(safe_sources, changeset)

        # Truncate title to 40 characters at word boundary
        truncated_title = truncate_title(base_slug, 40)

        # Build deterministic suffix from venue + date (conditionally includes venue)
        suffix = build_deterministic_suffix(changeset, truncated_title)

        # Combine title and suffix
        candidate_slug = "#{truncated_title}-#{suffix}"

        # Ensure uniqueness by checking for collisions
        ensure_unique_slug(candidate_slug, changeset)
    end
  end

  # Truncate slug to max_length at word boundary (hyphen)
  defp truncate_title(title, max_length) do
    if String.length(title) <= max_length do
      title
    else
      title
      |> String.slice(0, max_length)
      |> String.split("-")
      # Drop partial word at end
      |> Enum.drop(-1)
      |> Enum.join("-")
    end
  end

  # Build deterministic suffix from venue slug + date
  # Only includes venue slug if not already present in title
  defp build_deterministic_suffix(changeset, title_slug) do
    venue_id = Ecto.Changeset.get_field(changeset, :venue_id)
    starts_at = Ecto.Changeset.get_field(changeset, :starts_at)

    # Get venue slug (truncated and cleaned)
    venue_slug = get_venue_slug(venue_id)

    # Format date as yymmdd
    date_str = format_date(starts_at)

    # Only append venue if not already in title (prevents duplication)
    if should_append_venue_slug?(title_slug, venue_slug) do
      "#{venue_slug}-#{date_str}"
    else
      date_str
    end
  end

  # Check if venue slug should be appended to avoid duplication
  # Normalizes both strings and checks for containment
  defp should_append_venue_slug?(title_slug, venue_slug) do
    # Normalize: remove all non-alphanumeric characters
    title_normalized = title_slug |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
    venue_normalized = venue_slug |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")

    # Don't append venue if title already contains it
    not String.contains?(title_normalized, venue_normalized)
  end

  # Get venue slug from venue_id and clean it
  defp get_venue_slug(nil), do: "online"

  defp get_venue_slug(venue_id) do
    venue =
      EventasaurusApp.Venues.Venue
      |> Repo.get(venue_id)
      |> Repo.preload(city_ref: :country)

    case venue do
      nil ->
        "venue"

      %{slug: slug, city_ref: %{slug: city_slug}} when is_binary(slug) ->
        clean_venue_slug(slug, city_slug, 25)

      %{slug: slug} when is_binary(slug) ->
        clean_venue_slug(slug, nil, 25)

      _ ->
        "venue"
    end
  end

  # Clean venue slug by removing city name and trailing numbers
  defp clean_venue_slug(slug, city_slug, max_length) do
    slug
    # Remove city name if present (e.g., "krakow-bonarka-1-649" → "bonarka-1-649")
    |> remove_city_from_slug(city_slug)
    # Remove trailing numbers (e.g., "bonarka-1-649" → "bonarka")
    |> remove_trailing_numbers()
    # Remove trailing hyphens
    |> String.trim_trailing("-")
    # Truncate to max_length at word boundary
    |> truncate_at_word_boundary(max_length)
  end

  # Remove city slug from venue slug if present
  defp remove_city_from_slug(venue_slug, nil), do: venue_slug

  defp remove_city_from_slug(venue_slug, city_slug) when is_binary(city_slug) do
    # Try to remove city at beginning: "krakow-bonarka" → "bonarka"
    cleaned =
      venue_slug
      |> String.replace_prefix("#{city_slug}-", "")

    # If nothing changed, try removing city anywhere in the slug
    if cleaned == venue_slug do
      venue_slug
      |> String.split("-")
      |> Enum.reject(&(&1 == city_slug))
      |> Enum.join("-")
    else
      cleaned
    end
  end

  # Remove trailing numeric segments (e.g., "bonarka-1-649" → "bonarka")
  defp remove_trailing_numbers(slug) do
    slug
    |> String.split("-")
    |> Enum.reverse()
    |> Enum.drop_while(&String.match?(&1, ~r/^[0-9]+$/))
    |> Enum.reverse()
    |> Enum.join("-")
  end

  # Truncate to max_length at word boundary (hyphen)
  defp truncate_at_word_boundary(slug, max_length) do
    if String.length(slug) <= max_length do
      slug
    else
      # Take complete words only
      slug
      |> String.split("-")
      |> Enum.reduce_while([], fn word, acc ->
        candidate = Enum.join(acc ++ [word], "-")

        if String.length(candidate) <= max_length do
          {:cont, acc ++ [word]}
        else
          {:halt, acc}
        end
      end)
      |> Enum.join("-")
    end
  end

  # Format date as yymmdd
  defp format_date(nil), do: "nodate"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%y%m%d")
  end

  # Ensure slug is unique using semantic disambiguation
  defp ensure_unique_slug(candidate_slug, changeset) do
    existing_id = Ecto.Changeset.get_field(changeset, :id)

    if slug_exists?(candidate_slug, existing_id) do
      # Try semantic disambiguation first
      resolve_collision_semantically(candidate_slug, changeset, existing_id)
    else
      candidate_slug
    end
  end

  # Resolve collisions using semantic information (city, country) before falling back to numbers
  defp resolve_collision_semantically(base_slug, changeset, existing_id) do
    venue_id = Ecto.Changeset.get_field(changeset, :venue_id)

    # Get city and country info
    {city_slug, country_code} = get_location_info(venue_id)

    # Try adding city name
    with_city = try_slug_with_suffix(base_slug, city_slug, existing_id)

    cond do
      with_city != nil ->
        with_city

      true ->
        # Try adding country code
        with_country = try_slug_with_suffix(base_slug, country_code, existing_id)

        cond do
          with_country != nil ->
            with_country

          true ->
            # Try both city and country
            with_both =
              try_slug_with_suffix(base_slug, "#{city_slug}-#{country_code}", existing_id)

            cond do
              with_both != nil ->
                with_both

              true ->
                # Fall back to numeric increment
                find_next_available_slug(base_slug, existing_id, 2)
            end
        end
    end
  end

  # Get city slug and country code for semantic disambiguation
  defp get_location_info(nil), do: {nil, nil}

  defp get_location_info(venue_id) do
    case Repo.get(EventasaurusApp.Venues.Venue, venue_id, preload: [city_ref: :country]) do
      %{city_ref: %{slug: city_slug, country: %{code: country_code}}} ->
        {city_slug, String.downcase(country_code)}

      %{city_ref: %{slug: city_slug}} ->
        {city_slug, nil}

      _ ->
        {nil, nil}
    end
  end

  # Try a slug with a suffix, return it if unique, nil otherwise
  # Guard against nil or empty suffixes to prevent double hyphens
  defp try_slug_with_suffix(_base_slug, suffix, _existing_id)
       when suffix in [nil, ""],
       do: nil

  defp try_slug_with_suffix(base_slug, suffix, existing_id) do
    candidate = "#{base_slug}-#{suffix}"

    if slug_exists?(candidate, existing_id) do
      nil
    else
      candidate
    end
  end

  # Check if slug already exists (excluding current record if updating)
  defp slug_exists?(slug, nil) do
    query = from(e in EventasaurusDiscovery.PublicEvents.PublicEvent, where: e.slug == ^slug)
    Repo.exists?(query)
  end

  defp slug_exists?(slug, existing_id) do
    query =
      from(e in EventasaurusDiscovery.PublicEvents.PublicEvent,
        where: e.slug == ^slug and e.id != ^existing_id
      )

    Repo.exists?(query)
  end

  # Recursively find next available slug by incrementing counter (last resort)
  defp find_next_available_slug(base_slug, existing_id, counter) do
    candidate = "#{base_slug}-#{counter}"

    if slug_exists?(candidate, existing_id) do
      find_next_available_slug(base_slug, existing_id, counter + 1)
    else
      candidate
    end
  end

  # Universal UTF-8 safety function used by all scrapers
  defp ensure_safe_string(value) do
    case value do
      # Handle error tuples from failed UTF-8 conversions
      # This catches the {:error, "", <<226>>} type errors from Ticketmaster
      {:error, _, invalid_bytes} ->
        Logger.warning("""
        Invalid UTF-8 detected in slug source
        Error tuple: #{inspect(value)}
        Invalid bytes: #{inspect(invalid_bytes, limit: 50)}
        """)

        ""

      # Handle valid binary strings
      str when is_binary(str) ->
        # Use our universal UTF8 utility to clean the string
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

defmodule EventasaurusDiscovery.PublicEvents.PublicEvent do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.PublicEvents.PublicEvent.Slug

  schema "public_events" do
    field(:title, :string)
    field(:title_translations, :map)
    field(:slug, Slug.Type)
    field(:starts_at, :utc_datetime)
    field(:ends_at, :utc_datetime)
    # external_id moved to public_event_sources table
    # ticket_url moved to public_event_sources table (source-specific)
    # min_price, max_price, currency moved to public_event_sources table (source-specific)
    # metadata moved to public_event_sources table
    field(:occurrences, :map)
    # Pre-computed translation count (updated by database trigger on insert/update)
    field(:title_translation_count, :integer, default: 0)

    # PostHog popularity tracking (synced by PostHogPopularitySyncWorker)
    field(:posthog_view_count, :integer, default: 0)
    field(:posthog_synced_at, :utc_datetime)

    # Virtual field for primary category (populated in queries when needed)
    field(:primary_category_id, :id, virtual: true)

    # Virtual fields for localized display (populated by PublicEventsEnhanced)
    field(:display_title, :string, virtual: true)
    field(:display_description, :string, virtual: true)
    field(:cover_image_url, :string, virtual: true)

    belongs_to(:venue, EventasaurusApp.Venues.Venue)

    # Keep old relationship for backward compatibility during transition
    belongs_to(:category, EventasaurusDiscovery.Categories.Category)

    # New many-to-many relationship
    many_to_many(:categories, EventasaurusDiscovery.Categories.Category,
      join_through: EventasaurusDiscovery.Categories.PublicEventCategory,
      join_keys: [event_id: :id, category_id: :id],
      on_replace: :delete
    )

    many_to_many(:performers, EventasaurusDiscovery.Performers.Performer,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
      join_keys: [event_id: :id, performer_id: :id]
    )

    many_to_many(:movies, EventasaurusDiscovery.Movies.Movie,
      join_through: EventasaurusDiscovery.PublicEvents.EventMovie,
      join_keys: [event_id: :id, movie_id: :id],
      on_replace: :delete
    )

    # Association to sources for description_translations access
    has_many(:sources, EventasaurusDiscovery.PublicEvents.PublicEventSource,
      foreign_key: :event_id
    )

    timestamps()
  end

  @doc false
  def changeset(public_event, attrs) do
    public_event
    |> cast(attrs, [
      :title,
      :title_translations,
      :starts_at,
      :ends_at,
      :venue_id,
      :category_id,
      :occurrences
    ])
    |> validate_required([:title, :starts_at, :venue_id],
      message: "Public events must have a venue for proper location and collision detection"
    )
    # PostgreSQL boundary protection
    |> sanitize_utf8()
    |> validate_date_order()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    # external_id can collide across sources; uniqueness enforced in PublicEventSource
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:category_id)
  end

  # PostgreSQL boundary protection - validate UTF-8 before DB insertion
  defp sanitize_utf8(changeset) do
    changeset
    |> update_change(:title, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
    |> update_change(
      :title_translations,
      &EventasaurusDiscovery.Utils.UTF8.validate_map_strings/1
    )
    |> update_change(:occurrences, &EventasaurusDiscovery.Utils.UTF8.validate_map_strings/1)
  end

  defp validate_date_order(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    cond do
      is_nil(starts_at) or is_nil(ends_at) ->
        changeset

      DateTime.compare(ends_at, starts_at) == :lt ->
        add_error(changeset, :ends_at, "must be after start date")

      true ->
        changeset
    end
  end

  @doc """
  Returns the count of occurrences for an event.
  """
  def occurrence_count(%__MODULE__{occurrences: nil}), do: 0

  def occurrence_count(%__MODULE__{occurrences: %{"dates" => dates}}) when is_list(dates) do
    length(dates)
  end

  def occurrence_count(_), do: 0

  @doc """
  Checks if an event is recurring (has multiple occurrences).
  """
  def recurring?(%__MODULE__{} = event) do
    occurrence_count(event) > 1
  end

  @doc """
  Returns a human-readable description of the event frequency.
  """
  def frequency_label(%__MODULE__{} = event) do
    count = occurrence_count(event)

    cond do
      count == 0 -> nil
      # Single events don't need a label
      count == 1 -> nil
      count <= 7 -> "#{count} dates available"
      count <= 30 -> "Multiple dates"
      count <= 60 -> "Daily event"
      true -> "#{count} dates available"
    end
  end

  @doc """
  Returns the next upcoming date for an event with occurrences.
  """
  def next_occurrence_date(%__MODULE__{occurrences: nil, starts_at: starts_at}), do: starts_at

  def next_occurrence_date(%__MODULE__{occurrences: %{"dates" => dates}, starts_at: starts_at})
      when is_list(dates) do
    now = DateTime.utc_now()

    # Parse dates and find the next upcoming one
    upcoming =
      dates
      |> Enum.map(fn %{"date" => date_str, "time" => time_str} ->
        with {:ok, date} <- Date.from_iso8601(date_str),
             {:ok, time} <- Time.from_iso8601(time_str <> ":00") do
          DateTime.new!(date, time, "Etc/UTC")
        else
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
      |> Enum.sort(&(DateTime.compare(&1, &2) == :lt))
      |> List.first()

    upcoming || starts_at
  end

  def next_occurrence_date(%__MODULE__{starts_at: starts_at}), do: starts_at
end
