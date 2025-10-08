defmodule EventasaurusWeb.Helpers.BreadcrumbBuilder do
  @moduledoc """
  Helper module for building breadcrumb navigation items.

  Constructs breadcrumb hierarchies for different page types:
  - Public events/activities
  - Containers (festivals, conferences, etc.)
  - City-based pages

  ## Breadcrumb Patterns

  ### Activity in a Container
  `Home / Kraków / Festivals / Unsound Kraków 2025 / Concerts / Event Name`

  ### Activity with City (no container)
  `Home / Kraków / Concerts / Event Name`

  ### Activity without City (online/TBD venue)
  `Home / All Activities / Category / Event Name`

  ### Container Page
  `Home / Kraków / Festivals / Unsound Kraków 2025`
  """

  use EventasaurusWeb, :verified_routes

  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventContainer}
  alias EventasaurusApp.Repo
  import Ecto.Query

  @doc """
  Build breadcrumb items for a public event/activity page.

  Returns a list of breadcrumb items with proper hierarchy based on:
  - City (if event has a venue with city)
  - Parent container (if event is part of a festival/conference/etc.)
  - Primary category
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

    # Add category
    items_with_category = add_category_breadcrumb(items_with_container, event)

    # Add current event (no link)
    items_with_category ++ [%{label: event.title, path: nil}]
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
        label: String.capitalize(PublicEventContainer.container_type_plural(container.container_type)),
        path: container_type_index_path(city.slug, container.container_type)
      },
      %{label: container.title, path: nil}
    ]
  end

  # Private helper functions

  defp add_city_breadcrumb(items, %{venue: %{city_ref: %{slug: city_slug, name: city_name}}}, _gettext_backend) do
    items ++ [%{label: city_name, path: ~p"/c/#{city_slug}"}]
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
          items ++ [
            %{
              label: String.capitalize(PublicEventContainer.container_type_plural(container.container_type)),
              path: container_type_index_path(city_slug, container.container_type)
            },
            %{
              label: container.title,
              path: ~p"/c/#{city_slug}/#{PublicEventContainer.container_type_plural(container.container_type)}/#{container.slug}"
            }
          ]
        else
          # If no city, can't build proper container path, skip container breadcrumb
          items
        end
    end
  end

  defp add_category_breadcrumb(items, event) do
    primary_category = get_primary_category(event)

    if primary_category do
      items ++ [%{label: primary_category.name, path: ~p"/activities?#{[category: primary_category.slug]}"}]
    else
      items
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

  defp get_primary_category(%{primary_category_id: nil, categories: categories}) when is_list(categories) do
    # No primary category set, use first category
    List.first(categories)
  end

  defp get_primary_category(%{primary_category_id: cat_id, categories: categories}) when not is_nil(cat_id) do
    Enum.find(categories, &(&1.id == cat_id))
  end

  defp get_primary_category(_), do: nil

  defp container_type_index_path(city_slug, container_type) do
    type_plural = PublicEventContainer.container_type_plural(container_type)
    "/c/#{city_slug}/#{type_plural}"
  end

end
