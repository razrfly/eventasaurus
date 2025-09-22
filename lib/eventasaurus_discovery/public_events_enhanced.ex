defmodule EventasaurusDiscovery.PublicEventsEnhanced do
  @moduledoc """
  Enhanced PublicEvents context with comprehensive filtering, search, and pagination.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City

  @default_limit 20
  @max_limit 100

  @doc """
  List events with comprehensive filtering options.

  ## Options
    * `:categories` - List of category IDs to filter by
    * `:start_date` - Filter events starting after this date
    * `:end_date` - Filter events starting before this date
    * `:min_price` - Minimum price filter
    * `:max_price` - Maximum price filter
    * `:city_id` - Filter by city ID
    * `:country_id` - Filter by country ID
    * `:venue_ids` - List of venue IDs
    * `:search` - Text search query
    * `:language` - Language code for translations (default: "en")
    * `:sort_by` - Sort field (:starts_at, :price, :title, :relevance)
    * `:sort_order` - :asc or :desc
    * `:page` - Page number for pagination
    * `:page_size` - Items per page (max: 100)
  """
  def list_events(opts \\ []) do
    base_query = from(pe in PublicEvent)

    base_query
    |> filter_by_categories(opts[:categories])
    |> filter_by_date_range(opts[:start_date], opts[:end_date])
    |> filter_by_price_range(opts[:min_price], opts[:max_price])
    |> filter_by_location(opts[:city_id], opts[:country_id], opts[:venue_ids])
    |> apply_search(opts[:search])
    |> apply_sorting(opts[:sort_by], opts[:sort_order])
    |> paginate(opts[:page], opts[:page_size])
    |> Repo.all()
    |> preload_with_sources(opts[:language])
  end

  @doc """
  Full-text search for events.
  """
  def search_events(search_term, opts \\ []) when is_binary(search_term) do
    language = opts[:language] || "en"
    limit = min(opts[:limit] || @default_limit, @max_limit)
    offset = opts[:offset] || 0

    # Build search query
    search_query = String.trim(search_term)

    from(pe in PublicEvent,
      where: fragment(
        "? @@ websearch_to_tsquery('english', ?)",
        pe.search_vector,
        ^search_query
      ) or
      fragment(
        "? ILIKE ?",
        pe.title,
        ^"%#{search_query}%"
      ),
      order_by: [
        desc: fragment(
          "ts_rank(?, websearch_to_tsquery('english', ?))",
          pe.search_vector,
          ^search_query
        )
      ],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
    |> preload_with_sources(language)
  end

  @doc """
  Get events from the localized view with language preference.
  """
  def list_events_localized(opts \\ []) do
    language = opts[:language] || "en"
    limit = min(opts[:limit] || @default_limit, @max_limit)
    offset = opts[:offset] || 0

    query = """
    SELECT
      id,
      slug,
      COALESCE(
        title_translations->>'#{language}',
        title_translations->>'en',
        title
      ) as display_title,
      COALESCE(
        description_translations->>'#{language}',
        description_translations->>'en'
      ) as display_description,
      starts_at,
      ends_at,
      venue_name,
      venue_slug,
      city_name,
      country_name,
      category_name,
      category_color,
      category_icon,
      min_price,
      max_price,
      currency,
      ticket_url,
      image_url
    FROM public_events_view
    WHERE starts_at > NOW()
    ORDER BY starts_at ASC
    LIMIT $1 OFFSET $2
    """

    result = Ecto.Adapters.SQL.query!(Repo, query, [limit, offset])

    # Convert to maps
    Enum.map(result.rows, fn row ->
      Enum.zip(result.columns, row)
      |> Enum.into(%{})
      |> Map.update(:starts_at, nil, &parse_datetime/1)
      |> Map.update(:ends_at, nil, &parse_datetime/1)
    end)
  end

  ## Filter Functions

  defp filter_by_categories(query, nil), do: query
  defp filter_by_categories(query, []), do: query
  defp filter_by_categories(query, category_ids) when is_list(category_ids) do
    from(pe in query,
      join: pec in "public_event_categories",
      on: pec.event_id == pe.id,
      where: pec.category_id in ^category_ids
    )
  end

  defp filter_by_date_range(query, nil, nil), do: query
  defp filter_by_date_range(query, start_date, nil) do
    from(pe in query, where: pe.starts_at >= ^start_date)
  end
  defp filter_by_date_range(query, nil, end_date) do
    from(pe in query, where: pe.starts_at <= ^end_date)
  end
  defp filter_by_date_range(query, start_date, end_date) do
    from(pe in query,
      where: pe.starts_at >= ^start_date and pe.starts_at <= ^end_date
    )
  end

  defp filter_by_price_range(query, nil, nil), do: query
  defp filter_by_price_range(query, min_price, nil) do
    from(pe in query,
      where: is_nil(pe.min_price) or pe.max_price >= ^min_price
    )
  end
  defp filter_by_price_range(query, nil, max_price) do
    from(pe in query,
      where: is_nil(pe.min_price) or pe.min_price <= ^max_price
    )
  end
  defp filter_by_price_range(query, min_price, max_price) do
    from(pe in query,
      where: (is_nil(pe.min_price) and is_nil(pe.max_price)) or
             (pe.max_price >= ^min_price and pe.min_price <= ^max_price)
    )
  end

  defp filter_by_location(query, nil, nil, nil), do: query
  defp filter_by_location(query, city_id, country_id, venue_ids) do
    query
    |> filter_by_city(city_id)
    |> filter_by_country(country_id)
    |> filter_by_venues(venue_ids)
  end

  defp filter_by_city(query, nil), do: query
  defp filter_by_city(query, city_id) do
    from(pe in query,
      join: v in Venue, on: pe.venue_id == v.id,
      where: v.city_id == ^city_id
    )
  end

  defp filter_by_country(query, nil), do: query
  defp filter_by_country(query, country_id) do
    from(pe in query,
      join: v in Venue, on: pe.venue_id == v.id,
      join: c in City, on: v.city_id == c.id,
      where: c.country_id == ^country_id
    )
  end

  defp filter_by_venues(query, nil), do: query
  defp filter_by_venues(query, []), do: query
  defp filter_by_venues(query, venue_ids) when is_list(venue_ids) do
    from(pe in query, where: pe.venue_id in ^venue_ids)
  end

  ## Search

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query
  defp apply_search(query, search_term) do
    search_query = String.trim(search_term)
    from(pe in query,
      where: fragment(
        "? @@ websearch_to_tsquery('english', ?) OR ? ILIKE ?",
        pe.search_vector,
        ^search_query,
        pe.title,
        ^"%#{search_query}%"
      )
    )
  end

  ## Sorting

  defp apply_sorting(query, nil, nil), do: apply_sorting(query, :starts_at, :asc)
  defp apply_sorting(query, nil, order), do: apply_sorting(query, :starts_at, order || :asc)
  defp apply_sorting(query, field, nil), do: apply_sorting(query, field, :asc)
  defp apply_sorting(query, :starts_at, order) when order in [:asc, :desc] do
    from(pe in query, order_by: [{^order, pe.starts_at}])
  end
  defp apply_sorting(query, :price, order) when order in [:asc, :desc] do
    from(pe in query, order_by: [{^order, pe.min_price}])
  end
  defp apply_sorting(query, :title, order) when order in [:asc, :desc] do
    from(pe in query, order_by: [{^order, pe.title}])
  end
  defp apply_sorting(query, :relevance, _order) do
    # Relevance sorting only makes sense with search
    query
  end
  defp apply_sorting(query, _field, _order), do: apply_sorting(query, :starts_at, :asc)

  ## Pagination

  defp paginate(query, nil, nil), do: paginate(query, 1, @default_limit)
  defp paginate(query, page, page_size) do
    page = max(page || 1, 1)
    page_size = min(page_size || @default_limit, @max_limit)
    offset = (page - 1) * page_size

    from(pe in query,
      limit: ^page_size,
      offset: ^offset
    )
  end

  ## Preloading

  defp preload_with_sources(events, language) do
    events
    |> Repo.preload([
      :venue,
      :categories,
      :performers,
      :sources
    ])
    |> Enum.map(fn event ->
      # Add display fields based on language
      Map.merge(event, %{
        display_title: get_localized_title(event, language),
        display_description: get_localized_description(event, language),
        cover_image_url: get_cover_image_url(event)
      })
    end)
  end

  defp get_localized_title(event, language) do
    case event.title_translations do
      nil -> event.title
      translations when is_map(translations) ->
        translations[language] || translations["en"] || event.title
      _ -> event.title
    end
  end

  defp get_localized_description(event, language) do
    # Sort sources by priority and take the first one's description
    sorted_sources = event.sources
    |> Enum.sort_by(fn source ->
      priority = case source.metadata do
        %{"priority" => p} when is_integer(p) -> p
        %{"priority" => p} when is_binary(p) ->
          case Integer.parse(p) do
            {num, _} -> num
            _ -> 10
          end
        _ -> 10
      end
      {priority, source.last_seen_at}
    end)

    case sorted_sources do
      [source | _] ->
        case source.description_translations do
          nil -> nil
          translations when is_map(translations) ->
            translations[language] || translations["en"] || nil
          _ -> nil
        end
      _ -> nil
    end
  end

  defp get_cover_image_url(event) do
    # Sort sources by priority and try to get the first available image
    sorted_sources = event.sources
    |> Enum.sort_by(fn source ->
      priority = case source.metadata do
        %{"priority" => p} when is_integer(p) -> p
        %{"priority" => p} when is_binary(p) ->
          case Integer.parse(p) do
            {num, _} -> num
            _ -> 10
          end
        _ -> 10
      end
      {priority, source.last_seen_at}
    end)

    # Try to extract image from sources
    Enum.find_value(sorted_sources, fn source ->
      # First check the direct image_url field
      if source.image_url do
        source.image_url
      else
        # Fall back to metadata
        extract_image_from_metadata(source.metadata)
      end
    end)
  end

  defp extract_image_from_metadata(nil), do: nil
  defp extract_image_from_metadata(metadata) do
    cond do
      # Ticketmaster stores images in an array
      images = get_in(metadata, ["ticketmaster_data", "images"]) ->
        case images do
          [%{"url" => url} | _] when is_binary(url) -> url
          _ -> nil
        end

      # Bandsintown and Karnet store in image_url
      url = metadata["image_url"] ->
        url

      true ->
        nil
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
  defp parse_datetime(datetime), do: datetime

  @doc """
  Count total events matching filters (for pagination metadata).
  """
  def count_events(opts \\ []) do
    base_query = from(pe in PublicEvent, select: count(pe.id))

    base_query
    |> filter_by_categories(opts[:categories])
    |> filter_by_date_range(opts[:start_date], opts[:end_date])
    |> filter_by_price_range(opts[:min_price], opts[:max_price])
    |> filter_by_location(opts[:city_id], opts[:country_id], opts[:venue_ids])
    |> apply_search(opts[:search])
    |> Repo.one()
  end

  @doc """
  Get facet counts for filters (useful for showing available options).
  """
  def get_filter_facets(base_filters \\ []) do
    # Get counts for each filterable dimension
    %{
      categories: get_category_counts(base_filters),
      cities: get_city_counts(base_filters),
      price_ranges: get_price_range_counts(base_filters),
      date_ranges: get_date_range_counts(base_filters)
    }
  end

  defp get_category_counts(base_filters) do
    from(pe in PublicEvent,
      join: pec in "public_event_categories", on: pec.event_id == pe.id,
      join: c in Category, on: c.id == pec.category_id,
      where: pe.starts_at > ^DateTime.utc_now(),
      group_by: [c.id, c.name],
      select: {c.id, c.name, count(pe.id)}
    )
    |> apply_base_filters(base_filters)
    |> Repo.all()
    |> Enum.map(fn {id, name, count} ->
      %{id: id, name: name, count: count}
    end)
  end

  defp get_city_counts(base_filters) do
    from(pe in PublicEvent,
      join: v in Venue, on: pe.venue_id == v.id,
      join: c in City, on: v.city_id == c.id,
      where: pe.starts_at > ^DateTime.utc_now(),
      group_by: [c.id, c.name],
      select: {c.id, c.name, count(pe.id)}
    )
    |> apply_base_filters(base_filters)
    |> Repo.all()
    |> Enum.map(fn {id, name, count} ->
      %{id: id, name: name, count: count}
    end)
  end

  defp get_price_range_counts(base_filters) do
    # Define price ranges
    ranges = [
      {:free, 0, 0},
      {:under_25, 0.01, 25},
      {:under_50, 25.01, 50},
      {:under_100, 50.01, 100},
      {:over_100, 100.01, 999999}
    ]

    Enum.map(ranges, fn {label, min, max} ->
      query = from(pe in PublicEvent,
        where: pe.starts_at > ^DateTime.utc_now()
      )

      count = if min == 0 and max == 0 do
        from(pe in query,
          where: is_nil(pe.min_price) or pe.min_price == 0,
          select: count(pe.id)
        )
      else
        from(pe in query,
          where: pe.min_price >= ^min and pe.min_price <= ^max,
          select: count(pe.id)
        )
      end
      |> apply_base_filters(base_filters)
      |> Repo.one()

      %{label: label, min: min, max: max, count: count}
    end)
  end

  defp get_date_range_counts(base_filters) do
    now = DateTime.utc_now()
    today_end = DateTime.add(now, 86400, :second) |> DateTime.truncate(:second)
    week_end = DateTime.add(now, 7 * 86400, :second)
    month_end = DateTime.add(now, 30 * 86400, :second)

    [
      {:today, now, today_end},
      {:this_week, now, week_end},
      {:this_month, now, month_end}
    ]
    |> Enum.map(fn {label, start_date, end_date} ->
      count = from(pe in PublicEvent,
        where: pe.starts_at >= ^start_date and pe.starts_at <= ^end_date,
        select: count(pe.id)
      )
      |> apply_base_filters(base_filters)
      |> Repo.one()

      %{label: label, count: count}
    end)
  end

  defp apply_base_filters(query, filters) do
    # Apply any base filters that should affect facet counts
    query
    |> filter_by_categories(filters[:categories])
    |> apply_search(filters[:search])
  end
end