defmodule EventasaurusWeb.CityLive.Venues do
  @moduledoc """
  LiveView for city venues listing.
  Displays all venues in a city with images, search, filtering, and pagination.
  """
  use EventasaurusWeb, :live_view

  on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler}

  alias EventasaurusApp.Venues
  alias EventasaurusDiscovery.Locations
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.Helpers.LanguageDiscovery
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Components.VenueCards
  alias EventasaurusWeb.Components.Breadcrumbs

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/activities")}

      city ->
        # Get language from connect params (safe nil handling) or default to English
        params = get_connect_params(socket) || %{}
        language = params["locale"] || socket.assigns[:language] || "en"

        # Get dynamically available languages for this city
        available_languages = LanguageDiscovery.get_available_languages_for_city(city_slug)

        # Capture request URI for correct URL generation (ngrok support)
        raw_uri = get_connect_info(socket, :uri)

        request_uri =
          cond do
            match?(%URI{}, raw_uri) -> raw_uri
            is_binary(raw_uri) -> URI.parse(raw_uri)
            true -> nil
          end

        # Build breadcrumb items using BreadcrumbBuilder
        breadcrumb_items = BreadcrumbBuilder.build_venue_list_breadcrumbs(city)

        socket =
          socket
          |> assign(:city, city)
          |> assign(:language, language)
          |> assign(:available_languages, available_languages)
          |> assign(:request_uri, request_uri)
          |> assign(:page_title, "Venues in #{city.name}")
          |> assign(:breadcrumb_items, breadcrumb_items)
          |> assign(:view_mode, "grid")
          |> assign(:show_filters, false)
          |> assign(:loading, false)
          |> assign(:filters, default_filters())
          |> assign(:show_collections, true)
          |> load_venue_stats()
          |> load_venue_collections()

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Hide collections when search or filters are active
    has_active_filters =
      params["search"] != nil ||
        params["has_events"] == "true" ||
        params["sort"] != nil

    socket =
      socket
      |> apply_params_to_filters(params)
      |> assign(:show_collections, !has_active_filters)
      |> fetch_venues()
      |> assign_seo_meta_tags()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    filters =
      socket.assigns.filters
      |> Map.put(:search, search_term)
      |> Map.put(:page, 1)

    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    filters =
      socket.assigns.filters
      |> Map.put(:search, nil)
      |> Map.put(:page, 1)

    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :view_mode, view)}
  end

  @impl true
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, update(socket, :show_filters, &(!&1))}
  end

  @impl true
  def handle_event("filter", %{"has_events" => has_events}, socket) when is_binary(has_events) do
    # Handle quick filter button (phx-value-has_events="true")
    filters =
      socket.assigns.filters
      |> Map.put(:has_events, parse_boolean(has_events))
      |> Map.put(:page, 1)

    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter_params}, socket) do
    # Handle filter form submission
    filters =
      socket.assigns.filters
      |> Map.put(:sort_by, parse_sort(filter_params["sort_by"]))
      |> Map.put(:has_events, parse_boolean(filter_params["has_events"]))
      |> Map.put(:page, 1)

    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    cleared_filters = default_filters()

    socket =
      socket
      |> assign(:filters, cleared_filters)
      |> push_patch(to: build_path(socket, cleared_filters))

    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    filters = Map.put(socket.assigns.filters, :page, page)

    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
  end

  # Private functions

  defp default_filters do
    %{
      search: nil,
      sort_by: :name,
      has_events: false,
      page: 1,
      page_size: 30
    }
  end

  defp apply_params_to_filters(socket, params) do
    filters = %{
      socket.assigns.filters
      | search: params["search"] || socket.assigns.filters.search,
        page: parse_integer(params["page"]) || socket.assigns.filters.page,
        sort_by: parse_sort(params["sort"]) || socket.assigns.filters.sort_by,
        has_events: parse_boolean(params["has_events"]) || socket.assigns.filters.has_events
    }

    assign(socket, :filters, filters)
  end

  defp fetch_venues(socket) do
    city = socket.assigns.city
    filters = socket.assigns.filters

    venues = Venues.list_city_venues(city.id, Enum.into(filters, []))

    assign(socket, :venues, venues)
  end

  defp load_venue_stats(socket) do
    city = socket.assigns.city

    total_venues = Venues.count_city_venues(city.id)
    active_venues = Venues.count_active_city_venues(city.id)

    socket
    |> assign(:total_venues, total_venues)
    |> assign(:active_venues, active_venues)
  end

  defp load_venue_collections(socket) do
    city = socket.assigns.city
    collections = Venues.get_venue_collections(city.id, 6)

    assign(socket, :collections, collections)
  end

  defp assign_seo_meta_tags(socket) do
    city = socket.assigns.city
    total_venues = socket.assigns.total_venues
    request_uri = socket.assigns.request_uri

    title = "Venues in #{city.name} | Wombie - Event Spaces & Cultural Locations"

    description =
      "Explore #{total_venues} venues in #{city.name}, Poland. Find theaters, concert halls, museums, and event spaces. Discover where events happen in #{city.name}."

    canonical_path = ~p"/c/#{city.slug}/venues"

    # JSON-LD ItemList schema (must be JSON-encoded string)
    json_ld =
      %{
        "@context" => "https://schema.org",
        "@type" => "ItemList",
        "name" => "Venues in #{city.name}",
        "description" => "Event venues and cultural spaces in #{city.name}, Poland",
        "numberOfItems" => total_venues,
        "itemListElement" =>
          socket.assigns.venues
          |> Enum.with_index(1)
          |> Enum.map(fn {venue_data, position} ->
            %{
              "@type" => "ListItem",
              "position" => position,
              "item" => %{
                "@type" => "Place",
                "name" => venue_data.venue.name,
                "address" => venue_data.venue.address,
                "url" => EventasaurusWeb.UrlHelper.build_url(~p"/venues/#{venue_data.venue.slug}")
              }
            }
          end)
      }
      |> Jason.encode!()

    SEOHelpers.assign_meta_tags(socket,
      title: title,
      description: description,
      type: "website",
      canonical_path: canonical_path,
      json_ld: json_ld,
      request_uri: request_uri
    )
  end

  defp build_path(socket, filters) do
    city = socket.assigns.city
    query_params = []

    query_params =
      if filters.search, do: [{"search", filters.search} | query_params], else: query_params

    query_params =
      if filters.page > 1, do: [{"page", filters.page} | query_params], else: query_params

    query_params =
      if filters.sort_by != :name,
        do: [{"sort", Atom.to_string(filters.sort_by)} | query_params],
        else: query_params

    query_params =
      if filters.has_events,
        do: [{"has_events", "true"} | query_params],
        else: query_params

    ~p"/c/#{city.slug}/venues?#{query_params}"
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_sort(nil), do: :name

  defp parse_sort(value) when is_binary(value) do
    case value do
      "name" -> :name
      "events_count" -> :events_count
      "id" -> :id
      _ -> :name
    end
  end

  defp parse_sort(value) when is_atom(value), do: value

  defp parse_boolean(nil), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_), do: false
end
