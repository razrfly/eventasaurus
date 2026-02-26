defmodule EventasaurusWeb.Api.V1.Mobile.EventController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.PublicEvents
  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup
  alias EventasaurusWeb.CityEvents
  alias EventasaurusApp.{Events, Repo}
  alias EventasaurusApp.Events.EventPlans
  alias EventasaurusApp.Events.EventParticipant
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias EventasaurusWeb.Helpers.SourceAttribution
  alias Eventasaurus.CDN
  alias EventasaurusWeb.Helpers.VenueHelpers
  alias EventasaurusWeb.Utils.TimezoneUtils

  require Logger

  @default_radius_km 50
  @max_radius_km 200
  @default_per_page 50
  @max_per_page 100

  @valid_sort_fields ~w(starts_at title popularity relevance)
  @valid_sort_orders ~w(asc desc)
  @accepted_locales ~w(en pl de fr es it nl pt ru uk cs sk hu ro bg hr sr sl)

  @spec nearby(Plug.Conn.t(), map()) :: Plug.Conn.t()
  @doc """
  GET /api/v1/mobile/events/nearby?lat=X&lng=Y&radius=Z

  Returns public events near the given coordinates.
  Radius is in meters (default: 50000 = 50km).

  Events are aggregated: movies showing at multiple venues are stacked into
  a single entry (matching web behavior). The `type` field distinguishes:
    - "public" — single public event
    - "movie_group" — aggregated movie screenings
    - "event_group" — aggregated source events (e.g. pub quizzes)
    - "container_group" — festival/conference grouping

  Optional filters:
    - categories: comma-separated category IDs
    - city_id: use city coordinates instead of lat/lng
    - search: text search query
    - date_range: today, tomorrow, this_weekend, next_7_days, etc.
    - sort_by: starts_at, title, popularity, relevance
    - sort_order: asc, desc
  """
  def nearby(conn, params) do
    with {:ok, lat, lng, city_id, city_slug} <- resolve_coordinates(params) do
      page = parse_int(params["page"], 1)
      per_page = min(parse_int(params["per_page"], @default_per_page), @max_per_page)

      # Live query path: full aggregation (movies + source groups + containers)
      # Use city_id when available (exact city boundary match);
      # fall back to radius for pure lat/lng searches (Issue #3673)
      language = params["language"] || "en"
      query_start = System.monotonic_time(:millisecond)

      opts =
        if city_id do
          [
            city_id: city_id,
            page: page,
            page_size: per_page,
            language: language
          ]
        else
          radius_km =
            case parse_float(params["radius"], "radius") do
              {:ok, meters} -> (meters / 1000) |> max(0) |> min(@max_radius_km)
              _ -> @default_radius_km
            end

          [
            center_lat: lat,
            center_lng: lng,
            radius_km: radius_km,
            page: page,
            page_size: per_page,
            language: language
          ]
        end
        |> maybe_add_browsing_city(city_id)
        |> maybe_add_categories(params)
        |> maybe_add_search(params)
        |> maybe_add_date_range(params)
        |> maybe_add_sort(params)

      # Try MV fallback first (sub-5ms) when city_id is available and no complex filters
      # MV doesn't support category/search/date filtering, only unfiltered listing
      has_complex_filters =
        Keyword.has_key?(opts, :categories) or Keyword.has_key?(opts, :search) or
          Keyword.has_key?(opts, :start_date) or Keyword.has_key?(opts, :end_date)

      case maybe_serve_from_mv(city_slug, page, per_page, has_complex_filters) do
        {:ok, {items, total_count, all_count, mv_date_counts, _source}} ->
          query_ms = System.monotonic_time(:millisecond) - query_start

          :telemetry.execute(
            [:eventasaurus, :mobile_api, :nearby],
            %{duration_ms: query_ms, event_count: total_count},
            %{path: :mv_fallback, city_id: city_id}
          )

          json(conn, %{
            events: Enum.map(items, &serialize_item/1),
            meta: %{
              page: page,
              per_page: per_page,
              total_count: total_count,
              all_events_count: all_count,
              date_range_counts: mv_date_counts
            }
          })

        :miss ->
          # Live query path with circuit breaker (Issue #3686 Phase 4)
          {items, total_count, all_count, date_range_counts, query_path} =
            CityEvents.with_circuit_breaker(
              city_slug,
              fn ->
                opts_for_aggregation =
                  opts
                  |> Keyword.put(:aggregate, true)
                  |> Keyword.put(:ignore_city_in_aggregation, true)
                  |> Map.new()
                  |> EventFilters.enrich_with_all_events_filters()

                {items, total_count, all_count} =
                  PublicEventsEnhanced.list_events_with_aggregation_and_counts(
                    opts_for_aggregation
                  )

                dr_counts =
                  compute_date_range_counts(city_id, lat, lng, params, opts[:radius_km])

                path = if(city_id, do: :city_id, else: :lat_lng)
                {items, total_count, all_count, dr_counts, path}
              end,
              on_failure: fn ->
                {items, total, all_count, date_counts, _} = CityEvents.serve_degraded(city_slug)
                {items, total, all_count, date_counts, if(city_id, do: :city_id, else: :lat_lng)}
              end
            )

          query_ms = System.monotonic_time(:millisecond) - query_start

          :telemetry.execute(
            [:eventasaurus, :mobile_api, :nearby],
            %{duration_ms: query_ms, event_count: total_count},
            %{path: query_path, city_id: city_id}
          )

          if query_ms > 200 do
            Logger.warning("Slow mobile nearby query",
              path: to_string(query_path),
              city_id: city_id,
              duration_ms: query_ms,
              event_count: total_count
            )
          end

          json(conn, %{
            events: Enum.map(items, &serialize_item/1),
            meta: %{
              page: page,
              per_page: per_page,
              total_count: total_count,
              all_events_count: all_count,
              date_range_counts: date_range_counts
            }
          })
      end
    else
      {:error, field, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_params", message: "#{field}: #{message}"})
    end
  end

  @spec categories(Plug.Conn.t(), map()) :: Plug.Conn.t()
  @doc """
  GET /api/v1/mobile/categories

  Returns active event categories.
  """
  def categories(conn, _params) do
    cats = Categories.list_active_categories(locale: "en")

    json(conn, %{
      categories: Enum.map(cats, &serialize_category/1)
    })
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  @doc """
  GET /api/v1/mobile/events/:slug

  Returns event details by slug. Checks both public events and user-created events.
  """
  def show(conn, %{"slug" => slug} = params) do
    user = conn.assigns.user

    with {:ok, language} <- validate_language(params["language"]) do
      case find_event_by_slug(slug, language) do
        {:ok, {:public, event}} ->
          json(conn, %{
            event:
              serialize_public_event_detail(event, language) |> add_attendance_info(slug, user)
          })

        {:ok, {:user, event}} ->
          json(conn, %{
            event: serialize_user_event_detail(event, user) |> add_attendance_info(event, user)
          })

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found", message: "Event not found"})
      end
    else
      {:error, :invalid_locale} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_params", message: "language: unsupported locale"})
    end
  end

  # --- Date range counts ---

  @date_ranges ~w(today tomorrow this_weekend next_7_days next_30_days this_month next_month)a

  # Use city_id when available for consistent city-boundary filtering (Issue #3673)
  defp compute_date_range_counts(city_id, _lat, _lng, params, _radius_km)
       when is_integer(city_id) do
    base_opts =
      [city_id: city_id]
      |> maybe_add_categories(params)
      |> maybe_add_search(params)

    do_compute_date_range_counts(base_opts)
  end

  defp compute_date_range_counts(_city_id, lat, lng, params, radius_km) do
    radius_km = radius_km || @default_radius_km

    base_opts =
      [center_lat: lat, center_lng: lng, radius_km: radius_km]
      |> maybe_add_categories(params)
      |> maybe_add_search(params)

    do_compute_date_range_counts(base_opts)
  end

  defp do_compute_date_range_counts(base_opts) do
    defaults = Map.new(@date_ranges, &{Atom.to_string(&1), 0})

    Task.Supervisor.async_stream_nolink(
      Eventasaurus.TaskSupervisor,
      @date_ranges,
      fn range ->
        {start_date, end_date} = PublicEventsEnhanced.calculate_date_range(range)

        count =
          base_opts
          |> Keyword.put(:start_date, start_date)
          |> Keyword.put(:end_date, end_date)
          |> Map.new()
          |> PublicEventsEnhanced.count_events()

        {Atom.to_string(range), count}
      end,
      max_concurrency: length(@date_ranges),
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(defaults, fn
      {:ok, {key, count}}, acc ->
        Map.put(acc, key, count)

      {:exit, reason}, acc ->
        Logger.error("Date range count task failed",
          reason: inspect(reason)
        )

        acc
    end)
  end

  # --- MV fallback for mobile (Issue #3686) ---

  # Try serving from the materialized view when city slug is available and no complex filters
  defp maybe_serve_from_mv(city_slug, page, per_page, has_complex_filters) do
    CityEvents.fetch_from_mv(city_slug, page: page, page_size: per_page, skip: has_complex_filters)
  end

  # --- Coordinate resolution ---

  defp resolve_coordinates(%{"city_id" => city_id} = _params) when is_binary(city_id) do
    case Integer.parse(city_id) do
      {id, _} ->
        case Repo.get(City, id) do
          %City{latitude: lat, longitude: lng, slug: slug}
          when not is_nil(lat) and not is_nil(lng) ->
            {:ok, Decimal.to_float(lat), Decimal.to_float(lng), id, slug}

          _ ->
            {:error, "city_id", "city not found"}
        end

      :error ->
        {:error, "city_id", "must be an integer"}
    end
  end

  defp resolve_coordinates(params) do
    with {:ok, lat} <- parse_float(params["lat"], "lat"),
         {:ok, lng} <- parse_float(params["lng"], "lng") do
      {:ok, lat, lng, nil, nil}
    end
  end

  # --- Filter builders ---

  defp maybe_add_browsing_city(opts, nil), do: opts
  defp maybe_add_browsing_city(opts, city_id), do: Keyword.put(opts, :browsing_city_id, city_id)

  defp maybe_add_categories(opts, %{"categories" => categories}) when is_binary(categories) do
    ids =
      categories
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.flat_map(fn s ->
        case Integer.parse(s) do
          {id, _} -> [id]
          :error -> []
        end
      end)

    case ids do
      [] -> opts
      ids -> Keyword.put(opts, :categories, ids)
    end
  end

  defp maybe_add_categories(opts, _params), do: opts

  defp maybe_add_search(opts, %{"search" => search}) when is_binary(search) and search != "" do
    Keyword.put(opts, :search, search)
  end

  defp maybe_add_search(opts, _params), do: opts

  defp maybe_add_date_range(opts, %{"date_range" => range}) when is_binary(range) do
    case EventFilters.parse_quick_range(range) do
      {:ok, :all} ->
        opts

      {:ok, range_atom} ->
        {start_date, end_date} = PublicEventsEnhanced.calculate_date_range(range_atom)

        opts
        |> Keyword.put(:start_date, start_date)
        |> Keyword.put(:end_date, end_date)

      :error ->
        opts
    end
  end

  defp maybe_add_date_range(opts, _params), do: opts

  defp maybe_add_sort(opts, params) do
    opts =
      case params["sort_by"] do
        sort when sort in @valid_sort_fields ->
          Keyword.put(opts, :sort_by, String.to_existing_atom(sort))

        _ ->
          opts
      end

    case params["sort_order"] do
      order when order in @valid_sort_orders ->
        Keyword.put(opts, :sort_order, String.to_existing_atom(order))

      _ ->
        opts
    end
  end

  # --- Serialization (polymorphic: handles all item types from aggregate_events) ---

  defp serialize_item(%AggregatedMovieGroup{} = group) do
    %{
      slug: group.movie_slug,
      title: AggregatedMovieGroup.title(group),
      starts_at: group.earliest_starts_at,
      ends_at: nil,
      cover_image_url: resolve_image_url(group.movie_backdrop_url || group.movie_poster_url),
      type: "movie_group",
      venue: nil,
      screening_count: group.screening_count,
      venue_count: group.venue_count,
      subtitle: AggregatedMovieGroup.description(group),
      runtime: group.movie_runtime,
      vote_average: group.movie_vote_average,
      genres: group.movie_genres,
      tagline: group.movie_tagline
    }
  end

  defp serialize_item(%AggregatedEventGroup{} = group) do
    %{
      slug: group.source_slug,
      title: AggregatedEventGroup.title(group),
      starts_at: nil,
      ends_at: nil,
      cover_image_url: resolve_image_url(group.cover_image_url),
      type: "event_group",
      venue: nil,
      event_count: group.event_count,
      venue_count: group.venue_count,
      subtitle: AggregatedEventGroup.description(group)
    }
  end

  defp serialize_item(%AggregatedContainerGroup{} = group) do
    %{
      slug: group.container_slug,
      title: AggregatedContainerGroup.title(group),
      starts_at: group.start_date,
      ends_at: group.end_date,
      cover_image_url: resolve_image_url(group.cover_image_url),
      type: "container_group",
      venue: nil,
      event_count: group.event_count,
      venue_count: length(group.venue_ids || []),
      subtitle: AggregatedContainerGroup.description(group),
      container_type: to_string(group.container_type)
    }
  end

  # Plain map from MV fallback (not a struct — has :slug key but no __struct__)
  defp serialize_item(%{slug: slug, title: title} = event)
       when is_map(event) and not is_struct(event) do
    %{
      slug: slug,
      title: title,
      starts_at: event[:starts_at],
      ends_at: event[:ends_at],
      cover_image_url: resolve_image_url(event[:cover_image_url]),
      type: "public",
      venue:
        case event[:venue] do
          %{name: _} = venue ->
            %{
              name: venue[:name],
              slug: venue[:slug],
              latitude: venue[:latitude],
              longitude: venue[:longitude]
            }

          _ ->
            nil
        end,
      categories:
        case event[:category] do
          %{name: name, slug: cat_slug} -> [%{name: name, slug: cat_slug}]
          _ -> []
        end
    }
  end

  defp serialize_item(event) do
    serialize_public_event(event)
  end

  # --- Private helpers ---

  defp find_event_by_slug(slug, language) do
    case PublicEvents.get_by_slug(slug) do
      %{} = event ->
        # Preload sources, movies, and venue for cover image resolution and attribution
        event = Repo.preload(event, sources: [:source], movies: [], venue: [city_ref: :country])

        # Populate virtual fields that preload_with_sources normally sets
        event =
          Map.merge(event, %{
            cover_image_url: PublicEventsEnhanced.get_cover_image_url(event),
            display_title: get_localized_field(event.title_translations, event.title, language),
            display_description: get_source_description(event.sources, language)
          })

        {:ok, {:public, event}}

      nil ->
        case Events.get_event_by_slug(slug) do
          %{} = event -> {:ok, {:user, event}}
          nil -> {:error, :not_found}
        end
    end
  end

  defp get_localized_field(nil, fallback, _language), do: fallback

  defp get_localized_field(translations, fallback, language) when is_map(translations) do
    translations[language] || translations["en"] || fallback
  end

  defp get_localized_field(_, fallback, _language), do: fallback

  defp get_source_description(sources, language) do
    case get_sorted_sources(sources) do
      [source | _] ->
        case source.description_translations do
          translations when is_map(translations) ->
            translations[language] || translations["en"] || first_map_value(translations)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp first_map_value(map) when map_size(map) > 0 do
    Enum.find_value(@accepted_locales, fn locale -> Map.get(map, locale) end) ||
      map |> Map.values() |> List.first()
  end

  defp first_map_value(_), do: nil

  defp validate_language(nil), do: {:ok, "en"}
  defp validate_language(lang) when lang in @accepted_locales, do: {:ok, lang}
  defp validate_language(_), do: {:error, :invalid_locale}

  defp serialize_category(cat) do
    %{
      id: cat.id,
      name: cat.name,
      slug: cat.slug,
      icon: cat.icon,
      color: cat.color
    }
  end

  defp serialize_public_event(event) do
    %{
      slug: event.slug,
      title: event.display_title || event.title,
      starts_at: event.starts_at,
      ends_at: event.ends_at,
      cover_image_url: resolve_image_url(event.cover_image_url),
      type: "public",
      venue: serialize_venue(event.venue),
      categories: serialize_categories(event)
    }
  end

  defp serialize_public_event_detail(event, language) do
    nearby_events =
      PublicEvents.get_nearby_activities_with_fallback(event,
        display_count: 4,
        language: language
      )

    movie_slug =
      case event.movies do
        [movie | _] when not is_nil(movie) -> movie.slug
        _ -> nil
      end

    city_id =
      case event.venue do
        %{city_ref: %{id: id}} when not is_nil(id) -> id
        _ -> nil
      end

    serialize_public_event(event)
    |> Map.merge(%{
      description: event.display_description,
      ticket_url: get_primary_source_ticket_url(event),
      sources: serialize_sources(event),
      nearby_events: Enum.map(nearby_events, &serialize_public_event/1),
      movie_group_slug: movie_slug,
      movie_city_id: city_id,
      occurrences: enrich_occurrences(event)
    })
  end

  defp enrich_occurrences(event) do
    timezone =
      case event.venue do
        %{city_ref: %{timezone: tz}} when is_binary(tz) and tz != "" -> tz
        _ -> TimezoneUtils.default_timezone()
      end

    occurrences = event.occurrences || %{}

    enriched_dates =
      case Map.get(occurrences, "dates") do
        dates when is_list(dates) ->
          Enum.map(dates, fn date_info ->
            with {:ok, date} <- Date.from_iso8601(date_info["date"] || ""),
                 [h, m] <- String.split(date_info["time"] || "", ":"),
                 {hour, ""} <- Integer.parse(h),
                 {min, ""} <- Integer.parse(m),
                 {:ok, time} <- Time.new(hour, min, 0),
                 {:ok, dt} <- DateTime.new(date, time, timezone) do
              Map.put(date_info, "datetime", dt)
            else
              {:ambiguous, dt, _} -> Map.put(date_info, "datetime", dt)
              {:gap, _, after_dt} -> Map.put(date_info, "datetime", after_dt)
              _ -> date_info
            end
          end)

        _ ->
          []
      end

    Map.put(occurrences, "dates", enriched_dates)
  end

  defp serialize_user_event(event) do
    %{
      slug: event.slug,
      title: event.title,
      starts_at: event.start_at,
      ends_at: event.ends_at,
      cover_image_url: resolve_image_url(event.cover_image_url),
      type: "user",
      venue: serialize_venue(event.venue)
    }
  end

  defp serialize_user_event_detail(event, user) do
    cover_image_url = event.cover_image_url || EventPlans.get_public_event_cover_url(event.id)

    participant_count =
      Events.list_event_participants(event)
      |> length()

    registration_status = Events.get_user_registration_status(event, user)

    serialize_user_event(event)
    |> Map.delete(:cover_image_url)
    |> Map.merge(%{
      cover_image_url: resolve_image_url(cover_image_url),
      description: event.description,
      attendee_count: participant_count,
      is_attending: registration_status in [:registered, :organizer],
      status: to_string(event.status)
    })
  end

  defp serialize_categories(%{categories: categories}) when is_list(categories) do
    Enum.map(categories, fn cat ->
      %{name: cat.name, slug: cat.slug, icon: cat.icon, color: cat.color}
    end)
  end

  defp serialize_categories(_), do: []

  defp serialize_venue(nil), do: nil

  defp serialize_venue(venue) do
    %{
      name: VenueHelpers.venue_display_name(venue.name),
      slug: venue.slug,
      address: venue.address,
      lat: venue.latitude,
      lng: venue.longitude
    }
  end

  # --- Source / Ticket helpers ---

  defp get_primary_source_ticket_url(event) do
    get_sorted_sources(event.sources)
    |> Enum.find_value(fn source ->
      case SourceAttribution.get_source_url(source) do
        nil -> nil
        "" -> nil
        url -> url
      end
    end)
  end

  defp get_sorted_sources(sources) when is_list(sources) do
    sources
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

      ts =
        case source.last_seen_at do
          %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
          _ -> 9_223_372_036_854_775_807
        end

      {priority, ts}
    end)
  end

  defp get_sorted_sources(_), do: []

  defp serialize_sources(event) do
    case event.sources do
      sources when is_list(sources) ->
        sources
        |> SourceAttribution.deduplicate_sources()
        |> Enum.map(fn source ->
          %{
            name: SourceAttribution.get_source_name(source),
            logo_url: SourceAttribution.get_source_logo_url(source),
            url: SourceAttribution.get_source_url(source)
          }
        end)

      _ ->
        []
    end
  end

  # Resolve image URLs through the same CDN pipeline the web uses.
  # Handles legacy Supabase→R2 conversion and applies Cloudflare optimization.
  # Unlike the web (which can load HTTP URLs in browsers), mobile clients
  # require HTTPS, so we always apply CDN transformation for HTTP URLs.
  @cdn_opts [width: 400, height: 300, fit: "cover", quality: 85]
  defp resolve_image_url(nil), do: nil

  defp resolve_image_url(url) do
    case CDN.url(url, @cdn_opts) do
      # CDN disabled in dev — still need to upgrade HTTP→HTTPS for mobile
      ^url -> ensure_https(url)
      cdn_url -> cdn_url
    end
  end

  defp ensure_https("http://" <> rest), do: "https://" <> rest
  defp ensure_https(url), do: url

  defp parse_float(nil, field), do: {:error, field, "is required"}

  defp parse_float(val, field) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> {:ok, num}
      :error -> {:error, field, "must be a number"}
    end
  end

  defp parse_float(val, _field) when is_number(val), do: {:ok, val / 1}

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} when num > 0 -> num
      _ -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val) and val > 0, do: val
  defp parse_int(_, default), do: default

  # --- Attendance / RSVP helpers ---

  # For public events, look up by slug in the user events table (RSVP works on user events)
  defp add_attendance_info(serialized, slug_or_event, user) when is_binary(slug_or_event) do
    case Events.get_event_by_slug(slug_or_event) do
      nil ->
        Map.merge(serialized, %{attendance_status: nil, is_attending: false, attendee_count: 0})

      event ->
        add_attendance_info(serialized, event, user)
    end
  end

  defp add_attendance_info(serialized, _event, nil) do
    Map.merge(serialized, %{attendance_status: nil, is_attending: false, attendee_count: 0})
  end

  defp add_attendance_info(serialized, event, user) do
    participant = Events.get_event_participant_by_event_and_user(event, user)

    status =
      case participant do
        %EventParticipant{status: s} -> Atom.to_string(s)
        nil -> nil
      end

    attendee_count =
      Events.count_participants_by_status(event, :accepted) +
        Events.count_participants_by_status(event, :confirmed_with_order)

    Map.merge(serialized, %{
      attendance_status: status,
      is_attending: status in ["accepted", "confirmed_with_order"],
      attendee_count: attendee_count
    })
  end
end
