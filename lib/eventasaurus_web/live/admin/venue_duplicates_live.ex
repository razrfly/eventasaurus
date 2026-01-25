defmodule EventasaurusWeb.Admin.VenueDuplicatesLive do
  @moduledoc """
  Admin page for detecting and merging duplicate venues.

  Features:
  - Display potential duplicate venue groups
  - Search for any venue to find its duplicates
  - Side-by-side comparison of venue pairs
  - Granular pair merge with full audit trail
  - Mark pairs as "not duplicates" to exclude from future detection
  - Show merge history for accountability
  """
  use EventasaurusWeb, :live_view

  import Ecto.Query

  alias EventasaurusApp.Venues
  alias EventasaurusApp.Venues.VenueDeduplication
  alias EventasaurusApp.Repo

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "Venue Duplicates")
      |> assign(:duplicate_groups, nil)
      |> assign(:loading, false)
      # Search state
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:selected_venue, nil)
      |> assign(:venue_duplicates, nil)
      # Comparison state
      |> assign(:comparison_mode, false)
      |> assign(:venue_a, nil)
      |> assign(:venue_b, nil)
      # City filter
      |> assign(:cities, load_cities())
      |> assign(:selected_city_id, nil)
      # Recent merges
      |> assign(:recent_merges, [])
      |> assign(:show_merge_history, false)
      # Current user for audit
      |> assign(:current_user_id, get_user_id(session))

    # Load duplicates and recent merges asynchronously after mount
    if connected?(socket) do
      send(self(), :load_duplicates)
      send(self(), :load_recent_merges)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Handle venue_id URL parameter to pre-select a venue
    socket =
      case params do
        %{"venue_id" => venue_id_str} ->
          if connected?(socket) do
            case Integer.parse(venue_id_str) do
              {venue_id, ""} ->
                # Find duplicates for this venue (similar to select_venue handler)
                case VenueDeduplication.find_duplicates_for_venue(venue_id,
                       distance_meters: 2000,
                       min_similarity: 0.3,
                       limit: 20
                     ) do
                  {:ok, duplicates} ->
                    case Repo.get(Venues.Venue, venue_id) do
                      nil ->
                        put_flash(socket, :error, "Venue not found")

                      venue ->
                        venue = Repo.preload(venue, :city)
                        venue = Map.put(venue, :event_count, count_events_for_venue(venue.id))

                        socket
                        |> assign(:selected_venue, venue)
                        |> assign(:venue_duplicates, duplicates)
                    end

                  {:error, _reason} ->
                    put_flash(socket, :error, "Venue not found")
                end

              _ ->
                put_flash(socket, :error, "Invalid venue ID")
            end
          else
            socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_duplicates, socket) do
    # Load duplicate groups with distance and similarity data
    duplicate_groups =
      Venues.find_duplicate_groups(distance: 1000, min_similarity: 0.5, row_limit: 200)

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
     |> put_flash(:info, "Duplicate detection complete. Found #{length(enriched_groups)} groups.")}
  end

  @impl true
  def handle_info(:load_recent_merges, socket) do
    recent_merges = VenueDeduplication.list_recent_merges(limit: 10)
    {:noreply, assign(socket, :recent_merges, recent_merges)}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("detect_duplicates", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)

    send(self(), :load_duplicates)

    {:noreply, socket}
  end

  # Search handlers
  @impl true
  def handle_event("search_venues", %{"value" => query}, socket) do
    # Handle raw input phx-change (sends "value" key)
    do_search_venues(query, socket)
  end

  @impl true
  def handle_event("search_venues", %{"query" => query}, socket) do
    # Handle form-wrapped input (sends "query" key based on name attribute)
    do_search_venues(query, socket)
  end

  @impl true
  def handle_event("filter_by_city", %{"city_id" => city_id}, socket) do
    do_filter_by_city(city_id, socket)
  end

  @impl true
  def handle_event("filter_by_city", %{"value" => city_id}, socket) do
    # Handle raw select phx-change (sends "value" key)
    do_filter_by_city(city_id, socket)
  end

  @impl true
  def handle_event("select_venue", %{"venue_id" => venue_id}, socket) do
    venue_id = String.to_integer(venue_id)

    # Find duplicates for this venue
    case VenueDeduplication.find_duplicates_for_venue(venue_id,
           distance_meters: 2000,
           min_similarity: 0.3,
           limit: 20
         ) do
      {:ok, duplicates} ->
        case Repo.get(Venues.Venue, venue_id) do
          nil ->
            {:noreply, put_flash(socket, :error, "Venue not found")}

          venue ->
            venue = Repo.preload(venue, :city)
            venue = Map.put(venue, :event_count, count_events_for_venue(venue.id))

            {:noreply,
             socket
             |> assign(:selected_venue, venue)
             |> assign(:venue_duplicates, duplicates)
             |> assign(:search_results, [])
             |> assign(:search_query, "")}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Venue not found")}
    end
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_venue, nil)
     |> assign(:venue_duplicates, nil)
     |> assign(:comparison_mode, false)
     |> assign(:venue_a, nil)
     |> assign(:venue_b, nil)}
  end

  # Comparison handlers
  @impl true
  def handle_event(
        "compare_venues",
        %{"venue_a_id" => venue_a_id, "venue_b_id" => venue_b_id},
        socket
      ) do
    with venue_a when not is_nil(venue_a) <-
           Repo.get(Venues.Venue, String.to_integer(venue_a_id)),
         venue_b when not is_nil(venue_b) <- Repo.get(Venues.Venue, String.to_integer(venue_b_id)) do
      venue_a =
        venue_a
        |> Repo.preload(:city)
        |> Map.put(:event_count, count_events_for_venue(venue_a.id))

      venue_b =
        venue_b
        |> Repo.preload(:city)
        |> Map.put(:event_count, count_events_for_venue(venue_b.id))

      {:noreply,
       socket
       |> assign(:comparison_mode, true)
       |> assign(:venue_a, venue_a)
       |> assign(:venue_b, venue_b)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "One or both venues no longer exist")}
    end
  end

  @impl true
  def handle_event("close_comparison", _params, socket) do
    {:noreply,
     socket
     |> assign(:comparison_mode, false)
     |> assign(:venue_a, nil)
     |> assign(:venue_b, nil)}
  end

  # Merge handlers (granular pair merge with audit)
  @impl true
  def handle_event("merge_pair", %{"source_id" => source_id, "target_id" => target_id}, socket) do
    source_id = String.to_integer(source_id)
    target_id = String.to_integer(target_id)

    # Get similarity/distance if we have them
    similarity_score =
      case socket.assigns.venue_duplicates do
        nil ->
          nil

        dups ->
          Enum.find_value(dups, fn d -> if d.venue.id == source_id, do: d.similarity_score end)
      end

    distance_meters =
      case socket.assigns.venue_duplicates do
        nil ->
          nil

        dups ->
          Enum.find_value(dups, fn d -> if d.venue.id == source_id, do: d.distance_meters end)
      end

    opts = [
      user_id: socket.assigns.current_user_id,
      reason: "manual_admin_merge",
      similarity_score: similarity_score,
      distance_meters: distance_meters
    ]

    case VenueDeduplication.merge_venues(source_id, target_id, opts) do
      {:ok, %{target_venue: target, audit: audit}} ->
        # Reload recent merges
        send(self(), :load_recent_merges)

        # Clear comparison mode and refresh
        socket =
          socket
          |> put_flash(
            :info,
            "Successfully merged venue into #{target.name}. #{audit.events_reassigned} events and #{audit.public_events_reassigned} public events transferred."
          )
          |> assign(:comparison_mode, false)
          |> assign(:venue_a, nil)
          |> assign(:venue_b, nil)
          |> assign(:selected_venue, nil)
          |> assign(:venue_duplicates, nil)

        # Reload duplicate groups
        send(self(), :load_duplicates)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to merge venues: #{inspect(reason)}")}
    end
  end

  # Legacy group merge (for backwards compatibility with existing UI)
  @impl true
  def handle_event("merge_venues", params, socket) do
    primary_id = String.to_integer(params["primary_id"])
    all_venue_ids = String.split(params["all_ids"], ",") |> Enum.map(&String.to_integer/1)
    duplicate_ids = Enum.reject(all_venue_ids, &(&1 == primary_id))

    # Merge each duplicate into the primary
    results =
      Enum.map(duplicate_ids, fn source_id ->
        VenueDeduplication.merge_venues(source_id, primary_id,
          user_id: socket.assigns.current_user_id,
          reason: "manual_group_merge"
        )
      end)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &match?({:error, _}, &1))

    socket =
      if failures > 0 do
        put_flash(socket, :warning, "Merged #{successes} venues, #{failures} failed")
      else
        put_flash(
          socket,
          :info,
          "Successfully merged #{successes} venues into venue ##{primary_id}"
        )
      end

    # Reload
    send(self(), :load_duplicates)
    send(self(), :load_recent_merges)

    {:noreply, socket}
  end

  # Exclusion handlers
  @impl true
  def handle_event("exclude_pair", %{"venue_id_1" => id1, "venue_id_2" => id2}, socket) do
    id1 = String.to_integer(id1)
    id2 = String.to_integer(id2)

    case VenueDeduplication.exclude_pair(id1, id2,
           user_id: socket.assigns.current_user_id,
           reason: "marked_not_duplicate_by_admin"
         ) do
      {:ok, _exclusion} ->
        # Refresh the duplicate list for the selected venue
        socket =
          if socket.assigns.selected_venue do
            case VenueDeduplication.find_duplicates_for_venue(socket.assigns.selected_venue.id,
                   distance_meters: 2000,
                   min_similarity: 0.3,
                   limit: 20
                 ) do
              {:ok, duplicates} ->
                assign(socket, :venue_duplicates, duplicates)

              _ ->
                socket
            end
          else
            socket
          end

        {:noreply,
         socket
         |> put_flash(:info, "Marked as not duplicates. They won't appear as duplicates again.")
         |> assign(:comparison_mode, false)
         |> assign(:venue_a, nil)
         |> assign(:venue_b, nil)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to exclude pair: #{inspect(reason)}")}
    end
  end

  # History toggle
  @impl true
  def handle_event("toggle_merge_history", _params, socket) do
    {:noreply, assign(socket, :show_merge_history, !socket.assigns.show_merge_history)}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_search_venues(query, socket) do
    results =
      if String.length(query) >= 2 do
        opts =
          if socket.assigns.selected_city_id do
            [city_id: socket.assigns.selected_city_id, limit: 20]
          else
            [limit: 20]
          end

        VenueDeduplication.search_venues(query, opts)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  defp do_filter_by_city(city_id, socket) do
    city_id =
      case city_id do
        "" ->
          nil

        nil ->
          nil

        id when is_integer(id) ->
          id

        id when is_binary(id) ->
          case Integer.parse(id) do
            {int, ""} -> int
            _ -> nil
          end
      end

    # Re-run search with city filter if there's a query
    results =
      if String.length(socket.assigns.search_query) >= 2 do
        opts =
          if city_id do
            [city_id: city_id, limit: 20]
          else
            [limit: 20]
          end

        VenueDeduplication.search_venues(socket.assigns.search_query, opts)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_city_id, city_id)
     |> assign(:search_results, results)}
  end

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

  defp load_cities do
    from(c in EventasaurusDiscovery.Locations.City,
      order_by: [asc: c.name],
      select: {c.name, c.id}
    )
    |> Repo.all()
  end

  defp get_user_id(session) do
    case session do
      %{"current_user_id" => id} -> id
      _ -> nil
    end
  end
end
