defmodule EventasaurusWeb.Api.V1.Mobile.EventController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.PublicEvents
  alias EventasaurusApp.Events

  @default_radius_km 50
  @default_per_page 20
  @max_per_page 100

  @doc """
  GET /api/v1/mobile/events/nearby?lat=X&lng=Y&radius=Z

  Returns public events near the given coordinates.
  Radius is in meters (default: 50000 = 50km).
  """
  def nearby(conn, params) do
    with {:ok, lat} <- parse_float(params["lat"], "lat"),
         {:ok, lng} <- parse_float(params["lng"], "lng") do
      radius_km =
        case parse_float(params["radius"], "radius") do
          {:ok, meters} -> meters / 1000
          _ -> @default_radius_km
        end

      page = parse_int(params["page"], 1)
      per_page = min(parse_int(params["per_page"], @default_per_page), @max_per_page)

      events =
        PublicEventsEnhanced.list_events(
          center_lat: lat,
          center_lng: lng,
          radius_km: radius_km,
          page: page,
          page_size: per_page,
          language: "en"
        )

      json(conn, %{
        events: Enum.map(events, &serialize_public_event/1),
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
  GET /api/v1/mobile/events/attending

  Returns events the current user is participating in.
  """
  def attending(conn, _params) do
    user = conn.assigns.user

    events =
      Events.list_events_with_participation(user)
      |> Enum.filter(&upcoming?/1)
      |> Enum.sort_by(& &1.start_at, DateTime)

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

  defp upcoming?(%{start_at: nil}), do: true
  defp upcoming?(%{start_at: start_at}), do: DateTime.compare(start_at, DateTime.utc_now()) == :gt
  defp upcoming?(%{ends_at: nil} = e), do: upcoming_by_start(e)
  defp upcoming?(%{ends_at: ends_at}), do: DateTime.compare(ends_at, DateTime.utc_now()) == :gt

  defp upcoming_by_start(%{start_at: nil}), do: true

  defp upcoming_by_start(%{start_at: start_at}),
    do: DateTime.compare(start_at, DateTime.utc_now()) == :gt

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
