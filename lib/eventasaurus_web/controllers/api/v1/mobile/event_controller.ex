defmodule EventasaurusWeb.Api.V1.Mobile.EventController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.PublicEvents
  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup
  alias EventasaurusApp.{Events, Repo}
  alias EventasaurusApp.Events.EventParticipant
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias EventasaurusWeb.Helpers.SourceAttribution
  alias Eventasaurus.CDN

  require Logger

  @default_radius_km 50
  @default_per_page 20
  @max_per_page 100

  @valid_sort_fields ~w(starts_at title popularity relevance)
  @valid_sort_orders ~w(asc desc)

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
    with {:ok, lat, lng, city_id} <- resolve_coordinates(params) do
      radius_km =
        case parse_float(params["radius"], "radius") do
          {:ok, meters} -> meters / 1000
          _ -> @default_radius_km
        end

      page = parse_int(params["page"], 1)
      per_page = min(parse_int(params["per_page"], @default_per_page), @max_per_page)

      opts =
        [
          center_lat: lat,
          center_lng: lng,
          radius_km: radius_km,
          page: page,
          page_size: per_page,
          language: params["language"] || "en"
        ]
        |> maybe_add_browsing_city(city_id)
        |> maybe_add_categories(params)
        |> maybe_add_search(params)
        |> maybe_add_date_range(params)
        |> maybe_add_sort(params)

      # Fetch up to 500 events, aggregate, then paginate in-memory
      # (matches the web pipeline — without this, DB pagination fetches only
      # 20 events, leaving almost nothing to aggregate).
      opts_for_aggregation =
        opts
        |> Keyword.put(:aggregate, true)
        |> Keyword.put(:ignore_city_in_aggregation, true)
        |> Map.new()
        |> EventFilters.enrich_with_all_events_filters()

      {items, total_count, all_count} =
        PublicEventsEnhanced.list_events_with_aggregation_and_counts(opts_for_aggregation)

      # Compute date range counts for filter chips (efficient SQL COUNTs)
      date_range_counts = compute_date_range_counts(lat, lng, radius_km, params)

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
    else
      {:error, field, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_params", message: "#{field}: #{message}"})
    end
  end

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

  @doc """
  GET /api/v1/mobile/events/attending

  Returns events the current user is participating in.
  """
  def attending(conn, _params) do
    user = conn.assigns.user

    events =
      Events.list_events_with_participation(user,
        upcoming: true,
        order_by: [asc: :start_at],
        limit: 50
      )

    json(conn, %{
      events: Enum.map(events, &serialize_user_event/1),
      meta: %{total_count: length(events)}
    })
  end

  @doc """
  GET /api/v1/mobile/events/:slug

  Returns event details by slug. Checks both public events and user-created events.
  """
  def show(conn, %{"slug" => slug}) do
    user = conn.assigns.user

    case find_event_by_slug(slug) do
      {:public, event} ->
        json(conn, %{
          event: serialize_public_event_detail(event) |> add_attendance_info(slug, user)
        })

      {:user, event} ->
        json(conn, %{
          event: serialize_user_event_detail(event, user) |> add_attendance_info(event, user)
        })

      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Event not found"})
    end
  end

  @doc """
  PUT /api/v1/mobile/events/:slug/participant-status

  Updates the current user's RSVP status for an event.
  """
  def update_participant_status(conn, %{"slug" => slug} = params) do
    user = conn.assigns.user
    status_str = params["status"]
    valid_statuses = EventParticipant.valid_status_strings()

    with {:status_valid, true} <- {:status_valid, status_str in valid_statuses},
         {:event, event} when not is_nil(event) <- {:event, Events.get_event_by_slug(slug)} do
      status_atom = String.to_existing_atom(status_str)

      case Events.update_participant_status(event, user, status_atom) do
        {:ok, participant} ->
          count =
            Events.count_participants_by_status(event, :accepted) +
              Events.count_participants_by_status(event, :confirmed_with_order)

          json(conn, %{
            status: status_str,
            participant_count: count,
            updated_at: participant.updated_at
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "update_failed", message: format_changeset_errors(changeset)})
      end
    else
      {:status_valid, false} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_status",
          message: "Valid statuses: #{Enum.join(valid_statuses, ", ")}"
        })

      {:event, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Event not found"})
    end
  end

  @doc """
  DELETE /api/v1/mobile/events/:slug/participant-status

  Removes the current user's RSVP status from an event.
  """
  def remove_participant_status(conn, %{"slug" => slug}) do
    user = conn.assigns.user

    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Event not found"})

      event ->
        case Events.remove_participant_status(event, user) do
          {:ok, :removed} ->
            json(conn, %{removed: true})

          {:ok, :not_participant} ->
            json(conn, %{removed: true})

          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.error("Failed to remove participant status",
              slug: slug,
              user_id: user.id,
              reason: inspect(Ecto.Changeset.traverse_errors(changeset, & &1))
            )

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "remove_failed", message: format_changeset_errors(changeset)})

          {:error, reason} ->
            Logger.error("Failed to remove participant status",
              slug: slug,
              user_id: user.id,
              reason: inspect(reason, structs: false)
            )

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "remove_failed", message: "Failed to remove attendance status"})
        end
    end
  end

  @doc """
  GET /api/v1/mobile/events/:slug/participant-status

  Gets the current user's RSVP status for an event.
  """
  def get_participant_status(conn, %{"slug" => slug}) do
    user = conn.assigns.user

    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Event not found"})

      event ->
        case Events.get_event_participant_by_event_and_user(event, user) do
          %EventParticipant{status: status, updated_at: updated_at} ->
            json(conn, %{status: Atom.to_string(status), updated_at: updated_at})

          nil ->
            json(conn, %{status: nil, updated_at: nil})
        end
    end
  end

  # --- Date range counts ---

  @date_ranges ~w(today tomorrow this_weekend next_7_days next_30_days this_month next_month)a

  defp compute_date_range_counts(lat, lng, radius_km, params) do
    # Build base filters matching the current search/category context (but NOT date range)
    base_opts =
      [center_lat: lat, center_lng: lng, radius_km: radius_km]
      |> maybe_add_categories(params)
      |> maybe_add_search(params)

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

  # --- Coordinate resolution ---

  defp resolve_coordinates(%{"city_id" => city_id} = _params) when is_binary(city_id) do
    case Integer.parse(city_id) do
      {id, _} ->
        case Repo.get(City, id) do
          %City{latitude: lat, longitude: lng} when not is_nil(lat) and not is_nil(lng) ->
            {:ok, Decimal.to_float(lat), Decimal.to_float(lng), id}

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
      {:ok, lat, lng, nil}
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
      subtitle: AggregatedMovieGroup.description(group)
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

  defp serialize_item(event) do
    serialize_public_event(event)
  end

  # --- Private helpers ---

  defp find_event_by_slug(slug) do
    case PublicEvents.get_by_slug(slug) do
      %{} = event ->
        # Preload sources (with their source assoc) for ticket URL and attribution
        event = Repo.preload(event, sources: [:source])
        {:public, event}

      nil ->
        case Events.get_event_by_slug(slug) do
          %{} = event -> {:user, event}
          nil -> :not_found
        end
    end
  end

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

  defp serialize_public_event_detail(event) do
    nearby_events =
      PublicEvents.get_nearby_activities_with_fallback(event, display_count: 4, language: "en")

    serialize_public_event(event)
    |> Map.merge(%{
      description: event.display_description,
      ticket_url: get_primary_source_ticket_url(event),
      sources: serialize_sources(event),
      nearby_events: Enum.map(nearby_events, &serialize_public_event/1)
    })
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
    participant_count =
      Events.list_event_participants(event)
      |> length()

    registration_status = Events.get_user_registration_status(event, user)

    serialize_user_event(event)
    |> Map.merge(%{
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
      name: venue.name,
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

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> inspect()
  end
end
