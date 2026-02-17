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
  alias EventasaurusWeb.Live.Helpers.EventFilters

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
    with {:ok, lat, lng} <- resolve_coordinates(params) do
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
          language: "en"
        ]
        |> maybe_add_categories(params)
        |> maybe_add_search(params)
        |> maybe_add_date_range(params)
        |> maybe_add_sort(params)

      # Fetch raw events then aggregate (same pipeline the web uses).
      # Note: aggregate_events uses is_map_key guards, so opts must be a map.
      raw_events = PublicEventsEnhanced.list_events(opts)
      items = PublicEventsEnhanced.aggregate_events(raw_events, %{ignore_city_in_aggregation: true})

      json(conn, %{
        events: Enum.map(items, &serialize_item/1),
        meta: %{page: page, per_page: per_page}
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
      meta: %{total: length(events)}
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
        json(conn, %{event: serialize_public_event_detail(event)})

      {:user, event} ->
        json(conn, %{event: serialize_user_event_detail(event, user)})

      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Event not found"})
    end
  end

  # --- Coordinate resolution ---

  defp resolve_coordinates(%{"city_id" => city_id} = _params) when is_binary(city_id) do
    case Integer.parse(city_id) do
      {id, _} ->
        case Repo.get(City, id) do
          %City{latitude: lat, longitude: lng} when not is_nil(lat) and not is_nil(lng) ->
            {:ok, Decimal.to_float(lat), Decimal.to_float(lng)}

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
      {:ok, lat, lng}
    end
  end

  # --- Filter builders ---

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
      cover_image_url: group.movie_backdrop_url || group.movie_poster_url,
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
      cover_image_url: group.cover_image_url,
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
      cover_image_url: group.cover_image_url,
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
      %{} = event -> {:public, event}
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
      cover_image_url: event.cover_image_url,
      type: "public",
      venue: serialize_venue(event.venue)
    }
  end

  defp serialize_public_event_detail(event) do
    serialize_public_event(event)
    |> Map.merge(%{
      description: event.display_description,
      categories: Enum.map(event.categories || [], & &1.name)
    })
  end

  defp serialize_user_event(event) do
    %{
      slug: event.slug,
      title: event.title,
      starts_at: event.start_at,
      ends_at: event.ends_at,
      cover_image_url: event.cover_image_url,
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

  defp serialize_venue(nil), do: nil

  defp serialize_venue(venue) do
    %{
      name: venue.name,
      address: venue.address,
      lat: venue.latitude,
      lng: venue.longitude
    }
  end

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
end
