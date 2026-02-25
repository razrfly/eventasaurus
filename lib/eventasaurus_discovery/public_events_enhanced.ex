defmodule EventasaurusDiscovery.PublicEventsEnhanced do
  @moduledoc """
  Enhanced PublicEvents context with comprehensive filtering, search, and pagination.
  """

  import Ecto.Query, warn: false
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Telemetry.CityPageTelemetry
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainer
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainerMembership
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Images.{EventSourceImages, ImageEnv}

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
    # CRITICAL FIX (Issue #3334 Phase 3): Exclude occurrences from city page queries
    # The occurrences JSONB column can contain massive data (100+ KB per event for
    # recurring cinema showtimes), causing Jason.decode!/2 to take 15+ seconds and
    # triggering DBConnection timeouts. City pages don't need occurrence data -
    # only the event detail page uses it.
    base_query =
      from(pe in PublicEvent,
        select_merge: %{occurrences: fragment("NULL")}
      )

    # Query timeout: 90 seconds for expensive city page queries (Issue #3347)
    # Default Postgrex timeout is 15s which is insufficient for 800+ event aggregation.
    # PgBouncer kills connections that exceed this, causing "connection closed by pool" errors.
    query_timeout = opts[:timeout] || 90_000

    # CRITICAL: Allow passing a custom repo for background jobs (Issue #3353)
    # PgBouncer in transaction mode kills long-running queries. Background jobs like
    # CityPageCacheRefreshJob can take 30-60+ seconds with 800+ events.
    # Pass `repo: EventasaurusApp.JobRepo` to bypass PgBouncer and use direct connection.
    repo = opts[:repo] || Repo

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
    |> repo.all(timeout: query_timeout)
    |> preload_with_sources(opts[:language], opts[:browsing_city_id], repo)
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

    # CRITICAL FIX (Issue #3334 Phase 3): Exclude occurrences from search queries
    # Query timeout: 60 seconds for search queries (Issue #3347)
    query_timeout = opts[:timeout] || 60_000

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
      offset: ^offset,
      select_merge: %{occurrences: fragment("NULL")}
    )
    |> Repo.all(timeout: query_timeout)
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
    # - It has no end date and hasn't started yet, OR
    # - It has occurrence_type = "unknown" and was seen in the last 7 days (freshness tracking)
    current_time = DateTime.utc_now()
    freshness_threshold = DateTime.add(current_time, -7, :day)

    from(pe in query,
      left_join: es in EventasaurusDiscovery.PublicEvents.PublicEventSource,
      on: es.event_id == pe.id,
      # Known dates: check starts_at/ends_at
      # Unknown occurrence type: check last_seen_at for freshness (JSONB query)
      where:
        (not is_nil(pe.ends_at) and pe.ends_at > ^current_time) or
          (is_nil(pe.ends_at) and pe.starts_at > ^current_time) or
          (fragment("? ->> 'occurrence_type'", es.metadata) == "unknown" and
             es.last_seen_at >= ^freshness_threshold),
      distinct: pe.id
    )
  end

  # Version of filter_past_events without `distinct: pe.id` for use in count queries
  # The COUNT(DISTINCT pe.id) in count_events handles deduplication instead
  defp filter_past_events_for_count(query, true), do: query

  defp filter_past_events_for_count(query, _) do
    current_time = DateTime.utc_now()
    freshness_threshold = DateTime.add(current_time, -7, :day)

    from(pe in query,
      left_join: es in EventasaurusDiscovery.PublicEvents.PublicEventSource,
      on: es.event_id == pe.id,
      # Known dates: check starts_at/ends_at
      # Unknown occurrence type: check last_seen_at for freshness (JSONB query)
      where:
        (not is_nil(pe.ends_at) and pe.ends_at > ^current_time) or
          (is_nil(pe.ends_at) and pe.starts_at > ^current_time) or
          (fragment("? ->> 'occurrence_type'", es.metadata) == "unknown" and
             es.last_seen_at >= ^freshness_threshold)
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
  #
  # PERF: Uses subquery pattern to force GIST index usage on venues_location_gist.
  # The index is defined as: ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
  # We must match this expression exactly for the index to be used.
  #
  # Previous approach joined venues inline, causing the query planner to choose
  # venues_city_id_covering_idx and do a full table scan with post-filter.
  # The subquery pattern forces the planner to use the spatial index first.

  defp filter_by_radius(query, nil, nil, nil), do: query
  defp filter_by_radius(query, nil, _lng, _radius), do: query
  defp filter_by_radius(query, _lat, nil, _radius), do: query
  defp filter_by_radius(query, _lat, _lng, nil), do: query

  defp filter_by_radius(query, center_lat, center_lng, radius_km) do
    # Convert Decimal types to float for PostGIS
    lat = to_float(center_lat)
    lng = to_float(center_lng)
    radius = to_float(radius_km)

    if is_number(lat) and is_number(lng) and is_number(radius) do
      do_filter_by_radius(query, lat, lng, radius)
    else
      query
    end
  end

  defp do_filter_by_radius(query, center_lat, center_lng, radius_km)
       when is_number(center_lat) and is_number(center_lng) and is_number(radius_km) do
    radius_meters = radius_km * 1000

    # Use JOIN instead of IN (subquery) for better query planning and index usage.
    # The geographic expression MUST match the GIST index definition exactly:
    # ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
    #
    # The JOIN approach allows PostgreSQL to:
    # 1. Use the spatial index during the join operation
    # 2. Avoid creating an intermediate result set
    # 3. Better estimate row counts for query planning
    from(pe in query,
      join: v in Venue,
      on: pe.venue_id == v.id,
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      where:
        fragment(
          "ST_DWithin(
            ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
            ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
            ?
          )",
          v.longitude,
          v.latitude,
          ^center_lng,
          ^center_lat,
          ^radius_meters
        )
    )
  end

  # Helper to convert various numeric types to float for PostGIS
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_float(n), do: n
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(_), do: nil

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
  # Popularity defaults to desc (most popular first), other fields default to asc
  defp apply_sorting(query, :popularity, nil), do: apply_sorting(query, :popularity, :desc)
  defp apply_sorting(query, field, nil), do: apply_sorting(query, field, :asc)

  defp apply_sorting(query, :starts_at, order) when order in [:asc, :desc] do
    from(pe in query, order_by: [{^order, pe.starts_at}])
  end

  defp apply_sorting(query, :title, order) when order in [:asc, :desc] do
    from(pe in query, order_by: [{^order, pe.title}])
  end

  defp apply_sorting(query, :popularity, order) when order in [:asc, :desc] do
    # Sort by posthog_view_count (synced from PostHog) with starts_at as secondary sort
    # Higher view counts first (desc), then by date
    from(pe in query, order_by: [{^order, pe.posthog_view_count}, {:asc, pe.starts_at}])
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

  defp preload_with_sources(events, language, browsing_city_id \\ nil, repo \\ Repo) do
    # Load browsing city with unsplash_gallery if provided
    browsing_city =
      if browsing_city_id do
        repo.get(City, browsing_city_id)
      else
        nil
      end

    # Phase 2 optimization (Issue #3331): Removed :performers preload
    # Performers are only used on individual event detail pages, not city page cards.
    # This eliminates unnecessary data loading and improves query performance.
    preloaded_events =
      events
      |> repo.preload([
        :categories,
        # Load nested source association for aggregate_events and cover images
        sources: :source,
        # Load nested venue associations for timezone mapping and aggregation
        venue: [city_ref: :country],
        # Load movies association for movie aggregation
        movies: []
      ])

    # BATCH FIX: Collect all source IDs and fetch cached URLs in ONE query
    # This fixes the N+1 problem that was causing 10+ second load times
    all_source_ids =
      preloaded_events
      |> Enum.flat_map(fn event -> Enum.map(event.sources, & &1.id) end)
      |> Enum.uniq()

    # Single batch query instead of 300-400 individual queries
    image_cache = EventSourceImages.get_urls(all_source_ids)

    preloaded_events
    |> Enum.map(fn event ->
      # Add display fields based on language
      Map.merge(event, %{
        display_title: get_localized_title(event, language),
        display_description: get_localized_description(event, language),
        cover_image_url: get_cover_image_url(event, browsing_city, image_cache)
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
  Helper to ensure events have required preloads for image enrichment.
  Can be piped into Ecto queries or called on query results.

  ## Examples

      # With query
      query
      |> PublicEventsEnhanced.preload_for_image_enrichment()
      |> Repo.all()

      # With event list
      events
      |> PublicEventsEnhanced.preload_for_image_enrichment()

  ## Preloaded Associations

    * `:sources` - For source images and fallback detection
    * `:movies` - For movie-specific images
    * `:categories` - For category determination
    * `venue: :city_ref` - For Unsplash fallback images (unsplash_gallery is a JSONB field on cities)
  """
  @spec preload_for_image_enrichment(Ecto.Query.t() | [PublicEvent.t()] | PublicEvent.t()) ::
          Ecto.Query.t() | [PublicEvent.t()] | PublicEvent.t()
  def preload_for_image_enrichment(query_or_events) do
    Repo.preload(query_or_events, [
      :sources,
      :movies,
      :categories,
      venue: :city_ref
    ])
  end

  @doc """
  Enriches events with cover_image_url using Unsplash city image fallbacks.

  This function provides a unified interface for adding cover images to events
  across different contexts (city-centric vs event-centric views).

  ## Strategies

    * `:browsing_city` - Use single browsing city for all events (city-centric views)
      Requires: `browsing_city_id` option
      Use case: City pages, city search results, aggregate detail pages

    * `:own_city` - Use each event's venue city (event-centric views)
      Default strategy when browsing_city_id not provided
      Use case: Event detail pages, global feed, nearby activities

    * `:skip` - Don't enrich, preserve existing cover_image_url values
      Use case: When events already have images or enrichment not needed

  ## Options

    * `:browsing_city_id` - City ID to use for :browsing_city strategy
    * `:force` - Re-enrich even if cover_image_url already set (default: false)
    * `:strategy` - Enrichment strategy (default: :own_city)

  ## Examples

      # City-centric view (all events use London's gallery)
      events = PublicEventsEnhanced.list_events(...)
      enriched = PublicEventsEnhanced.enrich_event_images(events,
        strategy: :browsing_city,
        browsing_city_id: london_id
      )

      # Event-centric view (each event uses its own city)
      events = PublicEventsEnhanced.list_events(...)
      enriched = PublicEventsEnhanced.enrich_event_images(events,
        strategy: :own_city
      )

      # Force re-enrichment
      enriched = PublicEventsEnhanced.enrich_event_images(events,
        strategy: :own_city,
        force: true
      )

  ## Preload Requirements

  Events must have these associations preloaded for enrichment to work:
    * `:sources` (for source images)
    * `:movies` (for movie-specific images)
    * `:categories` (for category determination)
    * `venue: [city_ref: :unsplash_gallery]` (for Unsplash fallback)

  Use `preload_for_image_enrichment/1` to ensure proper preloads.

  ## Telemetry

  Emits telemetry event when unable to enrich due to missing gallery:
    * `[:eventasaurus, :unsplash, :fallback_missing]`
  """
  @spec enrich_event_images([PublicEvent.t()], keyword()) :: [PublicEvent.t()]
  def enrich_event_images(events, opts \\ []) when is_list(events) do
    Logger.debug("Enriching #{length(events)} events with opts: #{inspect(opts)}")
    strategy = Keyword.get(opts, :strategy, :own_city)
    browsing_city_id = Keyword.get(opts, :browsing_city_id)
    force = Keyword.get(opts, :force, false)

    case strategy do
      :browsing_city when is_integer(browsing_city_id) ->
        # Fetch browsing city once, reuse for all events
        browsing_city = Repo.get(City, browsing_city_id)

        if browsing_city do
          Enum.map(events, &enrich_with_browsing_city(&1, browsing_city, force))
        else
          Logger.warning("Cannot enrich with browsing city: city #{browsing_city_id} not found")

          events
        end

      :own_city ->
        # Use each event's own venue city
        Enum.map(events, &enrich_with_own_city(&1, force))

      :skip ->
        events

      _ ->
        # Invalid strategy, return as-is with warning
        Logger.warning("Invalid enrichment strategy: #{inspect(strategy)}, using :own_city")
        Enum.map(events, &enrich_with_own_city(&1, force))
    end
  end

  # Private helper: enrich event using browsing city
  defp enrich_with_browsing_city(event, browsing_city, force) do
    # Check if cover_image_url already exists using Map.get (safe for Ecto structs)
    if force || is_nil(Map.get(event, :cover_image_url)) do
      # Pass the full City struct, not just the ID
      cover_image_url = get_cover_image_url(event, browsing_city)
      # Map.put works on Ecto structs (they are maps)
      Map.put(event, :cover_image_url, cover_image_url)
    else
      event
    end
  end

  # Private helper: enrich event using its own venue's city
  defp enrich_with_own_city(event, force) do
    # Check if cover_image_url already exists using Map.get (safe for Ecto structs)
    existing_url = Map.get(event, :cover_image_url)

    if force || is_nil(existing_url) do
      # Get city struct from event's venue (preloaded by preload_for_image_enrichment)
      city = get_in(event, [Access.key(:venue), Access.key(:city_ref)])

      if city do
        # Pass nil as browsing_city so it uses the venue's city (from the event itself)
        cover_image_url = get_cover_image_url(event, nil)

        if is_nil(cover_image_url) do
          # Emit telemetry for missing gallery
          :telemetry.execute(
            [:eventasaurus, :unsplash, :fallback_missing],
            %{count: 1},
            %{city_id: city.id, event_id: event.id}
          )
        end

        # Map.put works on Ecto structs (they are maps)
        Map.put(event, :cover_image_url, cover_image_url)
      else
        # No venue/city, can't enrich - emit telemetry
        :telemetry.execute(
          [:eventasaurus, :unsplash, :fallback_missing],
          %{count: 1},
          %{city_id: nil, event_id: event.id, reason: :no_venue}
        )

        event
      end
    else
      event
    end
  end

  @doc """
  Gets the cover image URL for an event from its sources.

  For movie events, prioritizes movie poster/backdrop from TMDb over source images.
  Falls back to source images if no movie image is available.
  For aggregate events without source images, falls back to city Unsplash images.

  Sorts sources by priority and last_seen_at timestamp, then extracts
  the first available image from either the image_url field or metadata.
  """
  def get_cover_image_url(event, browsing_city \\ nil, image_cache \\ %{}) do
    # For movie events, prioritize movie images from TMDb
    result =
      case get_movie_image(event) do
        nil ->
          # Fall back to source image if no movie image available
          from_sources = get_image_from_sources(event, browsing_city, image_cache)
          from_sources

        image_url ->
          image_url
      end

    result
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

  defp get_image_from_sources(event, browsing_city, image_cache) do
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

    # Try to extract image from sources, using pre-fetched cache map
    source_image =
      Enum.find_value(sorted_sources, fn source ->
        # Look up in pre-fetched cache map (O(1) instead of DB query)
        case get_cached_source_image(source, image_cache) do
          {:cached, cdn_url} ->
            cdn_url

          :not_cached ->
            # Fall back to original URL
            if source.image_url do
              source.image_url
            else
              extract_image_from_metadata(source.metadata)
            end
        end
      end)

    # If no source image found, fall back to city Unsplash images
    result =
      case source_image do
        nil ->
          fallback = get_city_fallback_image(event, browsing_city)
          fallback

        url ->
          url
      end

    result
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

  # Check if a source's image has been cached to R2.
  # Returns {:cached, cdn_url} if cached, :not_cached otherwise.
  #
  # Uses pre-fetched image_cache map for O(1) lookup instead of DB query.
  # The cache is populated by a single batch query in preload_with_sources.
  #
  # Also triggers lazy caching for enabled sources that haven't been cached yet.
  # This allows gradual migration of existing images without a backfill job.
  defp get_cached_source_image(source, image_cache) do
    # O(1) map lookup instead of individual DB query - fixes N+1 problem
    case Map.get(image_cache, source.id) do
      cdn_url when is_binary(cdn_url) ->
        {:cached, cdn_url}

      nil ->
        # Only trigger lazy caching in production
        if ImageEnv.production?(), do: maybe_trigger_lazy_caching(source)
        :not_cached
    end
  end

  # Trigger lazy caching for images from enabled sources.
  # This enables gradual migration of existing images.
  # Only runs in production (guarded by caller).
  defp maybe_trigger_lazy_caching(source) do
    alias EventasaurusDiscovery.Scraping.Processors.EventImageCaching

    # Only cache if source is enabled and has an image URL
    if source.image_url && EventImageCaching.enabled?(get_source_slug(source)) do
      source_slug = get_source_slug(source)

      # Queue for caching (async, won't block render)
      EventImageCaching.cache_event_image(
        source.image_url,
        source.id,
        source_slug,
        %{"lazy_cached" => true, "trigger" => "render"}
      )
    end

    :ok
  end

  # Extract source slug from a PublicEventSource.
  # Handles both preloaded and non-preloaded source associations.
  defp get_source_slug(%{source: %{slug: slug}}) when is_binary(slug), do: slug

  defp get_source_slug(%{source_id: source_id}) when is_integer(source_id) do
    # If source not preloaded, look it up
    case EventasaurusApp.Repo.get(EventasaurusDiscovery.Sources.Source, source_id) do
      %{slug: slug} -> slug
      _ -> nil
    end
  end

  defp get_source_slug(_), do: nil

  # Get city fallback image from Unsplash gallery.
  #
  # Returns an Unsplash image URL from the city's categorized gallery,
  # selected based on the event type, source, and venue.
  #
  # Prioritizes browsing city gallery over venue city gallery for aggregate pages.
  # Falls back gracefully through category chain if primary category has no images.
  # Uses CityFallbackImageCache for pre-computed CDN-transformed URLs.
  defp get_city_fallback_image(event, browsing_city) do
    alias EventasaurusApp.Cache.CityFallbackImageCache

    # Extract venue_id for image variation (ensures different images per venue on same day)
    venue_id =
      case event do
        %{venue: %{id: id}} when is_integer(id) -> id
        %{venue_id: id} when is_integer(id) -> id
        _ -> 0
      end

    # Determine category once
    category = determine_event_category(event)

    # Try browsing city first (for aggregate pages like /c/london/trivia/speed-quizzing)
    # Then fall back to venue's actual city
    city_id =
      cond do
        browsing_city && has_unsplash_gallery?(browsing_city) ->
          browsing_city.id

        true ->
          venue_city = get_event_city(event)
          has_gallery = has_unsplash_gallery?(venue_city)

          if has_gallery do
            venue_city && venue_city.id
          else
            # Fallback: Find a major city with gallery in the same country
            fallback = find_country_fallback_city(venue_city)
            fallback && fallback.id
          end
      end

    # Try cache first (pre-computed CDN-transformed URLs)
    if city_id do
      # Try primary category, then "general" fallback
      # Cache miss - fall back to direct computation (shouldn't happen after cache warm-up)
      CityFallbackImageCache.get_fallback_image(city_id, category, venue_id) ||
        CityFallbackImageCache.get_fallback_image(city_id, "general", venue_id) ||
        get_city_fallback_image_uncached(city_id, category, venue_id)
    else
      nil
    end
  end

  # Fallback for cache misses (should be rare after cache warm-up)
  defp get_city_fallback_image_uncached(city_id, category, venue_id) do
    city = Repo.get(City, city_id)

    if city do
      fallback_chain = [category, "general"] |> Enum.uniq()

      case try_category_chain(city, fallback_chain, venue_id) do
        nil -> nil
        url -> apply_cdn_transformations(url)
      end
    else
      nil
    end
  end

  # Get city from event (handles various preload scenarios)
  # City is already preloaded - return it directly
  defp get_event_city(%{venue: %{city_ref: %City{} = city}}), do: city

  # City was preloaded but is nil (venue has no city) - return nil without re-querying
  defp get_event_city(%{venue: %{city_ref: nil}}), do: nil

  # Venue exists but city_ref association not loaded (Ecto.Association.NotLoaded)
  # This shouldn't happen if preload_with_sources was called, but handle gracefully
  defp get_event_city(%{venue: %Venue{} = venue}) do
    case Repo.preload(venue, :city_ref) do
      %{city_ref: %City{} = city} -> city
      _ -> nil
    end
  end

  defp get_event_city(_), do: nil

  # Check if city has unsplash_gallery populated
  defp has_unsplash_gallery?(%City{unsplash_gallery: %{"categories" => categories}})
       when is_map(categories) do
    # Check if gallery has at least one category with images
    Enum.any?(categories, fn {_category, category_data} ->
      case category_data do
        %{"images" => images} when is_list(images) -> length(images) > 0
        _ -> false
      end
    end)
  end

  defp has_unsplash_gallery?(_), do: false

  # Find a fallback city with Unsplash gallery in the same country
  # Prioritizes geographically closer cities when coordinates available
  # Uses ETS cache for performance (eliminates ~12,740 database queries)
  defp find_country_fallback_city(nil), do: nil

  defp find_country_fallback_city(%City{country_id: country_id} = venue_city) do
    # Use cached city data instead of database query
    # The CityGalleryCache loads all cities with galleries on startup
    # and refreshes hourly, reducing load from 12,740 queries to 1 query/hour
    alias EventasaurusApp.Cache.CityGalleryCache

    CityGalleryCache.find_nearest_city(
      country_id,
      venue_city.latitude,
      venue_city.longitude
    )
  end

  # Determine event category using EventCategoryMapper
  defp determine_event_category(event) do
    EventasaurusApp.Events.CategoryMapper.determine_category(event)
  end

  # Try to get image from category chain (primary → fallback → general)
  defp try_category_chain(_city, [], _venue_id), do: nil

  defp try_category_chain(city, [category | rest], venue_id) do
    case get_category_image(city, category, venue_id) do
      nil -> try_category_chain(city, rest, venue_id)
      url -> url
    end
  end

  # Get image from specific category in city's unsplash_gallery
  defp get_category_image(city, category, venue_id)

  # Short-circuit when category is nil to avoid runtime errors
  defp get_category_image(_city, nil, _venue_id), do: nil

  defp get_category_image(
         %City{unsplash_gallery: %{"categories" => categories}} = _city,
         category,
         venue_id
       )
       when is_map(categories) and is_binary(category) do
    # JSONB keys are always strings, no need for atom conversion
    # This avoids String.to_atom/1 which can crash on nil and leak atoms
    case Map.get(categories, category) do
      %{"images" => images} when is_list(images) and length(images) > 0 ->
        # Get today's image with venue variation (daily rotation + per-venue offset)
        get_todays_image(images, venue_id)

      _ ->
        nil
    end
  end

  defp get_category_image(_, _, _), do: nil

  # Get today's image from category images (implements daily rotation with venue variation)
  # Combines day of year + venue_id to ensure different images per venue on same day
  defp get_todays_image(images, venue_id)

  defp get_todays_image(images, venue_id) when is_list(images) and length(images) > 0 do
    # Combine day + venue_id for unique but stable selection per venue
    day_of_year = Date.utc_today() |> Date.day_of_year()
    offset = day_of_year + venue_id
    index = rem(offset, length(images))

    case Enum.at(images, index) do
      %{"url" => url} when is_binary(url) -> url
      %{url: url} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp get_todays_image(_, _), do: nil

  # Apply CDN transformations to Unsplash images
  defp apply_cdn_transformations(url) when is_binary(url) do
    # Use Cloudflare CDN for transformations (returns original if CDN disabled)
    Eventasaurus.CDN.url(url, width: 800, quality: 85)
  end

  defp apply_cdn_transformations(nil), do: nil

  # Get a general city image from Unsplash gallery for aggregate groups
  # Uses "general" category with source_id for variation
  defp get_city_general_image(%City{} = city, source_id) when is_integer(source_id) do
    if has_unsplash_gallery?(city) do
      # Use source_id for variation so different sources get different images
      image_url = get_category_image(city, "general", source_id)
      apply_cdn_transformations(image_url)
    else
      nil
    end
  end

  defp get_city_general_image(_, _), do: nil

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

  Uses COUNT(DISTINCT pe.id) to handle cases where filter_past_events
  joins with event_sources (for unknown occurrence tracking), which can
  create duplicate rows.

  NOTE: We use filter_past_events_for_count instead of filter_past_events
  to avoid the `distinct: pe.id` clause, which conflicts with COUNT(DISTINCT pe.id).
  """
  def count_events(opts \\ []) do
    # Use DISTINCT count to handle joins that may create duplicate rows
    # (e.g., filter_past_events joins with event_sources for unknown occurrence tracking)
    base_query = from(pe in PublicEvent, select: fragment("COUNT(DISTINCT ?)", pe.id))

    # Apply geographic filter if coordinates are provided
    query =
      if opts[:center_lat] && opts[:center_lng] && opts[:radius_km] do
        filter_by_radius(base_query, opts[:center_lat], opts[:center_lng], opts[:radius_km])
      else
        base_query
      end

    # Allow passing a custom repo for background jobs (Issue #3347)
    repo = opts[:repo] || Repo

    query
    |> filter_past_events_for_count(opts[:show_past])
    |> filter_by_categories(opts[:categories])
    |> filter_by_date_range(opts[:start_date], opts[:end_date])
    |> filter_by_price_range(opts[:min_price], opts[:max_price])
    |> filter_by_location(opts[:city_id], opts[:country_id], opts[:venue_ids])
    |> apply_search(opts[:search])
    |> repo.one()
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

  Optimized to use a single SQL query with FILTER clauses for non-aggregation mode.
  For aggregation mode, falls back to sequential counting (cached via CityPageCache).
  """
  def get_quick_date_range_counts(filters \\ []) do
    filters_map = Enum.into(filters, %{})
    use_aggregation = Map.get(filters_map, :aggregate, false)

    if use_aggregation do
      # Aggregation requires fetching and aggregating events - use sequential counting
      # This is cached via CityPageCache with 15 minute TTL
      get_quick_date_range_counts_sequential(filters_map)
    else
      # Optimized: single query with FILTER clauses (7 queries → 1)
      get_quick_date_range_counts_single_query(filters_map)
    end
  end

  # Sequential counting for aggregation mode (cached externally)
  defp get_quick_date_range_counts_sequential(filters_map) do
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

      count_opts =
        filters_map
        |> Map.put(:start_date, start_date)
        |> Map.put(:end_date, end_date)
        |> Map.put(:show_past, true)

      count = count_events_with_aggregation(count_opts)
      %{range: range_type, count: count}
    end)
    |> Enum.into(%{}, fn %{range: range, count: count} -> {range, count} end)
  end

  # Single query optimization for non-aggregation mode (7 queries → 1)
  defp get_quick_date_range_counts_single_query(filters_map) do
    # Calculate all date ranges upfront
    ranges = %{
      today: calculate_date_range(:today),
      tomorrow: calculate_date_range(:tomorrow),
      this_weekend: calculate_date_range(:this_weekend),
      next_7_days: calculate_date_range(:next_7_days),
      next_30_days: calculate_date_range(:next_30_days),
      this_month: calculate_date_range(:this_month),
      next_month: calculate_date_range(:next_month)
    }

    # Build base query with all filters except date range
    base_query =
      from(pe in PublicEvent,
        select: %{
          starts_at: pe.starts_at
        }
      )

    # Apply all non-date filters
    query =
      base_query
      |> filter_past_events_for_count(true)
      |> filter_by_categories(filters_map[:categories])
      |> filter_by_price_range(filters_map[:min_price], filters_map[:max_price])
      |> filter_by_location(
        filters_map[:city_id],
        filters_map[:country_id],
        filters_map[:venue_ids]
      )
      |> apply_search(filters_map[:search])

    # Apply geographic filter if provided
    query =
      if filters_map[:center_lat] && filters_map[:center_lng] && filters_map[:radius_km] do
        filter_by_radius(
          query,
          filters_map[:center_lat],
          filters_map[:center_lng],
          filters_map[:radius_km]
        )
      else
        query
      end

    # Get the outer date bounds (next_30_days covers most ranges)
    {outer_start, _} = ranges.today
    {_, outer_end} = ranges.next_30_days

    # Also include next_month which may extend beyond next_30_days
    {_, next_month_end} = ranges.next_month

    actual_outer_end =
      if DateTime.compare(next_month_end, outer_end) == :gt, do: next_month_end, else: outer_end

    # Filter to the outer date range to reduce scan
    query =
      from(pe in query,
        where: pe.starts_at >= ^outer_start and pe.starts_at <= ^actual_outer_end,
        select: pe.starts_at
      )

    # Execute single query to get all relevant event starts_at
    event_times = Repo.all(query)

    # Count events in each range in memory
    %{
      today: count_in_range(event_times, ranges.today),
      tomorrow: count_in_range(event_times, ranges.tomorrow),
      this_weekend: count_in_range(event_times, ranges.this_weekend),
      next_7_days: count_in_range(event_times, ranges.next_7_days),
      next_30_days: count_in_range(event_times, ranges.next_30_days),
      this_month: count_in_range(event_times, ranges.this_month),
      next_month: count_in_range(event_times, ranges.next_month)
    }
  end

  # Count how many event times fall within a date range
  defp count_in_range(event_times, {start_dt, end_dt}) do
    Enum.count(event_times, fn dt ->
      DateTime.compare(dt, start_dt) != :lt and DateTime.compare(dt, end_dt) != :gt
    end)
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

      # Always fetch @max_limit raw events so aggregation output is consistent
      # across pages (variable fetch windows cause items to shift between pages).

      # Build fetch opts without DB pagination
      # Handle both Keyword lists and Maps by converting to Map
      opts_without_pagination =
        opts
        |> Map.new()
        |> Map.drop([:page, :offset, :limit])
        |> Map.put(:page_size, @max_limit)
        # Extract browsing_city_id from viewing_city for Unsplash fallback
        |> then(fn opts_map ->
          case opts_map[:viewing_city] do
            %{id: city_id} -> Map.put(opts_map, :browsing_city_id, city_id)
            _ -> opts_map
          end
        end)

      events = list_events(opts_without_pagination)
      aggregated = aggregate_events(events, opts)

      # Apply post-aggregation sorting
      # DB sorting happens before aggregation, so we need to re-sort after
      sort_by = opts[:sort_by] || :starts_at
      sort_order = opts[:sort_order] || :asc
      sorted = sort_aggregated_results(aggregated, sort_by, sort_order)

      # Apply pagination to sorted aggregated results
      paginate_aggregated_results(sorted, page, page_size)
    else
      list_events(opts)
    end
  end

  @doc """
  List events with aggregation AND return counts in a single pass.

  This consolidates what was previously 3 separate queries:
  1. list_events_with_aggregation (fetches events)
  2. count_events_with_aggregation (counts for pagination)
  3. count_events_with_aggregation (counts for "all events" without date filter)

  Now uses a single database fetch + in-memory aggregation for events/pagination,
  and an efficient SQL COUNT for the all_events_count.

  ## Returns

  `{events, total_count, all_events_count}` where:
  - `events` - Paginated list of events/aggregated groups for current page
  - `total_count` - Total aggregated items matching current filters (for pagination)
  - `all_events_count` - Raw event count without date filters (for "All Events" button).
    Note: This is an approximate count (raw events, not aggregated groups) for performance.
    The difference is typically small and acceptable for UI display purposes.

  ## Options

  Same as `list_events_with_aggregation/1`, plus:
  - `:all_events_filters` - Filters to use for all_events_count (typically without date range)
  """
  def list_events_with_aggregation_and_counts(opts \\ []) do
    # Extract city_slug for telemetry metadata
    city_slug =
      case opts[:viewing_city] do
        %{slug: slug} -> slug
        _ -> "unknown"
      end

    radius_km = opts[:radius_km] || 50

    telemetry_meta = %{city_slug: city_slug, radius_km: radius_km}

    if opts[:aggregate] do
      # Extract & sanitize pagination params
      page = max(opts[:page] || 1, 1)
      page_size = min(opts[:page_size] || @default_limit, @max_limit)

      # Always fetch @max_limit raw events so aggregation output is consistent
      # across pages (variable fetch windows cause items to shift between pages).

      # Build fetch opts without DB pagination
      opts_without_pagination =
        opts
        |> Map.new()
        |> Map.drop([:page, :offset, :limit, :all_events_filters])
        |> Map.put(:page_size, @max_limit)
        |> then(fn opts_map ->
          case opts_map[:viewing_city] do
            %{id: city_id} -> Map.put(opts_map, :browsing_city_id, city_id)
            _ -> opts_map
          end
        end)

      # TELEMETRY: Measure list_events query time
      {list_events_ms, events} =
        CityPageTelemetry.measure_query(:list_events, telemetry_meta, fn ->
          list_events(opts_without_pagination)
        end)

      CityPageTelemetry.log_if_slow("list_events", list_events_ms, telemetry_meta)

      # TELEMETRY: Measure aggregation time
      {aggregation_ms, aggregated} =
        CityPageTelemetry.measure_query(:aggregation, telemetry_meta, fn ->
          aggregate_events(events, opts)
        end)

      CityPageTelemetry.log_if_slow("aggregate_events", aggregation_ms, telemetry_meta)

      # Total count for pagination (current filters)
      total_count = length(aggregated)

      # Apply sorting
      sort_by = opts[:sort_by] || :starts_at
      sort_order = opts[:sort_order] || :asc
      sorted = sort_aggregated_results(aggregated, sort_by, sort_order)

      # Apply pagination to get current page
      paginated_events = paginate_aggregated_results(sorted, page, page_size)

      # Calculate "all events" count (without date filters)
      # Uses fetch + aggregate for accurate post-aggregation count.
      # The raw SQL COUNT was ~15 events higher because it counted individual
      # movie screenings that get collapsed into a single AggregatedMovieGroup.
      all_events_count =
        case opts[:all_events_filters] do
          nil ->
            # No separate filters, all_events = total
            total_count

          all_filters when is_map(all_filters) ->
            # Fetch events without date filter and aggregate for accurate count.
            # CRITICAL: Propagate :repo from parent opts (Issue #3352)
            all_opts =
              all_filters
              |> Map.drop([:page, :offset, :limit, :page_size, :all_events_filters])
              |> Map.put(:page_size, @max_limit)
              |> then(fn opts_map ->
                case opts[:repo] do
                  nil -> opts_map
                  repo -> Map.put(opts_map, :repo, repo)
                end
              end)
              |> then(fn opts_map ->
                case opts_map[:viewing_city] do
                  %{id: city_id} -> Map.put(opts_map, :browsing_city_id, city_id)
                  _ -> opts_map
                end
              end)

            # TELEMETRY: Measure fetch + aggregate for all events count
            {count_ms, count} =
              CityPageTelemetry.measure_query(:count_all_events, telemetry_meta, fn ->
                all_events = list_events(all_opts)
                all_aggregated = aggregate_events(all_events, opts)
                length(all_aggregated)
              end)

            CityPageTelemetry.log_if_slow("count_all_events (aggregated)", count_ms, telemetry_meta)
            count
        end

      # Log overall timing breakdown
      Logger.debug(
        "[CityPage:TIMING] #{city_slug} - list_events=#{list_events_ms}ms, aggregation=#{aggregation_ms}ms, events=#{length(events)}, aggregated=#{total_count}"
      )

      {paginated_events, total_count, all_events_count}
    else
      # Non-aggregated: use simple list with count
      {list_ms, events} =
        CityPageTelemetry.measure_query(:list_events, telemetry_meta, fn ->
          list_events(opts)
        end)

      CityPageTelemetry.log_if_slow("list_events (non-agg)", list_ms, telemetry_meta)

      # For non-aggregated, count via efficient SQL
      count_opts = opts |> Map.new() |> Map.drop([:page, :page_size, :offset, :limit])

      {count_ms, total_count} =
        CityPageTelemetry.measure_query(:count_events, telemetry_meta, fn ->
          count_events(count_opts)
        end)

      CityPageTelemetry.log_if_slow("count_events", count_ms, telemetry_meta)

      all_events_count =
        case opts[:all_events_filters] do
          nil ->
            total_count

          all_filters ->
            # CRITICAL: Propagate :repo from parent opts (Issue #3352)
            all_count_opts =
              all_filters
              |> Map.new()
              |> then(fn m -> if opts[:repo], do: Map.put(m, :repo, opts[:repo]), else: m end)

            count_events(all_count_opts)
        end

      {events, total_count, all_events_count}
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
    # Events already have sources preloaded from list_events/1 (via preload_with_sources/2)
    # which adds virtual fields like cover_image_url. Don't re-preload or we'll lose them!
    # Only preload if the associations are not already loaded.
    events_with_sources =
      if Enum.empty?(events) do
        events
      else
        first_event = List.first(events)
        # Check if sources are already loaded (from preload_with_sources)
        sources_loaded = match?(%Ecto.Association.NotLoaded{}, first_event.sources) == false
        venue_loaded = match?(%Ecto.Association.NotLoaded{}, first_event.venue) == false
        movies_loaded = match?(%Ecto.Association.NotLoaded{}, first_event.movies) == false

        if sources_loaded and venue_loaded and movies_loaded do
          # Already preloaded, don't reload to preserve virtual fields
          events
        else
          # Not preloaded, need to load associations
          Repo.preload(events, sources: :source, venue: [city_ref: :country], movies: [])
        end
      end

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
          city_id = if event.venue, do: event.venue.city_id, else: nil
          {source.id, city_id, source.aggregation_type}
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
          city_id = if event.venue, do: event.venue.city_id, else: nil
          {movie.id, city_id}
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

  # Sort aggregated results after aggregation
  # This is needed because DB sorting happens before aggregation
  defp sort_aggregated_results(items, :starts_at, order) do
    # For date sorting, separate aggregated groups (which have multiple dates)
    # from single events and sort appropriately
    {aggregated, non_aggregated} =
      Enum.split_with(items, fn
        %AggregatedEventGroup{} -> true
        %AggregatedMovieGroup{} -> true
        %AggregatedContainerGroup{} -> true
        _ -> false
      end)

    # Sort non-aggregated items by date
    sorted_non_aggregated =
      Enum.sort_by(
        non_aggregated,
        fn item ->
          get_item_start_date(item)
        end,
        {if(order == :desc, do: :desc, else: :asc), DateTime}
      )

    # Aggregated items go at the end (they have multiple dates, so date sorting is ambiguous)
    if order == :desc do
      aggregated ++ sorted_non_aggregated
    else
      sorted_non_aggregated ++ aggregated
    end
  end

  defp sort_aggregated_results(items, :title, order) do
    Enum.sort_by(
      items,
      fn item ->
        get_item_title(item) |> String.downcase()
      end,
      if(order == :desc, do: :desc, else: :asc)
    )
  end

  defp sort_aggregated_results(items, :popularity, order) do
    Enum.sort_by(
      items,
      fn item ->
        get_item_popularity(item)
      end,
      if(order == :desc, do: :desc, else: :asc)
    )
  end

  defp sort_aggregated_results(items, _field, _order), do: items

  # Helper to get title from various item types
  defp get_item_title(%PublicEvent{} = event) do
    event.display_title || event.title || ""
  end

  defp get_item_title(%AggregatedEventGroup{source_name: name}) when is_binary(name), do: name
  defp get_item_title(%AggregatedMovieGroup{movie_title: title}) when is_binary(title), do: title

  defp get_item_title(%AggregatedContainerGroup{container_title: title}) when is_binary(title),
    do: title

  defp get_item_title(_), do: ""

  # Helper to get start date from various item types
  defp get_item_start_date(%PublicEvent{starts_at: starts_at}),
    do: starts_at || DateTime.utc_now()

  # Aggregated groups don't have a single start date - they represent multiple events
  # Return a far-future date so they sort to end when sorting by date ascending
  defp get_item_start_date(%AggregatedEventGroup{}), do: ~U[2099-12-31 23:59:59Z]
  defp get_item_start_date(%AggregatedMovieGroup{}), do: ~U[2099-12-31 23:59:59Z]

  defp get_item_start_date(%AggregatedContainerGroup{start_date: date}) when not is_nil(date),
    do: date

  defp get_item_start_date(_), do: DateTime.utc_now()

  # Helper to get popularity from various item types
  defp get_item_popularity(%PublicEvent{posthog_view_count: count}) when is_integer(count),
    do: count

  defp get_item_popularity(%AggregatedEventGroup{event_count: count}) when is_integer(count),
    do: count

  defp get_item_popularity(%AggregatedMovieGroup{screening_count: count}) when is_integer(count),
    do: count

  defp get_item_popularity(%AggregatedContainerGroup{event_count: count}) when is_integer(count),
    do: count

  defp get_item_popularity(_), do: 0

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

      # Use viewing_city if provided (for city-specific pages), otherwise use first event's city
      canonical_city = viewing_city || first_event.venue.city_ref

      # Only create aggregated group if we have a valid city
      if canonical_city do
        # For multi-venue aggregates (>3), use city images to avoid showing just one venue
        # For small aggregates (1-3 venues), use first event's image (specific venue is OK)
        cover_image_url =
          if unique_venues > 3 do
            # Many venues: use general city Unsplash image to represent city-wide presence
            # Use source_id for variation so different sources get different images
            # IMPORTANT: Fall back to event image if city has no Unsplash gallery
            get_city_general_image(canonical_city, source_id) || first_event.cover_image_url
          else
            # Few venues: use first event's image (may show specific venue, which is appropriate)
            first_event.cover_image_url
          end

        # Check if any event is recurring
        is_recurring = Enum.any?(events, &PublicEvent.recurring?/1)

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

      # Only create aggregated group if we have a valid city
      if canonical_city do
        %AggregatedMovieGroup{
          movie_id: movie_id,
          movie_slug: movie.slug,
          movie_title: movie.title,
          movie_backdrop_url: movie.backdrop_url,
          movie_poster_url: movie.poster_url,
          movie_release_date: movie.release_date,
          movie_runtime: movie.runtime,
          movie_vote_average: extract_vote_average(movie.metadata),
          movie_genres: extract_genres(movie.metadata),
          movie_tagline: extract_tagline(movie.metadata),
          city_id: city_id,
          city: canonical_city,
          screening_count: length(events),
          venue_count: unique_venues,
          categories: all_categories
        }
      else
        nil
      end
    else
      nil
    end
  end

  # Extract vote_average from movie metadata (stored by TMDB sync)
  # Always coerce to float to match AggregatedMovieGroup.movie_vote_average spec (float() | nil)
  defp extract_vote_average(%{"vote_average" => v}) when is_number(v) and v > 0, do: v / 1

  defp extract_vote_average(%{"tmdb_data" => %{"vote_average" => v}})
       when is_number(v) and v > 0,
       do: v / 1

  defp extract_vote_average(_), do: nil

  # Extract genre names from movie metadata
  defp extract_genres(%{"genres" => genres}) when is_list(genres) do
    Enum.map(genres, fn
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_genres(_), do: []

  # Extract tagline from movie metadata
  defp extract_tagline(%{"tagline" => t}) when is_binary(t) and t != "", do: t
  defp extract_tagline(_), do: nil

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

  # =============================================================================
  # OPTIMIZED AGGREGATION QUERIES
  # =============================================================================
  # These functions use database-level aggregation (COUNT, GROUP BY) instead of
  # fetching all records and processing in Elixir. This dramatically improves
  # performance for aggregated content pages.
  # =============================================================================

  @doc """
  Get aggregation statistics for a source identifier using database-level aggregation.

  Returns stats without fetching full event records - uses COUNT and GROUP BY
  at the database level for optimal performance.

  ## Options
    * `:source_slug` - Required. The source identifier to aggregate.
    * `:center_lat` - Center latitude for geographic filtering.
    * `:center_lng` - Center longitude for geographic filtering.
    * `:radius_km` - Radius in kilometers for geographic filtering.

  ## Returns
  A map with aggregation statistics:
    * `:total_count` - Total events across all cities for this source
    * `:in_radius_count` - Events within the geographic radius
    * `:out_of_radius_count` - Events outside the geographic radius
    * `:unique_cities` - Number of unique cities with events
    * `:city_stats` - List of per-city statistics with counts and distances
  """
  def get_source_aggregation_stats(opts) do
    source_slug = opts[:source_slug]
    center_lat = opts[:center_lat]
    center_lng = opts[:center_lng]
    radius_km = opts[:radius_km] || 50

    # Get total count across all cities (no geo filter)
    total_count = count_events_by_source(source_slug)

    # Get count within radius (if coordinates provided)
    in_radius_count =
      if center_lat && center_lng do
        count_events_by_source_in_radius(source_slug, center_lat, center_lng, radius_km)
      else
        total_count
      end

    # Get per-city statistics with counts
    city_stats = get_city_stats_for_source(source_slug, center_lat, center_lng)

    %{
      total_count: total_count,
      in_radius_count: in_radius_count,
      out_of_radius_count: total_count - in_radius_count,
      unique_cities: length(city_stats),
      city_stats: city_stats
    }
  end

  @doc """
  Count events by source slug using database aggregation.
  Much faster than fetching all events and counting in Elixir.
  """
  def count_events_by_source(source_slug, opts \\ []) when is_binary(source_slug) do
    current_time = DateTime.utc_now()

    query =
      from(pe in PublicEvent,
        join: pes in "public_event_sources",
        on: pes.event_id == pe.id,
        join: s in "sources",
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        where:
          pe.starts_at > ^current_time or (not is_nil(pe.ends_at) and pe.ends_at > ^current_time),
        select: count(pe.id, :distinct)
      )

    query =
      case Keyword.get(opts, :city_id) do
        nil ->
          query

        city_id ->
          from(pe in query,
            join: v in Venue,
            on: pe.venue_id == v.id,
            where: v.city_id == ^city_id
          )
      end

    Repo.one(query) || 0
  end

  @doc """
  Count events by source slug within a geographic radius.
  Uses PostGIS ST_DWithin for efficient spatial filtering at the database level.
  """
  def count_events_by_source_in_radius(source_slug, center_lat, center_lng, radius_km)
      when is_binary(source_slug) and is_number(center_lat) and is_number(center_lng) do
    current_time = DateTime.utc_now()
    radius_meters = radius_km * 1000

    from(pe in PublicEvent,
      join: pes in "public_event_sources",
      on: pes.event_id == pe.id,
      join: s in "sources",
      on: s.id == pes.source_id,
      join: v in Venue,
      on: pe.venue_id == v.id,
      where: s.slug == ^source_slug,
      where:
        pe.starts_at > ^current_time or (not is_nil(pe.ends_at) and pe.ends_at > ^current_time),
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      where:
        fragment(
          "ST_DWithin(ST_MakePoint(?::float, ?::float)::geography, ST_MakePoint(?::float, ?::float)::geography, ?)",
          ^center_lng,
          ^center_lat,
          v.longitude,
          v.latitude,
          ^radius_meters
        ),
      select: count(pe.id, :distinct)
    )
    |> Repo.one() || 0
  end

  @doc """
  Get per-city statistics for a source, with event counts and optional distance calculations.
  Uses database-level GROUP BY for efficient aggregation.

  Returns a list of maps with:
    * `:city_id` - City ID
    * `:city_name` - City name
    * `:city_slug` - City slug for URLs
    * `:event_count` - Number of events in this city
    * `:venue_count` - Number of unique venues in this city
    * `:distance_km` - Distance from center coordinates (if provided)
  """
  def get_city_stats_for_source(source_slug, center_lat \\ nil, center_lng \\ nil)
      when is_binary(source_slug) do
    current_time = DateTime.utc_now()

    base_query =
      from(pe in PublicEvent,
        join: pes in "public_event_sources",
        on: pes.event_id == pe.id,
        join: s in "sources",
        on: s.id == pes.source_id,
        join: v in Venue,
        on: pe.venue_id == v.id,
        join: c in City,
        on: v.city_id == c.id,
        where: s.slug == ^source_slug,
        where:
          pe.starts_at > ^current_time or (not is_nil(pe.ends_at) and pe.ends_at > ^current_time),
        group_by: [c.id, c.name, c.slug, c.latitude, c.longitude],
        select: %{
          city_id: c.id,
          city_name: c.name,
          city_slug: c.slug,
          city_latitude: c.latitude,
          city_longitude: c.longitude,
          event_count: count(pe.id, :distinct),
          venue_count: fragment("COUNT(DISTINCT ?)", v.id)
        }
      )

    stats = Repo.all(base_query)

    # Calculate distances if center coordinates provided
    if center_lat && center_lng do
      stats
      |> Enum.map(fn stat ->
        distance =
          if stat.city_latitude && stat.city_longitude do
            calculate_haversine_distance(
              center_lat,
              center_lng,
              decimal_to_float(stat.city_latitude),
              decimal_to_float(stat.city_longitude)
            )
          else
            nil
          end

        Map.put(stat, :distance_km, distance)
      end)
      |> Enum.sort_by(fn stat ->
        # Sort: nil distances last, then by distance
        case stat.distance_km do
          nil -> {1, 999_999}
          d -> {0, d}
        end
      end)
    else
      stats
      |> Enum.map(&Map.put(&1, :distance_km, nil))
      |> Enum.sort_by(& &1.city_name)
    end
  end

  @doc """
  List events for display with pagination - only fetches what's needed for the current page.
  Use this after getting stats to load just the events needed for display.

  ## Options
    * `:source_slug` - Required. The source identifier.
    * `:city_id` - Optional. Filter to specific city.
    * `:center_lat`, `:center_lng`, `:radius_km` - Optional geographic filter.
    * `:page` - Page number (default: 1)
    * `:page_size` - Items per page (default: 20, max: 100)
    * `:browsing_city_id` - City ID for Unsplash fallback images
  """
  def list_events_for_source_display(opts) do
    source_slug = opts[:source_slug]
    city_id = opts[:city_id]
    page = opts[:page] || 1
    page_size = min(opts[:page_size] || 20, 100)

    query_opts = %{
      source_slug: source_slug,
      city_id: city_id,
      center_lat: opts[:center_lat],
      center_lng: opts[:center_lng],
      radius_km: opts[:radius_km],
      page: page,
      page_size: page_size,
      browsing_city_id: opts[:browsing_city_id]
    }

    list_events(query_opts)
  end

  @doc """
  Get a single representative event per venue for aggregated display.
  Much more efficient than fetching all events when you just need one per venue.

  Returns events grouped by venue with only one event per venue.
  """
  def list_events_grouped_by_venue(opts) do
    source_slug = opts[:source_slug]
    city_id = opts[:city_id]
    center_lat = opts[:center_lat]
    center_lng = opts[:center_lng]
    radius_km = opts[:radius_km] || 50
    browsing_city_id = opts[:browsing_city_id]
    current_time = DateTime.utc_now()

    # Use a window function to get one event per venue (most recent start time)
    # This is much more efficient than fetching all and grouping in Elixir
    # CRITICAL FIX (Issue #3334 Phase 3): Exclude occurrences from venue list queries
    base_query =
      from(pe in PublicEvent,
        join: pes in "public_event_sources",
        on: pes.event_id == pe.id,
        join: s in "sources",
        on: s.id == pes.source_id,
        join: v in Venue,
        on: pe.venue_id == v.id,
        where: s.slug == ^source_slug,
        where:
          pe.starts_at > ^current_time or (not is_nil(pe.ends_at) and pe.ends_at > ^current_time),
        # Use DISTINCT ON to get one event per venue (PostgreSQL specific)
        distinct: [v.id],
        order_by: [asc: v.id, asc: pe.starts_at],
        select: pe,
        select_merge: %{occurrences: fragment("NULL")}
      )

    # Apply city filter if provided
    query =
      if city_id do
        from([pe, pes, s, v] in base_query,
          where: v.city_id == ^city_id
        )
      else
        base_query
      end

    # Apply radius filter if coordinates provided
    query =
      if center_lat && center_lng do
        radius_meters = radius_km * 1000

        from([pe, pes, s, v] in query,
          where: not is_nil(v.latitude) and not is_nil(v.longitude),
          where:
            fragment(
              "ST_DWithin(ST_MakePoint(?::float, ?::float)::geography, ST_MakePoint(?::float, ?::float)::geography, ?)",
              ^center_lng,
              ^center_lat,
              v.longitude,
              v.latitude,
              ^radius_meters
            )
        )
      else
        query
      end

    query
    |> Repo.all()
    |> preload_with_sources(nil, browsing_city_id)
  end

  @doc """
  Get events grouped by city for multi-city display.
  Returns a map of city_id => list of events (one per venue).
  """
  def list_events_grouped_by_city_and_venue(opts) do
    source_slug = opts[:source_slug]
    browsing_city_id = opts[:browsing_city_id]
    current_time = DateTime.utc_now()

    # Get one event per venue across all cities
    # CRITICAL FIX (Issue #3334 Phase 3): Exclude occurrences from grouped queries
    events =
      from(pe in PublicEvent,
        join: pes in "public_event_sources",
        on: pes.event_id == pe.id,
        join: s in "sources",
        on: s.id == pes.source_id,
        join: v in Venue,
        on: pe.venue_id == v.id,
        where: s.slug == ^source_slug,
        where:
          pe.starts_at > ^current_time or (not is_nil(pe.ends_at) and pe.ends_at > ^current_time),
        # One event per venue
        distinct: [v.id],
        order_by: [asc: v.id, asc: pe.starts_at],
        select: pe,
        select_merge: %{occurrences: fragment("NULL")}
      )
      |> Repo.all()
      |> preload_with_sources(nil, browsing_city_id)
      |> Repo.preload(venue: :city_ref)

    # Group by city
    events
    |> Enum.group_by(fn event ->
      event.venue && event.venue.city_id
    end)
    |> Enum.reject(fn {city_id, _} -> is_nil(city_id) end)
    |> Enum.into(%{})
  end

  # Helper to safely convert Decimal to float
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(n) when is_float(n), do: n
  defp decimal_to_float(n) when is_integer(n), do: n * 1.0
  defp decimal_to_float(_), do: nil

  # Calculate distance between two points using Haversine formula
  # Returns distance in kilometers
  defp calculate_haversine_distance(lat1, lon1, lat2, lon2)
       when is_number(lat1) and is_number(lon1) and is_number(lat2) and is_number(lon2) do
    # Earth's radius in kilometers
    r = 6371.0

    # Convert to radians
    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    delta_lat = (lat2 - lat1) * :math.pi() / 180
    delta_lon = (lon2 - lon1) * :math.pi() / 180

    # Haversine formula
    a =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    distance = r * c

    Float.round(distance, 1)
  end

  defp calculate_haversine_distance(_, _, _, _), do: nil
end
