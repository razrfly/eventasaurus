defmodule EventasaurusWeb.Admin.VenueDuplicatesLive do
  @moduledoc """
  Admin page for detecting and merging duplicate venues.

  Features:
  - Display potential duplicate venue groups
  - Show similarity scores and distance metrics
  - Merge duplicate venues with proper event/activity reassignment
  - Async loading to handle large datasets
  """
  use EventasaurusWeb, :live_view

  import Ecto.Query

  alias EventasaurusApp.Venues
  alias EventasaurusApp.Repo

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Venue Duplicates")
      |> assign(:duplicate_groups, nil)
      |> assign(:loading, false)

    # Load duplicates asynchronously after mount
    if connected?(socket) do
      send(self(), :load_duplicates)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_duplicates, socket) do
    # Load duplicate groups with distance and similarity data
    duplicate_groups = Venues.find_duplicate_groups(200, 0.6)

    # Enrich venues with event counts
    enriched_groups =
      Enum.map(duplicate_groups, fn group ->
        venues_with_counts =
          Enum.map(group.venues, fn venue ->
            event_count = count_events_for_venue(venue.id)
            Map.put(venue, :event_count, event_count)
          end)

        Map.put(group, :venues, venues_with_counts)
      end)

    {:noreply,
     socket
     |> assign(:duplicate_groups, enriched_groups)
     |> assign(:loading, false)
     |> put_flash(:info, "Duplicate detection complete")}
  end

  @impl true
  def handle_event("detect_duplicates", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)

    send(self(), :load_duplicates)

    {:noreply, socket}
  end

  @impl true
  def handle_event("merge_venues", params, socket) do
    primary_id = String.to_integer(params["primary_id"])
    all_venue_ids = String.split(params["all_ids"], ",") |> Enum.map(&String.to_integer/1)
    # Filter out the primary venue from the duplicate list
    duplicate_ids = Enum.reject(all_venue_ids, &(&1 == primary_id))

    # Count events BEFORE merge (while duplicate venues still exist)
    events_count = count_events_for_venues(duplicate_ids)

    case Venues.merge_venues(primary_id, duplicate_ids) do
      {:ok, _updated_venue} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Successfully merged #{length(duplicate_ids)} duplicate venues into venue ##{primary_id}. Moved #{events_count} events."
          )

        # Reload duplicates
        send(self(), :load_duplicates)

        {:noreply, socket}

      {:error, reason} ->
        error_message =
          case reason do
            "Primary venue not found" -> "Primary venue not found"
            "Some duplicate venues not found" -> "Some duplicate venues not found"
            _ -> "Failed to merge venues: #{inspect(reason)}"
          end

        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  # Private functions

  defp count_events_for_venue(venue_id) do
    Repo.replica().aggregate(
      from(e in EventasaurusApp.Events.Event, where: e.venue_id == ^venue_id),
      :count,
      :id
    ) +
      Repo.replica().aggregate(
        from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
          where: pe.venue_id == ^venue_id
        ),
        :count,
        :id
      )
  end

  defp count_events_for_venues(venue_ids) do
    Repo.replica().aggregate(
      from(e in EventasaurusApp.Events.Event, where: e.venue_id in ^venue_ids),
      :count,
      :id
    ) +
      Repo.replica().aggregate(
        from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
          where: pe.venue_id in ^venue_ids
        ),
        :count,
        :id
      )
  end
end
