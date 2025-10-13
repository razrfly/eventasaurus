defmodule EventasaurusDiscovery.PublicEventsEnhanced do
  @moduledoc """
  Enhanced PublicEvents context with comprehensive filtering, search, and pagination.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainer
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainerMembership
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City

  @default_limit 20
  @max_limit 500

  @doc """
  List events with comprehensive filtering options.

  ## Options
    * `:categories` - List of category IDs to filter by
    * `:start_date` - Filter events starting after this date
    * `:end_date` - Filter events starting before this date
    * `:min_price` - Minimum price filter
    * `:max_price` - Maximum price filter
    * `:city_id` - Filter by city ID
    * `:country_id` - Filter by country ID
    * `:venue_ids` - List of venue IDs
    * `:center_lat` - Center latitude for geographic filtering
    * `:center_lng` - Center longitude for geographic filtering
    * `:radius_km` - Radius in kilometers for geographic filtering
    * `:search` - Text search query
    * `:language` - Language code for translations (default: "en")
    * `:sort_by` - Sort field (:starts_at, :price, :title, :relevance)
    * `:sort_order` - :asc or :desc
    * `:page` - Page number for pagination
    * `:page_size` - Items per page (max: 500)
  """
  def list_events(opts \\ []) do
    base_query = from(pe in PublicEvent)

    base_query
    |> filter_past_events(opts[:show_past])
    |> filter_by_categories(opts[:categories])
    |> filter_by_date_range(opts[:start_date], opts[:end_date])
    |> filter_by_price_range(opts[:min_price], opts[:max_price])
    |> filter_by_location(opts[:city_id], opts[:country_id], opts[:venue_ids])
    |> filter_by_radius(opts[:center_lat], opts[:center_lng], opts[:radius_km])
    |> filter_by_source(opts[:source_slug])
    |> apply_search(opts[:search])
    |> apply_sorting(opts[:sort_by], opts[:sort_order])
    |> paginate(opts[:page], opts[:page_size])
    |> Repo.all()
    |> preload_with_sources(opts[:language])
  end

  @doc """
  Full-text search for events.
  """
  def search_events(search_term, opts \\ []) when is_binary(search_term) do
    language = opts[:language] || "en"
    limit = min(opts[:limit] || @default_limit, @max_limit)
    offset = opts[:offset] || 0

    # Build search query
    search_query = String.trim(search_term)

    from(pe in PublicEvent,
      where:
        fragment(
          "? @@ websearch_to_tsquery('english', ?)",
          pe.search_vector,
          ^search_query
        ) or
          fragment(
            "? ILIKE ?",
            pe.title,
            ^"%#{search_query}%"
          ),
      order_by: [
        desc:
          fragment(
            "ts_rank(?, websearch_to_tsquery('english', ?))",
            pe.search_vector,
            ^search_query
          )
      ],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
    |> preload_with_sources(language)
  end

  @doc """
  Get events from the localized view with language preference.
  """
  def list_events_localized(opts \\ []) do
    # Validate and sanitize language parameter to prevent SQL injection
    language =
      case opts[:language] do
        l when is_binary(l) ->
          if String.match?(l, ~r/^[a-z]{2}$/) do
            l
          else
            "en"
          end

        _ ->
          "en"
      end

    limit = min(opts[:limit] || @default_limit, @max_limit)
    offset = opts[:offset] || 0

    query = """
    SELECT
      id,
      slug,
      COALESCE(
        jsonb_extract_path_text(title_translations, $3),
        jsonb_extract_path_text(title_translations, 'en'),
        title
      ) as display_title,
      COALESCE(
        jsonb_extract_path_text(description_translations, $3),
        jsonb_extract_path_text(description_translations, 'en')
      ) as display_description,
      starts_at,
      ends_at,
      venue_name,
      venue_slug,
      city_name,
      country_name,
      category_name,
      category_color,
      category_icon,
      min_price,
      max_price,
      currency,
      ticket_url,
      image_url
    FROM public_events_view
    WHERE starts_at > NOW()
    ORDER BY starts_at ASC
    LIMIT $1 OFFSET $2
    """

    result = Ecto.Adapters.SQL.query!(Repo, query, [limit, offset, language])

    # Convert to maps with proper string keys
    Enum.map(result.rows, fn row ->
      m =
        result.columns
        |> Enum.zip(row)
        |> Enum.into(%{})

      m
      |> Map.update("starts_at", nil, &parse_datetime/1)
      |> Map.update("ends_at", nil, &parse_datetime/1)
    end)
  end

  ## Filter Functions

  # If show_past is true, don't filter
  defp filter_past_events(query, true), do: query

  defp filter_past_events(query, _) do
    # By default, exclude past events
    # An event is considered active/upcoming if:
    # - It has an end date that hasn't passed yet, OR
    # - It has no end date and hasn't started yet
    current_time = DateTime.utc_now()

    from(pe in query,
      where:
        (not is_nil(pe.ends_at) and pe.ends_at > ^current_time) or
          (is_nil(pe.ends_at) and pe.starts_at > ^current_time)
    )
  end

  defp filter_by_categories(query, nil), do: query
  defp filter_by_categories(query, []), do: query

  defp filter_by_categories(query, category_ids) when is_list(category_ids) do
    from(pe in query,
      join: pec in "public_event_categories",
      on: pec.event_id == pe.id,
      where: pec.category_id in ^category_ids
    )
  end

  defp filter_by_date_range(query, nil, nil), do: query

  defp filter_by_date_range(query, start_date, nil) do
    from(pe in query, where: pe.starts_at >= ^start_date)
  end

  defp filter_by_date_range(query, nil, end_date) do
    from(pe in query, where: pe.starts_at <= ^end_date)
  end

  defp filter_by_date_range(query, start_date, end_date) do
    from(pe in query,
      where: pe.starts_at >= ^start_date and pe.starts_at <= ^end_date
    )
  end

  # Price filtering moved to source-specific implementation
  # TODO: Implement price filtering using public_event_sources data when needed
  defp filter_by_price_range(query, nil, nil), do: query
  defp filter_by_price_range(query, _min_price, _max_price), do: query

  defp filter_by_location(query, nil, nil, nil), do: query

  defp filter_by_location(query, city_id, country_id, venue_ids) do
    query
    |> filter_by_city(city_id)
    |> filter_by_country(country_id)
    |> filter_by_venues(venue_ids)
  end

  defp filter_by_city(query, nil), do: query

  defp filter_by_city(query, city_id) do
    from(pe in query, join: v in Venue, on: pe.venue_id == v.id, where: v.city_id == ^city_id)
  end

  defp filter_by_country(query, nil), do: query

  defp filter_by_country(query, country_id) do
    from(pe in query,
      join: v in Venue,
      on: pe.venue_id == v.id,
      join: c in City,
      on: v.city_id == c.id,
      where: c.country_id == ^country_id
    )
  end

  defp filter_by_venues(query, nil), do: query
  defp filter_by_venues(query, []), do: query

  defp filter_by_venues(query, venue_ids) when is_list(venue_ids) do
    from(pe in query, where: pe.venue_id in ^venue_ids)
  end

  ## Source Filtering

  defp filter_by_source(query, nil), do: query

  defp filter_by_source(query, source_slug) when is_binary(source_slug) do
    from(pe in query,
      join: pes in "public_event_sources",
      on: pes.event_id == pe.id,
      join: s in "sources",
      on: s.id == pes.source_id,
      where: s.slug == ^source_slug
    )
  end

  ## Geographic Filtering

  defp filter_by_radius(query, nil, nil, nil), do: query
  defp filter_by_radius(query, nil, _lng, _radius), do: query
  defp filter_by_radius(query, _lat, nil, _radius), do: query
  defp filter_by_radius(query, _lat, _lng, nil), do: query

  defp filter_by_radius(query, center_lat, center_lng, radius_km)
       when is_number(center_lat) and is_number(center_lng) and is_number(radius_km) do
    radius_meters = radius_km * 1000

    from(pe in query,
      join: v in Venue,
      on: pe.venue_id == v.id,
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      where:
        fragment(
          "ST_DWithin(
          ST_MakePoint(?::float, ?::float)::geography,
          ST_MakePoint(?::float, ?::float)::geography,
          ?
        )",
          ^center_lng,
          ^center_lat,
          v.longitude,
          v.latitude,
          ^radius_meters
        )
    )
  end

  ## Search

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, search_term) do
    search_query = String.trim(search_term)

    from(pe in query,
      where:
        fragment(
          "? @@ websearch_to_tsquery('english', ?) OR ? ILIKE ?",
          pe.search_vector,
          ^search_query,
          pe.title,
          ^"%#{search_query}%"
        )
    )
  end

  ## Sorting

  defp apply_sorting(query, nil, nil), do: apply_sorting(query, :starts_at, :asc)
  defp apply_sorting(query, nil, order), do: apply_sorting(query, :starts_at, order || :asc)
  defp apply_sorting(query, field, nil), do: apply_sorting(query, field, :asc)

  defp apply_sorting(query, :starts_at, order) when order in [:asc, :desc] do
    from(pe in query, order_by: [{^order, pe.starts_at}])
  end

  defp apply_sorting(query, :title, order) when order in [:asc, :desc] do
    from(pe in query, order_by: [{^order, pe.title}])
  end

  defp apply_sorting(query, :relevance, _order) do
    # Relevance sorting only makes sense with search
    query
  end

  defp apply_sorting(query, _field, _order), do: apply_sorting(query, :starts_at, :asc)

  ## Pagination

  defp paginate(query, nil, nil), do: paginate(query, 1, @default_limit)

  defp paginate(query, page, page_size) do
    page = max(page || 1, 1)
    page_size = min(page_size || @default_limit, @max_limit)
    offset = (page - 1) * page_size

    from(pe in query,
      limit: ^page_size,
      offset: ^offset
    )
  end

  ## Preloading

  defp preload_with_sources(events, language) do
    events
    |> Repo.preload([
      :venue,
      :categories,
      :performers,
      :movies,
      :sources
    ])
    |> Enum.map(fn event ->
      # Add display fields based on language
      Map.merge(event, %{
        display_title: get_localized_title(event, language),
        display_description: get_localized_description(event, language),
        cover_image_url: get_cover_image_url(event)
      })
    end)
  end

  defp get_localized_title(event, language) do
    case event.title_translations do
      nil ->
        event.title

      translations when is_map(translations) ->
        translations[language] || translations["en"] || event.title

      _ ->
        event.title
    end
  end

  defp get_localized_description(event, language) do
    # Sort sources by priority and take the first one's description
    # Fix: Sort by newest last_seen_at first (negative timestamp)
    sorted_sources =
      event.sources
      |> Enum.sort_by(fn source ->
        priority =
          case source.metadata do
            %{"priority" => p} when is_integer(p) ->
              p

            %{"priority" => p} when is_binary(p) ->
              case Integer.parse(p) do
                {num, _} -> num
                _ -> 10
              end

            _ ->
              10
          end

        # Newer timestamps first (negative for descending sort)
        ts =
          case source.last_seen_at do
            %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
            _ -> 9_223_372_036_854_775_807
          end

        {priority, ts}
      end)

    case sorted_sources do
      [source | _] ->
        case source.description_translations do
          nil ->
            nil

          translations when is_map(translations) ->
            translations[language] || translations["en"] || nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Gets the cover image URL for an event from its sources.

  For movie events, prioritizes movie poster/backdrop from TMDb over source images.
  Falls back to source images if no movie image is available.

  Sorts sources by priority and last_seen_at timestamp, then extracts
  the first available image from either the image_url field or metadata.
  """
  def get_cover_image_url(event) do
    # For movie events, prioritize movie images from TMDb
    case get_movie_image(event) do
      nil ->
        # Fall back to source image if no movie image available
        get_image_from_sources(event)

      image_url ->
        image_url
    end
  end

  defp get_movie_image(event) do
    case event.movies do
      [movie | _] when not is_nil(movie) ->
        # Prefer backdrop, fall back to poster
        cond do
          is_binary(movie.backdrop_url) and movie.backdrop_url != "" -> movie.backdrop_url
          is_binary(movie.poster_url) and movie.poster_url != "" -> movie.poster_url
          true -> nil
        end

      _ ->
        nil
    end
  end

  defp get_image_from_sources(event) do
    # Sort sources by priority and try to get the first available image
    # Fix: Sort by newest last_seen_at first (negative timestamp)
    sorted_sources =
      event.sources
      |> Enum.sort_by(fn source ->
        priority =
          case source.metadata do
            %{"priority" => p} when is_integer(p) ->
              p

            %{"priority" => p} when is_binary(p) ->
              case Integer.parse(p) do
                {num, _} -> num
                _ -> 10
              end

            _ ->
              10
          end

        # Newer timestamps first (negative for descending sort)
        ts =
          case source.last_seen_at do
            %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
            _ -> 9_223_372_036_854_775_807
          end

        {priority, ts}
      end)

    # Try to extract image from sources
    Enum.find_value(sorted_sources, fn source ->
      # First check the direct image_url field
      if source.image_url do
        source.image_url
      else
        # Fall back to metadata
        extract_image_from_metadata(source.metadata)
      end
    end)
  end

  defp extract_image_from_metadata(nil), do: nil

  defp extract_image_from_metadata(metadata) do
    cond do
      # Resident Advisor stores in raw_data -> event -> flyerFront
      flyer = get_in(metadata, ["raw_data", "event", "flyerFront"]) ->
        flyer

      # Ticketmaster stores images in an array
      images = get_in(metadata, ["ticketmaster_data", "images"]) ->
        case images do
          [%{"url" => url} | _] when is_binary(url) -> url
          _ -> nil
        end

      # Bandsintown and Karnet store in image_url
      url = metadata["image_url"] ->
        url

      true ->
        nil
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime

  @doc """
  Count total events matching filters (for pagination metadata).
  """
  def count_events(opts \\ []) do
    base_query = from(pe in PublicEvent, select: count(pe.id))

    # Apply geographic filter if coordinates are provided
    query =
      if opts[:center_lat] && opts[:center_lng] && opts[:radius_km] do
        filter_by_radius(base_query, opts[:center_lat], opts[:center_lng], opts[:radius_km])
      else
        base_query
      end

    query
    |> filter_past_events(opts[:show_past])
    |> filter_by_categories(opts[:categories])
    |> filter_by_date_range(opts[:start_date], opts[:end_date])
    |> filter_by_price_range(opts[:min_price], opts[:max_price])
    |> filter_by_location(opts[:city_id], opts[:country_id], opts[:venue_ids])
    |> apply_search(opts[:search])
    |> Repo.one()
  end

  @doc """
  Get facet counts for filters (useful for showing available options).
  """
  def get_filter_facets(base_filters \\ []) do
    # Get counts for each filterable dimension
    %{
      categories: get_category_counts(base_filters),
      cities: get_city_counts(base_filters),
      price_ranges: get_price_range_counts(base_filters),
      date_ranges: get_date_range_counts(base_filters)
    }
  end

  defp get_category_counts(base_filters) do
    from(pe in PublicEvent,
      join: pec in "public_event_categories",
      on: pec.event_id == pe.id,
      join: c in Category,
      on: c.id == pec.category_id,
      where: pe.starts_at > ^DateTime.utc_now(),
      group_by: [c.id, c.name],
      select: {c.id, c.name, count(pe.id)}
    )
    |> apply_base_filters(base_filters)
    |> Repo.all()
    |> Enum.map(fn {id, name, count} ->
      %{id: id, name: name, count: count}
    end)
  end

  defp get_city_counts(base_filters) do
    from(pe in PublicEvent,
      join: v in Venue,
      on: pe.venue_id == v.id,
      join: c in City,
      on: v.city_id == c.id,
      where: pe.starts_at > ^DateTime.utc_now(),
      group_by: [c.id, c.name],
      select: {c.id, c.name, count(pe.id)}
    )
    |> apply_base_filters(base_filters)
    |> Repo.all()
    |> Enum.map(fn {id, name, count} ->
      %{id: id, name: name, count: count}
    end)
  end

  defp get_price_range_counts(_base_filters) do
    # Price filtering not available - pricing data is source-specific
    # TODO: Implement using public_event_sources when price filtering is needed
    []
  end

  defp get_date_range_counts(base_filters) do
    now = DateTime.utc_now()
    today_end = DateTime.add(now, 86400, :second) |> DateTime.truncate(:second)
    week_end = DateTime.add(now, 7 * 86400, :second)
    month_end = DateTime.add(now, 30 * 86400, :second)

    [
      {:today, now, today_end},
      {:this_week, now, week_end},
      {:this_month, now, month_end}
    ]
    |> Enum.map(fn {label, start_date, end_date} ->
      count =
        from(pe in PublicEvent,
          where: pe.starts_at >= ^start_date and pe.starts_at <= ^end_date,
          select: count(pe.id)
        )
        |> apply_base_filters(base_filters)
        |> Repo.one()

      %{label: label, count: count}
    end)
  end

  defp apply_base_filters(query, filters) do
    # Apply any base filters that should affect facet counts
    # IMPORTANT: Must include show_past: true to get accurate counts
    query
    # Always show all events for counts
    |> filter_past_events(true)
    |> filter_by_categories(filters[:categories])
    |> apply_search(filters[:search])
  end

  @doc """
  Calculate date range boundaries for common filter presets.

  ## Examples
      iex> calculate_date_range(:today)
      {~U[2024-01-15 00:00:00Z], ~U[2024-01-15 23:59:59Z]}

      iex> calculate_date_range(:next_7_days)
      {~U[2024-01-15 00:00:00Z], ~U[2024-01-22 23:59:59Z]}
  """
  def calculate_date_range(range_type) do
    now = DateTime.utc_now()
    # Start of today (00:00:00 UTC)
    start_of_today =
      now
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00])

    end_of_today =
      now
      |> DateTime.to_date()
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00])
      |> DateTime.add(-1, :second)

    case range_type do
      :today ->
        {start_of_today, end_of_today}

      :tomorrow ->
        tomorrow_start = DateTime.add(end_of_today, 1, :second)
        tomorrow_end = DateTime.add(tomorrow_start, 86400 - 1, :second)
        {tomorrow_start, tomorrow_end}

      :this_weekend ->
        # Find next Friday, Saturday, Sunday
        date = DateTime.to_date(now)
        day_of_week = Date.day_of_week(date)

        # Days until Friday (5)
        days_to_friday = rem(5 - day_of_week + 7, 7)
        days_to_friday = if days_to_friday == 0 && day_of_week <= 5, do: 0, else: days_to_friday

        friday = Date.add(date, days_to_friday)
        sunday = Date.add(friday, 2)

        friday_start = DateTime.new!(friday, ~T[00:00:00])
        sunday_end = DateTime.new!(sunday, ~T[23:59:59])

        {friday_start, sunday_end}

      :next_7_days ->
        {start_of_today, DateTime.add(start_of_today, 7 * 86400 - 1, :second)}

      :next_30_days ->
        {start_of_today, DateTime.add(start_of_today, 30 * 86400 - 1, :second)}

      :this_month ->
        date = DateTime.to_date(now)
        end_of_month = Date.end_of_month(date)
        end_of_month_dt = DateTime.new!(end_of_month, ~T[23:59:59])
        {start_of_today, end_of_month_dt}

      :next_month ->
        date = DateTime.to_date(now)
        next_month_date = Date.add(Date.end_of_month(date), 1)
        next_month_start = DateTime.new!(next_month_date, ~T[00:00:00])
        next_month_end_date = Date.end_of_month(next_month_date)
        next_month_end = DateTime.new!(next_month_end_date, ~T[23:59:59])
        {next_month_start, next_month_end}

      _ ->
        {nil, nil}
    end
  end

  @doc """
  Get event counts for each quick date range filter.
  Supports all filters including geographic filtering (center_lat, center_lng, radius_km).
  """
  def get_quick_date_range_counts(filters \\ []) do
    [
      :today,
      :tomorrow,
      :this_weekend,
      :next_7_days,
      :next_30_days,
      :this_month,
      :next_month
    ]
    |> Enum.map(fn range_type ->
      {start_date, end_date} = calculate_date_range(range_type)

      # Build count options with date range and all other filters (including geographic)
      count_opts =
        filters
        |> Enum.into(%{})
        |> Map.put(:start_date, start_date)
        |> Map.put(:end_date, end_date)
        # Always show all events in range for counts
        |> Map.put(:show_past, true)

      count = count_events(count_opts)

      %{range: range_type, count: count}
    end)
    |> Enum.into(%{}, fn %{range: range, count: count} -> {range, count} end)
  end

  @doc """
  Group events by temporal periods for organized display.
  Returns a list of {period_label, events} tuples sorted by time.
  """
  def group_events_by_period(events) do
    now = DateTime.utc_now()

    events
    |> Enum.group_by(fn event -> categorize_event_period(event.starts_at, now) end)
    |> Enum.sort_by(fn {period, _events} -> period_sort_order(period) end)
  end

  defp categorize_event_period(nil, _now), do: :unknown

  defp categorize_event_period(starts_at, now) do
    today = DateTime.to_date(now)
    event_date = DateTime.to_date(starts_at)
    days_diff = Date.diff(event_date, today)

    # Extract year and month for comparison
    {today_year, today_month, _} = Date.to_erl(today)
    {event_year, event_month, _} = Date.to_erl(event_date)
    same_month = today_year == event_year && today_month == event_month

    cond do
      days_diff == 0 -> :today
      days_diff == 1 -> :tomorrow
      days_diff >= 2 && days_diff <= 7 -> :this_week
      days_diff >= 8 && same_month -> :later_this_month
      days_diff > 7 && !same_month -> :future
      true -> :past
    end
  end

  defp period_sort_order(period) do
    case period do
      :today -> 1
      :tomorrow -> 2
      :this_week -> 3
      :later_this_month -> 4
      :future -> 5
      :past -> 6
      :unknown -> 7
    end
  end

  @doc """
  Get time-sensitive badge info for an event.
  Returns a map with badge type and label, or nil if no badge applies.
  """
  def get_time_sensitive_badge(event) do
    now = DateTime.utc_now()

    case event.starts_at do
      nil ->
        nil

      starts_at ->
        hours_until = DateTime.diff(starts_at, now, :hour)
        days_until = div(hours_until, 24)

        cond do
          # Event has passed
          hours_until < 0 -> nil
          hours_until < 24 -> %{type: :last_chance, label: "🔥 Last Chance", emoji: "🔥"}
          days_until <= 7 -> %{type: :this_week, label: "⚡ This Week", emoji: "⚡"}
          days_until <= 30 -> %{type: :upcoming, label: "📅 Upcoming", emoji: "📅"}
          true -> nil
        end
    end
  end

  @doc """
  Get human-readable label for period type.
  """
  def period_label(period) do
    case period do
      :today -> "Today"
      :tomorrow -> "Tomorrow"
      :this_week -> "This Week"
      :later_this_month -> "Later This Month"
      :future -> "Future Events"
      :past -> "Past Events"
      :unknown -> "Unknown Date"
    end
  end

  @doc """
  List events with aggregation support for index pages.

  Returns a list containing both regular PublicEvent structs and AggregatedEventGroup structs.
  Events from sources with `aggregate_on_index: true` are grouped by source+city+type.

  When aggregation is enabled, pagination happens AFTER aggregation to ensure:
  - Aggregated cards appear only once across all pages
  - Consistent number of results per page (no gaps in grid layout)

  ## Options
  Same as list_events/1, plus:
    * `:aggregate` - Enable aggregation (default: false)

  ## Returns
  Mixed list of PublicEvent and AggregatedEventGroup structs
  """
  def list_events_with_aggregation(opts \\ []) do
    if opts[:aggregate] do
      # Extract & sanitize pagination params
      page = max(opts[:page] || 1, 1)
      page_size = min(opts[:page_size] || @default_limit, @max_limit)

      # Fetch window sized to requested page (cap at @max_limit)
      # Use larger multiplier for first page to ensure all events are seen for aggregation
      # Subsequent pages use smaller multiplier since aggregation is already established
      multiplier = if page == 1, do: 20, else: 3
      fetch_size = min(@max_limit, page * page_size * multiplier)

      # Build fetch opts without DB pagination
      # Handle both Keyword lists and Maps by converting to Map
      opts_without_pagination =
        opts
        |> Map.new()
        |> Map.drop([:page, :offset, :limit])
        |> Map.put(:page_size, fetch_size)

      events = list_events(opts_without_pagination)
      aggregated = aggregate_events(events, opts)

      # Apply pagination to aggregated results
      paginate_aggregated_results(aggregated, page, page_size)
    else
      list_events(opts)
    end
  end

  @doc """
  Aggregates events from sources marked for aggregation.

  Groups events by source+city combination and creates AggregatedEventGroup structs.
  Also groups movie screenings by movie+city and creates AggregatedMovieGroup structs.
  Non-aggregatable events are returned as-is.

  ## Options

    * `:ignore_city_in_aggregation` - When true, aggregates events by source only,
      ignoring city boundaries. Used for city-specific pages where geographic filtering
      already determines relevance.
    * `:viewing_city` - The city context for aggregation. When provided with
      `ignore_city_in_aggregation: true`, this city is used as the canonical city
      for generated aggregation groups.

  """
  def aggregate_events(events, opts \\ []) do
    # Preload sources, movies, venue, and venue associations for timezone conversion
    events_with_sources =
      Repo.preload(events, sources: :source, venue: [city_ref: :country], movies: [])

    # Separate movie events from other events
    {movie_events, other_events} = Enum.split_with(events_with_sources, &has_movie?/1)

    # Separate aggregatable from non-aggregatable events (for source-based aggregation)
    {aggregatable, non_aggregatable} = Enum.split_with(other_events, &event_aggregatable?/1)

    # Group aggregatable events by source+city (or source only if ignoring city boundaries)
    source_aggregated_groups =
      aggregatable
      |> Enum.group_by(fn event ->
        source = get_event_source(event)

        if opts[:ignore_city_in_aggregation] do
          # City-specific page: group by source only
          {source.id, source.aggregation_type}
        else
          # Global page: group by source + city to differentiate locations
          {source.id, event.venue.city_id, source.aggregation_type}
        end
      end)
      |> Enum.map(fn
        # When ignoring city boundaries, use viewing city as canonical city
        {{source_id, aggregation_type}, events} when is_map_key(opts, :ignore_city_in_aggregation) ->
          viewing_city = opts[:viewing_city]
          city_id = if viewing_city, do: viewing_city.id, else: nil
          build_aggregated_group(source_id, city_id, aggregation_type, events, viewing_city)

        # Normal city-based aggregation
        {{source_id, city_id, aggregation_type}, events} ->
          build_aggregated_group(source_id, city_id, aggregation_type, events, nil)
      end)
      |> Enum.reject(&is_nil/1)

    # Group movie events by movie+city (or movie only if ignoring city boundaries)
    {movie_aggregated_groups, failed_movie_events} =
      movie_events
      |> Enum.group_by(fn event ->
        movie = List.first(event.movies)

        if opts[:ignore_city_in_aggregation] do
          # City-specific page: group by movie only
          {movie.id}
        else
          # Global page: group by movie + city to differentiate locations
          {movie.id, event.venue.city_id}
        end
      end)
      |> Enum.reduce({[], []}, fn
        # When ignoring city boundaries, use viewing city as canonical city
        {{movie_id}, events}, {groups, failed} when is_map_key(opts, :ignore_city_in_aggregation) ->
          viewing_city = opts[:viewing_city]
          city_id = if viewing_city, do: viewing_city.id, else: nil

          case build_movie_aggregated_group(movie_id, city_id, events, viewing_city) do
            nil -> {groups, failed ++ events}
            group -> {[group | groups], failed}
          end

        # Normal city-based aggregation
        {{movie_id, city_id}, events}, {groups, failed} ->
          case build_movie_aggregated_group(movie_id, city_id, events, nil) do
            nil -> {groups, failed ++ events}
            group -> {[group | groups], failed}
          end
      end)

    # Build container aggregated groups for all events (not just aggregatable ones)
    # Containers should display even if individual events also display
    container_aggregated_groups = build_container_aggregated_groups(events_with_sources)

    # Combine all types and sort by starts_at (for groups, use first event's date)
    (source_aggregated_groups ++
       movie_aggregated_groups ++
       container_aggregated_groups ++ non_aggregatable ++ failed_movie_events)
    |> Enum.sort_by(fn
      # Groups sort to top
      %AggregatedEventGroup{} -> DateTime.utc_now()
      # Movie groups sort to top
      %AggregatedMovieGroup{} -> DateTime.utc_now()
      # Container groups sort to top
      %AggregatedContainerGroup{start_date: start_date} -> start_date || DateTime.utc_now()
      %PublicEvent{starts_at: starts_at} -> starts_at || DateTime.utc_now()
    end)
  end

  # Paginate aggregated results (in-memory pagination)
  defp paginate_aggregated_results(items, page, page_size) do
    page = max(page, 1)
    page_size = min(page_size, @max_limit)
    offset = (page - 1) * page_size

    items
    |> Enum.drop(offset)
    |> Enum.take(page_size)
  end

  @doc """
  Counts events with optional aggregation.

  When aggregate: true is passed, returns the count of aggregated groups
  rather than the raw event count.

  ## Options
  - `:aggregate` - If true, counts aggregated results instead of raw events
  - All other options are passed through to count_events/1

  ## Examples

      iex> count_events_with_aggregation(aggregate: true, city_id: 1)
      15  # Returns count of aggregated groups

      iex> count_events_with_aggregation(city_id: 1)
      47  # Returns raw event count
  """
  def count_events_with_aggregation(opts \\ []) do
    if opts[:aggregate] do
      # Fetch all events and aggregate them, then count results
      # Remove pagination params for counting
      count_opts =
        opts
        |> Map.new()
        |> Map.drop([:page, :page_size, :offset, :limit])
        |> Map.put(:page_size, @max_limit)

      events = list_events(count_opts)
      aggregated = aggregate_events(events, opts)

      length(aggregated)
    else
      count_events(opts)
    end
  end

  # Check if an event has an associated movie
  defp has_movie?(%PublicEvent{movies: movies}) when is_list(movies) and length(movies) > 0,
    do: true

  defp has_movie?(_), do: false

  # Check if an event should be aggregated
  defp event_aggregatable?(%PublicEvent{sources: sources}) when is_list(sources) do
    Enum.any?(sources, fn es ->
      es.source && es.source.aggregate_on_index == true
    end)
  end

  defp event_aggregatable?(_), do: false

  # Get the source for an event (first one with aggregate_on_index=true)
  defp get_event_source(%PublicEvent{sources: sources}) do
    Enum.find(sources, fn es ->
      es.source && es.source.aggregate_on_index == true
    end).source
  end

  # Build an AggregatedEventGroup from a list of events
  defp build_aggregated_group(source_id, city_id, aggregation_type, events, viewing_city) do
    # Get source and city info from first event
    first_event = List.first(events)
    source = get_event_source(first_event)

    if first_event.venue && first_event.venue.city_ref do
      # Get unique venues
      unique_venues = events |> Enum.map(& &1.venue_id) |> Enum.uniq() |> length()

      # Get all categories from events
      all_categories =
        events
        |> Enum.flat_map(&(&1.categories || []))
        |> Enum.uniq_by(& &1.id)

      # Use first event's cover image
      cover_image_url = first_event.cover_image_url || List.first(events).cover_image_url

      # Check if any event is recurring
      is_recurring = Enum.any?(events, &PublicEvent.recurring?/1)

      # Use viewing_city if provided (for city-specific pages), otherwise use first event's city
      canonical_city = viewing_city || first_event.venue.city_ref

      %AggregatedEventGroup{
        source_id: source_id,
        source_slug: source.slug,
        source_name: source.name,
        aggregation_type: aggregation_type || "events",
        city_id: city_id,
        city: canonical_city,
        event_count: length(events),
        venue_count: unique_venues,
        categories: all_categories,
        cover_image_url: cover_image_url,
        is_recurring: is_recurring
      }
    else
      nil
    end
  end

  # Build an AggregatedMovieGroup from a list of movie screening events
  defp build_movie_aggregated_group(movie_id, city_id, events, viewing_city) do
    first_event = List.first(events)
    movie = List.first(first_event.movies)

    if first_event.venue && first_event.venue.city_ref && movie do
      # Get unique venues
      unique_venues = events |> Enum.map(& &1.venue_id) |> Enum.uniq() |> length()

      # Get all categories from events
      all_categories =
        events
        |> Enum.flat_map(&(&1.categories || []))
        |> Enum.uniq_by(& &1.id)

      # Use viewing_city if provided (for city-specific pages), otherwise use first event's city
      canonical_city = viewing_city || first_event.venue.city_ref

      %AggregatedMovieGroup{
        movie_id: movie_id,
        movie_slug: movie.slug,
        movie_title: movie.title,
        movie_backdrop_url: movie.backdrop_url,
        movie_poster_url: movie.poster_url,
        movie_release_date: movie.release_date,
        city_id: city_id,
        city: canonical_city,
        screening_count: length(events),
        venue_count: unique_venues,
        categories: all_categories
      }
    else
      nil
    end
  end

  # Build container aggregated groups from events that belong to containers
  defp build_container_aggregated_groups(events) do
    # Extract event IDs for querying memberships
    event_ids = events |> Enum.map(& &1.id)

    if Enum.empty?(event_ids) do
      []
    else
      # Query all containers with their event counts for these events
      # Note: We get TOTAL counts for the container, not just filtered events
      container_data =
        from(c in PublicEventContainer,
          join: m in PublicEventContainerMembership,
          on: m.container_id == c.id,
          where: m.event_id in ^event_ids,
          group_by: c.id,
          select: %{
            container_id: c.id,
            slug: c.slug,
            type: c.container_type,
            title: c.title,
            description: c.description,
            start_date: c.start_date,
            end_date: c.end_date,
            metadata: c.metadata,
            event_ids: fragment("array_agg(?)", m.event_id),
            # Get TOTAL event count for this container (constant, unfiltered)
            total_event_count:
              fragment(
                "(SELECT COUNT(DISTINCT event_id) FROM public_event_container_memberships WHERE container_id = ?)",
                c.id
              ),
            # Get ALL unique venue IDs for this container (constant, unfiltered)
            total_venue_ids:
              fragment(
                "(SELECT array_agg(DISTINCT venue_id) FROM public_events WHERE id IN (SELECT event_id FROM public_event_container_memberships WHERE container_id = ?))",
                c.id
              )
          }
        )
        |> Repo.all()

      # Build groups from container data
      container_data
      |> Enum.map(fn container ->
        # Get events for this container
        container_events = events |> Enum.filter(&(&1.id in container.event_ids))

        if Enum.empty?(container_events) do
          nil
        else
          build_container_aggregated_group(container, container_events)
        end
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  defp build_container_aggregated_group(container, events) do
    first_event = List.first(events)

    if first_event && first_event.venue && first_event.venue.city_ref do
      # Get venue names from filtered events (for display purposes)
      venue_names = events |> Enum.map(& &1.venue.name) |> Enum.uniq()

      # Get cover image from first event (or could be from container metadata)
      cover_image = get_event_cover_image(first_event)

      %AggregatedContainerGroup{
        container_id: container.container_id,
        container_slug: container.slug,
        container_type: container.type,
        container_title: container.title,
        description: container.description,
        start_date: container.start_date,
        end_date: container.end_date,
        city_id: first_event.venue.city_id,
        city: first_event.venue.city_ref,
        # Use TOTAL counts from container query (constant, regardless of filtering)
        event_count: container.total_event_count,
        venue_ids: container.total_venue_ids || [],
        venue_names: venue_names,
        cover_image_url: cover_image,
        metadata: container.metadata || %{}
      }
    else
      nil
    end
  end

  # Get cover image from event (check multiple sources)
  defp get_event_cover_image(event) do
    cond do
      event.cover_image_url -> event.cover_image_url
      event.images && length(event.images) > 0 -> List.first(event.images)
      true -> nil
    end
  end
end
