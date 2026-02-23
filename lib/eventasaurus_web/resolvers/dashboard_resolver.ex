defmodule EventasaurusWeb.Resolvers.DashboardResolver do
  @moduledoc """
  Resolver for the dashboardEvents query — exposes the same backend
  functions the web dashboard uses, via GraphQL for the iOS client.
  """

  alias EventasaurusApp.Events

  def dashboard_events(_parent, args, %{context: %{current_user: user}}) do
    time_filter = args[:time_filter] || :upcoming
    ownership_filter = args[:ownership_filter] || :all
    limit = args[:limit] || 50

    events = fetch_events(user, time_filter, ownership_filter, limit)
    filter_counts = Events.get_dashboard_filter_counts(user)

    {:ok,
     %{
       events: events,
       filter_counts: filter_counts
     }}
  end

  # For upcoming/past, use the unified optimized query
  defp fetch_events(user, time_filter, ownership_filter, limit)
       when time_filter in [:upcoming, :past] do
    user
    |> Events.list_unified_events_for_user_optimized(
      time_filter: time_filter,
      ownership_filter: ownership_filter,
      limit: limit
    )
    |> Enum.map(&transform_unified_event/1)
  end

  # For archived, use the deleted events query and transform to match shape
  defp fetch_events(user, :archived, _ownership_filter, _limit) do
    user
    |> Events.list_deleted_events_by_user()
    |> Enum.map(&transform_archived_event/1)
  end

  # Transform a map from list_unified_events_for_user_optimized
  defp transform_unified_event(event) do
    venue = transform_venue(event[:venue])

    %{
      id: to_string(event.id),
      title: event.title,
      slug: event.slug,
      tagline: event[:tagline],
      description: event[:description],
      starts_at: event.start_at,
      ends_at: event.ends_at,
      timezone: event[:timezone],
      status: event.status,
      cover_image_url: event[:cover_image_url],
      is_virtual: event[:is_virtual] || false,
      user_role: event.user_role,
      user_status: event.user_status,
      can_manage: event.can_manage,
      participant_count: event.participant_count,
      venue: venue,
      created_at: to_utc_datetime(event.inserted_at),
      updated_at: to_utc_datetime(event.updated_at)
    }
  end

  # Transform a full Event struct from list_deleted_events_by_user
  defp transform_archived_event(%{} = event) do
    venue =
      case event.venue do
        %{id: id} when not is_nil(id) ->
          %{
            id: to_string(id),
            name: event.venue.name,
            address: event.venue.address,
            latitude: event.venue.latitude,
            longitude: event.venue.longitude
          }

        _ ->
          nil
      end

    %{
      id: to_string(event.id),
      title: event.title,
      slug: event.slug,
      tagline: event.tagline,
      description: event.description,
      starts_at: event.start_at,
      ends_at: event.ends_at,
      timezone: event.timezone,
      status: event.status,
      cover_image_url: event.cover_image_url,
      is_virtual: event.is_virtual || false,
      user_role: "organizer",
      user_status: "confirmed",
      can_manage: true,
      participant_count: 0,
      venue: venue,
      created_at: to_utc_datetime(event.inserted_at),
      updated_at: to_utc_datetime(event.updated_at)
    }
  end

  # Transform venue map from unified query — returns nil when venue id is nil
  defp transform_venue(%{id: nil}), do: nil
  defp transform_venue(nil), do: nil

  defp transform_venue(%{} = v) do
    %{
      id: to_string(v.id),
      name: v.name,
      address: v[:address],
      latitude: v[:latitude],
      longitude: v[:longitude]
    }
  end

  defp to_utc_datetime(%DateTime{} = dt), do: dt
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_utc_datetime(nil), do: nil
end
