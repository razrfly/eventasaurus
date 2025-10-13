defmodule EventasaurusWeb.JsonLd.BreadcrumbListSchema do
  @moduledoc """
  Generates JSON-LD structured data for breadcrumb navigation according to schema.org.

  This module creates properly formatted breadcrumb structured data
  for better SEO and Google search result appearance.

  ## Schema.org BreadcrumbList
  - Schema.org BreadcrumbList: https://schema.org/BreadcrumbList
  - Google Breadcrumbs: https://developers.google.com/search/docs/appearance/structured-data/breadcrumb

  ## Breadcrumb Items
  Each breadcrumb is represented as a ListItem with:
  - position: Integer position in the list (1-indexed)
  - name: Display name of the page
  - item: Full URL to the page
  """

  @doc """
  Generates JSON-LD structured data for breadcrumb navigation.

  ## Parameters
    - breadcrumbs: List of maps with :name and :url keys
      Example: [
        %{name: "Home", url: "https://example.com"},
        %{name: "Events", url: "https://example.com/events"},
        %{name: "Event Name", url: "https://example.com/events/event-slug"}
      ]

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> breadcrumbs = [
      ...>   %{name: "Home", url: "https://wombie.com"},
      ...>   %{name: "Kraków", url: "https://wombie.com/cities/krakow"},
      ...>   %{name: "Arctic Monkeys", url: "https://wombie.com/activities/arctic-monkeys-krakow"}
      ...> ]
      iex> EventasaurusWeb.JsonLd.BreadcrumbListSchema.generate(breadcrumbs)
      "{\"@context\":\"https://schema.org\",\"@type\":\"BreadcrumbList\",...}"
  """
  def generate(breadcrumbs) when is_list(breadcrumbs) do
    breadcrumbs
    |> build_breadcrumb_schema()
    |> Jason.encode!()
  end

  @doc """
  Builds the breadcrumb schema map (without JSON encoding).
  Useful for testing or combining with other schemas.
  """
  def build_breadcrumb_schema(breadcrumbs) when is_list(breadcrumbs) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => build_breadcrumb_items(breadcrumbs)
    }
  end

  # Build the list of breadcrumb items
  defp build_breadcrumb_items(breadcrumbs) do
    breadcrumbs
    |> Enum.with_index(1)
    |> Enum.map(fn {breadcrumb, position} ->
      %{
        "@type" => "ListItem",
        "position" => position,
        "name" => breadcrumb.name,
        "item" => breadcrumb.url
      }
    end)
  end

  @doc """
  Converts BreadcrumbBuilder items to JSON-LD structured data.

  This function adapts the output from `EventasaurusWeb.Helpers.BreadcrumbBuilder`
  to the format needed for Google breadcrumb rich results. It ensures the visual
  breadcrumbs and JSON-LD breadcrumbs always match.

  ## Parameters
    - items: List of breadcrumb items from BreadcrumbBuilder with :label and :path keys
      Example: [
        %{label: "Home", path: "/"},
        %{label: "Kraków", path: "/c/krakow"},
        %{label: "Festivals", path: "/c/krakow/festivals"},
        %{label: "Unsound Kraków 2025", path: "/c/krakow/festivals/unsound-krakow-2025-958"},
        %{label: "Concerts", path: "/activities?category=concerts"},
        %{label: "Event Name", path: nil}  # Current page
      ]
    - current_url: Full URL of the current page (used when path is nil)
    - base_url: Base URL of the application (e.g., "https://wombie.com")

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> items = [
      ...>   %{label: "Home", path: "/"},
      ...>   %{label: "Kraków", path: "/c/krakow"},
      ...>   %{label: "Event Name", path: nil}
      ...> ]
      iex> EventasaurusWeb.JsonLd.BreadcrumbListSchema.from_breadcrumb_builder_items(
      ...>   items,
      ...>   "https://wombie.com/activities/event-slug",
      ...>   "https://wombie.com"
      ...> )
      "{\"@context\":\"https://schema.org\",\"@type\":\"BreadcrumbList\",...}"
  """
  def from_breadcrumb_builder_items(items, current_url, base_url) when is_list(items) do
    items
    |> Enum.map(fn item ->
      url = case item.path do
        nil -> current_url  # Current page - use the actual page URL
        path -> build_absolute_url(path, base_url)
      end

      %{name: item.label, url: url}
    end)
    |> generate()
  end

  # Converts relative paths to absolute URLs
  defp build_absolute_url(path, base_url) do
    cond do
      # Already an absolute URL
      String.starts_with?(path, "http://") or String.starts_with?(path, "https://") ->
        path

      # Relative path - ensure it starts with /
      true ->
        normalized_path = if String.starts_with?(path, "/"), do: path, else: "/#{path}"
        "#{base_url}#{normalized_path}"
    end
  end

  @doc """
  Helper function to build breadcrumbs for an event page.

  @deprecated Use `from_breadcrumb_builder_items/3` with `EventasaurusWeb.Helpers.BreadcrumbBuilder.build_event_breadcrumbs/2` instead.
  This ensures visual breadcrumbs and JSON-LD breadcrumbs stay in sync.

  ## Parameters
    - event: PublicEvent struct with preloaded :venue (with :city_ref)
    - base_url: Base URL of the application (e.g., "https://wombie.com")

  ## Returns
    - List of breadcrumb maps suitable for generate/1
  """
  def build_event_breadcrumbs(event, base_url) do
    breadcrumbs = [
      %{name: "Home", url: base_url}
    ]

    breadcrumbs =
      if event.venue && event.venue.city_ref do
        city = event.venue.city_ref
        breadcrumbs ++
          [%{name: city.name, url: "#{base_url}/cities/#{city.slug}"}]
      else
        breadcrumbs
      end

    breadcrumbs ++
      [%{name: event.title, url: "#{base_url}/activities/#{event.slug}"}]
  end

  @doc """
  Helper function to build breadcrumbs for a city page.

  @deprecated Use `from_breadcrumb_builder_items/3` with appropriate BreadcrumbBuilder function instead.
  This ensures visual breadcrumbs and JSON-LD breadcrumbs stay in sync.

  ## Parameters
    - city: City struct
    - base_url: Base URL of the application (e.g., "https://wombie.com")

  ## Returns
    - List of breadcrumb maps suitable for generate/1
  """
  def build_city_breadcrumbs(city, base_url) do
    [
      %{name: "Home", url: base_url},
      %{name: city.name, url: "#{base_url}/cities/#{city.slug}"}
    ]
  end

  @doc """
  Helper function to build breadcrumbs for a venue page.

  @deprecated Use `from_breadcrumb_builder_items/3` with appropriate BreadcrumbBuilder function instead.
  This ensures visual breadcrumbs and JSON-LD breadcrumbs stay in sync.

  ## Parameters
    - venue: Venue struct with preloaded :city_ref
    - base_url: Base URL of the application (e.g., "https://wombie.com")

  ## Returns
    - List of breadcrumb maps suitable for generate/1
  """
  def build_venue_breadcrumbs(venue, base_url) do
    breadcrumbs = [
      %{name: "Home", url: base_url}
    ]

    breadcrumbs =
      if venue.city_ref do
        breadcrumbs ++
          [%{name: venue.city_ref.name, url: "#{base_url}/cities/#{venue.city_ref.slug}"}]
      else
        breadcrumbs
      end

    breadcrumbs ++
      [%{name: venue.name, url: "#{base_url}/venues/#{venue.slug}"}]
  end
end
