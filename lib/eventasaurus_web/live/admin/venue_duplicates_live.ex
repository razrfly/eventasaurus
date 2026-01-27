defmodule EventasaurusWeb.Admin.VenueDuplicatesLive do
  @moduledoc """
  Admin page for viewing cities with potential venue duplicates.

  This is a navigation page that:
  - Shows only cities that have ≥1 potential duplicate pair
  - Uses strict criteria: <100m distance AND (>60% similarity OR substring match)
  - Links to city health pages for actual duplicate management

  Merge functionality lives on the city health page, not here.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Venues.VenueDeduplication

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Venue Duplicates")
      |> assign(:loading, true)
      |> assign(:cities_with_duplicates, [])
      |> assign(:total_duplicate_count, 0)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:last_loaded_at, nil)

    # Load data asynchronously after mount
    if connected?(socket) do
      send(self(), :load_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_data, socket) do
    cities = VenueDeduplication.get_cities_with_duplicates()
    total = Enum.sum(Enum.map(cities, & &1.duplicate_count))

    {:noreply,
     socket
     |> assign(:cities_with_duplicates, cities)
     |> assign(:total_duplicate_count, total)
     |> assign(:last_loaded_at, DateTime.utc_now())
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    send(self(), :load_data)
    {:noreply, assign(socket, :loading, true)}
  end

  @impl true
  def handle_event("search_venues", %{"value" => query}, socket) do
    do_search(query, socket)
  end

  @impl true
  def handle_event("search_venues", %{"query" => query}, socket) do
    do_search(query, socket)
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  defp do_search(query, socket) do
    results =
      if String.length(query) >= 2 do
        VenueDeduplication.search_venues(query, limit: 10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end
end
