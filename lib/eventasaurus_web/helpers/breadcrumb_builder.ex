defmodule EventasaurusWeb.Helpers.BreadcrumbBuilder do
  @moduledoc """
  Helper module for building breadcrumb navigation items.

  Constructs breadcrumb hierarchies for different page types:
  - Public events/activities
  - Containers (festivals, conferences, etc.)
  - City-based pages
  - Movie pages (city-scoped and generic)
  - Venue pages

  ## Breadcrumb Patterns

  ### Movie Screening (activity page)
  `Home / All Activities / Kraków / Film / Bugonia / Bugonia at Agrafka`

  ### Activity in a Container
  `Home / All Activities / Kraków / Film / Festivals / Unsound Kraków 2025 / Event Name`

  ### Activity with City (no container)
  `Home / All Activities / Kraków / Film / Event Name`

  ### Activity with Metro Area
  `Home / All Activities / Paris / Paris 6 / Film / Event Name`

  ### Activity without City (online/TBD venue)
  `Home / All Activities / Film / Event Name`

  ### Container Page
  `Home / Kraków / Festivals / Unsound Kraków 2025`

  ### Movie Screenings Page (city-scoped)
  `Home / All Activities / Kraków / Film / Movie Title`

  ### Generic Movie Page (not city-scoped)
  `Home / All Activities / Film / Movie Title`

  ### Venue List Page
  `Home / City Name / Venues`

  ### Venue Detail Page
  `Home / All Activities / City Name / Venues / Venue Name`

  ### Venue Detail Page (with Metro Area)
  `Home / All Activities / Paris / Paris 6 / Venues / Venue Name`

  ### Performer/Artist Page
  `Home / All Activities / Artists / Performer Name`
  """

  use EventasaurusWeb, :verified_routes

  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventContainer}
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.AggregationTypeSlug
  alias EventasaurusDiscovery.Categories
  alias EventasaurusApp.Repo
  import Ecto.Query

  # Mapping from aggregation type URL slugs to category slugs
  # This is a semantic mapping between schema.org event types and our category taxonomy
  # The category slugs are validated against the database at runtime
  @aggregation_type_to_category_slug %{
    "social" => "trivia",
    "food" => "food-drink",
    "movies" => "film",
    "music" => "concerts",
    "comedy" => "comedy",
    "theater" => "theatre",
    "sports" => "sports",
    "classes" => "education",
    "festivals" => "festivals"
  }

  @doc """
  Get the category slug for a given aggregation type slug.
  Validates that the category exists in the database before returning.
  Returns nil if no mapping exists or category doesn't exist.

  Results are cached in the process dictionary for the duration of the request.
  """
  @spec get_category_slug_for_aggregation_type(String.t()) :: String.t() | nil
  def get_category_slug_for_aggregation_type(aggregation_type_slug) do
    cache_key = {:breadcrumb_category_slug, aggregation_type_slug}

    # Use {:cached, result} tuple to distinguish "not cached" from "cached as nil"
    case Process.get(cache_key, :not_cached) do
      :not_cached ->
        result = lookup_category_slug(aggregation_type_slug)
        Process.put(cache_key, {:cached, result})
        result

      {:cached, cached_result} ->
        cached_result
    end
  end

  defp lookup_category_slug(aggregation_type_slug) do
    case Map.get(@aggregation_type_to_category_slug, aggregation_type_slug) do
      nil ->
        nil

      category_slug ->
        # Validate the category exists in the database
        case Categories.get_category_by_slug(category_slug) do
          nil -> nil
          _category -> category_slug
        end
    end
  end

  @doc """
  Build breadcrumb items for a public event/activity page.

  Returns a list of breadcrumb items with proper hierarchy based on:
  - All Activities (top-level navigation)
  - City (if event has a venue with city)
  - Metro area (if city is a suburb of a major discovery-enabled city)
  - Category/Activity Type (primary category of the event)
  - Movie (if event is a movie screening, links to movie aggregation page)
  - Parent container (if event is part of a festival/conference/etc.)
  - Event title (current page, no link)

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_event_breadcrumbs(PublicEvent.t(), keyword()) :: [map()]
  def build_event_breadcrumbs(%PublicEvent{} = event, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    base_items = [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: Gettext.gettext(gettext_backend, "All Activities"), path: ~p"/activities"}
    ]

    # Add city if event has venue with city
    items_with_city = add_city_breadcrumb(base_items, event, gettext_backend)

    # Add category/activity type (primary category)
    items_with_category = add_category_breadcrumb(items_with_city, event)

    # Add movie breadcrumb if this is a movie screening
    items_with_movie = add_movie_breadcrumb(items_with_category, event)

    # Add parent container if event is part of one
    items_with_container = add_container_breadcrumb(items_with_movie, event)

    # Add current event (no link) - use display_title if available for localization
    items_with_container ++ [%{label: event.display_title || event.title, path: nil}]
  end

  @doc """
  Build breadcrumb items for a container page (festival, conference, etc.).

  Returns a list of breadcrumb items:
  - Home
  - All Activities
  - City name
  - Container type (plural, e.g., "Festivals")
  - Container title (current page, no link)
  """
  @spec build_container_breadcrumbs(PublicEventContainer.t(), map(), keyword()) :: [map()]
  def build_container_breadcrumbs(%PublicEventContainer{} = container, city, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: Gettext.gettext(gettext_backend, "All Activities"), path: ~p"/activities"},
      %{label: city.name, path: ~p"/c/#{city.slug}"},
      %{
        label:
          String.capitalize(PublicEventContainer.container_type_plural(container.container_type)),
        path: container_type_index_path(city.slug, container.container_type)
      },
      %{label: container.title, path: nil}
    ]
  end

  @doc """
  Build breadcrumb items for container type index pages (e.g., list of all festivals in a city).

  Pattern: `Home / City Name / Festivals`

  ## Parameters
    - city: The city struct with :name and :slug
    - container_type: The container type atom (e.g., :festival, :conference)
    - opts: Options including :gettext_backend

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_container_type_index_breadcrumbs(map(), atom(), keyword()) :: [map()]
  def build_container_type_index_breadcrumbs(city, container_type, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    type_plural = PublicEventContainer.container_type_plural(container_type)

    [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: city.name, path: ~p"/c/#{city.slug}"},
      %{label: String.capitalize(type_plural), path: nil}
    ]
  end

  @doc """
  Build breadcrumb items for aggregated source pages.

  Returns a list of breadcrumb items:
  - Home
  - City name (if city-scoped)
  - Content type (friendly name with link to content type index)
  - Source name with scope indicator (current page, no link)

  Pattern (city scope):
    Home / Kraków / Social / PubQuiz Poland

  Pattern (multi-city scope):
    Home / Social / PubQuiz Poland (All Cities)

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_aggregated_source_breadcrumbs(
          map() | nil,
          String.t(),
          String.t(),
          atom(),
          keyword()
        ) :: [map()]
  def build_aggregated_source_breadcrumbs(city, content_type, source_name, scope, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    # Convert schema.org type to URL slug
    content_type_slug = AggregationTypeSlug.to_slug(content_type)

    # Create friendly display name from slug
    content_type_label = format_content_type_label(content_type_slug)

    # Build content type link to activities page with appropriate filters
    # Maps aggregation types to categories for logical navigation
    content_type_path = build_content_type_path(content_type_slug, city, scope)

    # When viewing all cities, don't include city in breadcrumb path
    # When city-scoped, include the city
    base_items =
      case scope do
        :all_cities ->
          [%{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"}]

        _ ->
          [
            %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
            %{label: city.name, path: ~p"/c/#{city.slug}"}
          ]
      end

    # Add content type with link
    items_with_type =
      base_items ++
        [
          %{label: content_type_label, path: content_type_path}
        ]

    # Add source name with scope context
    final_label =
      case scope do
        :all_cities -> "#{source_name} (All Cities)"
        _ -> source_name
      end

    items_with_type ++ [%{label: final_label, path: nil}]
  end

  @doc """
  Build breadcrumb items for a movie screenings page (city-scoped movie page).

  Pattern: `Home / All Activities / Kraków / Film / Movie Title`

  ## Parameters
    - movie: The movie struct with at least :title
    - city: The city struct with :name and :slug
    - opts: Options including :gettext_backend

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_movie_screenings_breadcrumbs(map(), map(), keyword()) :: [map()]
  def build_movie_screenings_breadcrumbs(movie, city, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    # Get the film category slug (validated against database)
    film_category_slug = get_category_slug_for_aggregation_type("movies") || "film"

    [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: Gettext.gettext(gettext_backend, "All Activities"), path: ~p"/activities"},
      %{label: city.name, path: ~p"/c/#{city.slug}"},
      %{
        label: Gettext.gettext(gettext_backend, "Film"),
        path: ~p"/c/#{city.slug}?category=#{film_category_slug}"
      },
      %{label: movie.title, path: nil}
    ]
  end

  @doc """
  Build breadcrumb items for a generic movie page (not city-scoped).

  Pattern: `Home / All Activities / Film / Movie Title`

  ## Parameters
    - movie: The movie struct with at least :title
    - opts: Options including :gettext_backend

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_generic_movie_breadcrumbs(map(), keyword()) :: [map()]
  def build_generic_movie_breadcrumbs(movie, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    # Get the film category slug (validated against database)
    film_category_slug = get_category_slug_for_aggregation_type("movies") || "film"

    [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: Gettext.gettext(gettext_backend, "All Activities"), path: ~p"/activities"},
      %{
        label: Gettext.gettext(gettext_backend, "Film"),
        path: ~p"/activities?category=#{film_category_slug}"
      },
      %{label: movie.title, path: nil}
    ]
  end

  @doc """
  Build breadcrumb items for a venue list page (city venues index).

  Pattern: `Home / City Name / Venues`

  ## Parameters
    - city: The city struct with :name and :slug
    - opts: Options including :gettext_backend

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_venue_list_breadcrumbs(map(), keyword()) :: [map()]
  def build_venue_list_breadcrumbs(city, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: city.name, path: ~p"/c/#{city.slug}"},
      %{label: Gettext.gettext(gettext_backend, "Venues"), path: nil}
    ]
  end

  @doc """
  Build breadcrumb items for a performer/artist detail page.

  Pattern: `Home / All Activities / Artists / Performer Name`

  ## Parameters
    - performer: The performer struct with :name and :slug
    - opts: Options including :gettext_backend

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_performer_breadcrumbs(map(), keyword()) :: [map()]
  def build_performer_breadcrumbs(performer, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: Gettext.gettext(gettext_backend, "All Activities"), path: ~p"/activities"},
      %{label: Gettext.gettext(gettext_backend, "Artists"), path: ~p"/performers"},
      %{label: performer.name, path: nil}
    ]
  end

  @doc """
  Build breadcrumb items for a venue detail page.

  Pattern: `Home / All Activities / City Name / Venues / Venue Name`

  With metro area hierarchy:
  Pattern: `Home / All Activities / Paris / Paris 6 / Venues / Venue Name`

  ## Parameters
    - venue: The venue struct with :name, :slug, and preloaded :city_ref
    - opts: Options including :gettext_backend

  ## Options
    * `:gettext_backend` - Gettext backend module for translations (defaults to EventasaurusWeb.Gettext)
  """
  @spec build_venue_breadcrumbs(map(), keyword()) :: [map()]
  def build_venue_breadcrumbs(venue, opts \\ []) do
    gettext_backend = Keyword.get(opts, :gettext_backend, EventasaurusWeb.Gettext)

    base_items = [
      %{label: Gettext.gettext(gettext_backend, "Home"), path: ~p"/"},
      %{label: Gettext.gettext(gettext_backend, "All Activities"), path: ~p"/activities"}
    ]

    # Add city breadcrumb with metro area hierarchy if applicable
    items_with_city = add_venue_city_breadcrumb(base_items, venue, gettext_backend)

    # Add Venues breadcrumb (links to city venues page)
    items_with_venues = add_venues_breadcrumb(items_with_city, venue, gettext_backend)

    # Add current venue (no link)
    items_with_venues ++ [%{label: venue.name, path: nil}]
  end

  # Private helper functions

  defp add_venue_city_breadcrumb(
         items,
         %{city_ref: %{id: city_id, slug: city_slug, name: city_name}},
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

  defp add_venue_city_breadcrumb(items, _venue, _gettext_backend) do
    # No city - just return base items
    items
  end

  defp add_venues_breadcrumb(items, %{city_ref: %{slug: city_slug}}, gettext_backend) do
    # Add "Venues" breadcrumb linking to city venues page
    items ++
      [%{label: Gettext.gettext(gettext_backend, "Venues"), path: ~p"/c/#{city_slug}/venues"}]
  end

  defp add_venues_breadcrumb(items, _venue, _gettext_backend) do
    # No city - just return items without Venues breadcrumb
    items
  end

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

  defp add_city_breadcrumb(items, _event, _gettext_backend) do
    # No city - return items unchanged (All Activities already added in base_items)
    items
  end

  defp add_category_breadcrumb(items, %{
         categories: categories,
         primary_category_id: primary_id,
         venue: %{city_ref: %{slug: city_slug}}
       })
       when is_list(categories) and not is_nil(primary_id) do
    # Find the primary category in the preloaded categories list
    case Enum.find(categories, &(&1.id == primary_id)) do
      nil ->
        # Primary category not found in preloaded list, skip category breadcrumb
        items

      category ->
        # Add category breadcrumb linking to city-filtered activities
        items ++ [%{label: category.name, path: ~p"/c/#{city_slug}?category=#{category.slug}"}]
    end
  end

  defp add_category_breadcrumb(items, %{categories: categories, primary_category_id: primary_id})
       when is_list(categories) and not is_nil(primary_id) do
    # No city - fall back to global activities filter
    case Enum.find(categories, &(&1.id == primary_id)) do
      nil ->
        items

      category ->
        items ++ [%{label: category.name, path: ~p"/activities?category=#{category.slug}"}]
    end
  end

  defp add_category_breadcrumb(items, %{
         categories: [category | _],
         venue: %{city_ref: %{slug: city_slug}}
       })
       when not is_nil(category) do
    # No primary_category_id but has categories and city - use the first one with city filter
    items ++ [%{label: category.name, path: ~p"/c/#{city_slug}?category=#{category.slug}"}]
  end

  defp add_category_breadcrumb(items, %{categories: [category | _]}) when not is_nil(category) do
    # No primary_category_id but has categories, no city - use the first one with global filter
    items ++ [%{label: category.name, path: ~p"/activities?category=#{category.slug}"}]
  end

  defp add_category_breadcrumb(items, _event) do
    # No categories available, skip category breadcrumb
    items
  end

  defp add_movie_breadcrumb(items, %{movies: [movie | _], venue: %{city_ref: city}})
       when not is_nil(movie) and not is_nil(city) do
    # Add movie breadcrumb linking to movie aggregation page
    items ++ [%{label: movie.title, path: ~p"/c/#{city.slug}/movies/#{movie.slug}"}]
  end

  defp add_movie_breadcrumb(items, _event) do
    # Not a movie screening or missing city/movie data, skip movie breadcrumb
    items
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

  defp format_content_type_label(slug) when is_binary(slug) do
    # Convert URL slug to display-friendly label
    # "social" => "Social", "food" => "Food", "movies" => "Movies"
    slug
    |> String.capitalize()
  end

  defp build_content_type_path(content_type_slug, city, scope) do
    # Map aggregation type slug to category slug (validated against database)
    category_slug = get_category_slug_for_aggregation_type(content_type_slug)

    case {scope, category_slug} do
      # Multi-city: show all activities (category filtering not available on activities page)
      {:all_cities, _} ->
        ~p"/activities"

      # City-scoped with category mapping: filter city page by category
      {_, category_slug} when not is_nil(category_slug) ->
        ~p"/c/#{city.slug}?category=#{category_slug}"

      # City-scoped without category mapping: just link to city page
      _ ->
        ~p"/c/#{city.slug}"
    end
  end
end
