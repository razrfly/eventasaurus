defmodule EventasaurusWeb.Helpers.BreadcrumbBuilder do
  @moduledoc """
  Helper module for building breadcrumb navigation items.

  Constructs breadcrumb hierarchies for different page types:
  - Public events/activities
  - Containers (festivals, conferences, etc.)
  - City-based pages

  ## Breadcrumb Patterns

  ### Activity in a Container
  `Home / Kraków / Festivals / Unsound Kraków 2025 / Event Name`

  ### Activity with City (no container)
  `Home / Kraków / Event Name`

  ### Activity with Metro Area
  `Home / Paris / Paris 6 / Event Name`

  ### Activity without City (online/TBD venue)
  `Home / All Activities / Event Name`

  ### Container Page
  `Home / Kraków / Festivals / Unsound Kraków 2025`
  """

  use EventasaurusWeb, :verified_routes

  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventContainer}
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Repo
  import Ecto.Query

  @doc """
  Build breadcrumb items for a public event/activity page.

  Returns a list of breadcrumb items with proper hierarchy based on:
  - City (if event has a venue with city)
  - Metro area (if city is a suburb of a major discovery-enabled city)
  - Parent container (if event is part of a festival/conference/etc.)
  - Event title (current page, no link)

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  def build_event_breadcrumbs(%PublicEvent{} = event, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    base_items = [%{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"}]

    # Add city if event has venue with city
    items_with_city = add_city_breadcrumb(base_items, event, gettext_backend)

    # Add parent container if event is part of one
    items_with_container = add_container_breadcrumb(items_with_city, event)

    # Add current event (no link) - use display_title if available for localization
    items_with_container ++ [%{label: event.display_title || event.title, path: nil}]
  end

  @doc """
  Build breadcrumb items for a container page (festival, conference, etc.).

  Returns a list of breadcrumb items:
  - Home
  - City name
  - Container type (plural, e.g., "Festivals")
  - Container title (current page, no link)
  """
  def build_container_breadcrumbs(%PublicEventContainer{} = container, city, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: city.name, path: ~p"/c/#{city.slug}"},
      %{
        label:
          String.capitalize(PublicEventContainer.container_type_plural(container.container_type)),
        path: container_type_index_path(city.slug, container.container_type)
      },
      %{label: container.title, path: nil}
    ]
  end

  # Private helper functions

  defp add_city_breadcrumb(
         items,
         %{venue: %{city_ref: %{id: city_id, slug: city_slug, name: city_name}}},
         _gettext_backend
       ) do
    # Check if this city is part of a metro area (e.g., Paris 6 is part of Paris)
    case find_metro_primary_city(city_id) do
      nil ->
        # Standalone city or is itself the primary
        items ++ [%{label: city_name, path: ~p"/c/#{city_slug}"}]

      primary_city ->
        # City is part of a metro area - show hierarchy
        items ++
          [
            %{label: primary_city.name, path: ~p"/c/#{primary_city.slug}"},
            %{label: city_name, path: ~p"/c/#{city_slug}"}
          ]
    end
  end

  defp add_city_breadcrumb(items, _event, gettext_backend) do
    # No city - add "All Activities" instead
    items ++ [%{label: Gettext.gettext(gettext_backend, "All Activities"), path: ~p"/activities"}]
  end

  defp add_container_breadcrumb(items, event) do
    case get_parent_container(event) do
      nil ->
        items

      container ->
        # Get city slug from the event (needed for container paths)
        city_slug = get_in(event, [Access.key(:venue), Access.key(:city_ref), Access.key(:slug)])

        if city_slug do
          items ++
            [
              %{
                label:
                  String.capitalize(
                    PublicEventContainer.container_type_plural(container.container_type)
                  ),
                path: container_type_index_path(city_slug, container.container_type)
              },
              %{
                label: container.title,
                path:
                  ~p"/c/#{city_slug}/#{PublicEventContainer.container_type_plural(container.container_type)}/#{container.slug}"
              }
            ]
        else
          # If no city, can't build proper container path, skip container breadcrumb
          items
        end
    end
  end

  defp get_parent_container(%{id: event_id}) do
    # Query for the highest confidence container membership
    query =
      from(m in "public_event_container_memberships",
        where: m.event_id == ^event_id,
        order_by: [desc: m.confidence_score],
        limit: 1,
        select: m.container_id
      )

    case Repo.one(query) do
      nil ->
        nil

      container_id ->
        Repo.get(PublicEventContainer, container_id)
    end
  end

  defp container_type_index_path(city_slug, container_type) do
    type_plural = PublicEventContainer.container_type_plural(container_type)
    "/c/#{city_slug}/#{type_plural}"
  end

  defp find_metro_primary_city(city_id) do
    # Get the current city with coordinates
    current_city =
      Repo.one(
        from(c in City,
          where: c.id == ^city_id,
          select: %{
            id: c.id,
            name: c.name,
            slug: c.slug,
            latitude: c.latitude,
            longitude: c.longitude,
            country_id: c.country_id,
            discovery_enabled: c.discovery_enabled
          }
        )
      )

    # If the current city itself is discovery-enabled, it's the primary - don't add parent
    if current_city && current_city.discovery_enabled do
      nil
    else
      # Look for a nearby discovery-enabled city (the main city we promote)
      find_nearby_discovery_city(current_city)
    end
  end

  defp find_nearby_discovery_city(city) when is_nil(city), do: nil

  defp find_nearby_discovery_city(city) do
    if city.latitude && city.longitude do
      # Calculate bounding box for 50km radius (larger radius to catch main cities)
      lat = Decimal.to_float(city.latitude)
      lng = Decimal.to_float(city.longitude)

      lat_delta = 50.0 / 111.0
      lng_delta = 50.0 / (111.0 * :math.cos(lat * :math.pi() / 180.0))

      min_lat = lat - lat_delta
      max_lat = lat + lat_delta
      min_lng = lng - lng_delta
      max_lng = lng + lng_delta

      # Find the nearest discovery-enabled city
      Repo.one(
        from(c in City,
          where: c.country_id == ^city.country_id,
          where: c.discovery_enabled == true,
          where: not is_nil(c.latitude) and not is_nil(c.longitude),
          where: c.latitude >= ^min_lat and c.latitude <= ^max_lat,
          where: c.longitude >= ^min_lng and c.longitude <= ^max_lng,
          # Order by distance (approximation using lat/lng delta)
          order_by: [
            asc:
              fragment(
                "ABS(? - ?) + ABS(? - ?)",
                c.latitude,
                ^city.latitude,
                c.longitude,
                ^city.longitude
              )
          ],
          limit: 1,
          select: %{id: c.id, name: c.name, slug: c.slug}
        )
      )
    else
      nil
    end
  end

end
