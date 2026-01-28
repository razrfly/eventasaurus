defmodule EventasaurusWeb.Admin.VenueExclusionsLive do
  @moduledoc """
  Admin page for viewing venue duplicate exclusions with filters.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Venues.VenueDeduplication

  @page_size 50
  @sort_keys %{
    "date" => :inserted_at,
    "confidence" => :confidence_score,
    "similarity" => :similarity_score,
    "distance" => :distance_meters
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Venue Exclusions")
     |> assign(:loading, true)
     |> assign(:cities, [])
     |> assign(:filters, %{})
     |> assign(:exclusions, [])
     |> assign(:total_count, 0)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    cities = VenueDeduplication.list_exclusion_cities()
    city_map = Map.new(cities, &{&1.slug, &1.id})

    {filters, page} = parse_filters(params, city_map)
    {exclusions, total_count} = load_exclusions(filters, page)
    total_pages = max(1, ceil_div(total_count, @page_size))

    {:noreply,
     socket
     |> assign(:cities, cities)
     |> assign(:filters, filters)
     |> assign(:exclusions, exclusions)
     |> assign(:total_count, total_count)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)
     |> assign(:loading, false)}
  end

  defp load_exclusions(filters, page) do
    opts = [
      city_id: filters[:city_id],
      start_date: filters[:start_date],
      end_date: filters[:end_date],
      min_confidence: filters[:min_confidence],
      max_confidence: filters[:max_confidence],
      sort_by: filters[:sort_by],
      sort_dir: filters[:sort_dir],
      limit: @page_size,
      offset: (page - 1) * @page_size
    ]

    exclusions = VenueDeduplication.list_exclusions(opts)
    total_count = VenueDeduplication.count_exclusions(opts)

    {exclusions, total_count}
  end

  defp parse_filters(params, city_map) do
    city_slug = Map.get(params, "city")
    city_id = if city_slug, do: Map.get(city_map, city_slug)

    min_confidence = parse_float_param(Map.get(params, "min_confidence"))
    max_confidence = parse_float_param(Map.get(params, "max_confidence"))

    sort_by =
      params
      |> Map.get("sort_by", "date")
      |> then(fn value -> Map.get(@sort_keys, value, :inserted_at) end)

    sort_dir =
      case Map.get(params, "sort_dir", "desc") do
        "asc" -> :asc
        _ -> :desc
      end

    start_date = parse_date_start(Map.get(params, "start_date"))
    end_date = parse_date_end(Map.get(params, "end_date"))

    page = parse_page(Map.get(params, "page"))

    filters = %{
      city_slug: city_slug,
      city_id: city_id,
      start_date: start_date,
      end_date: end_date,
      min_confidence: min_confidence,
      max_confidence: max_confidence,
      sort_by: sort_by,
      sort_dir: sort_dir
    }

    {filters, page}
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_float_param(nil), do: nil

  defp parse_float_param(value) do
    case Float.parse(value) do
      {float, _} -> float
      _ -> nil
    end
  end

  defp parse_date_start(nil), do: nil

  defp parse_date_start(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         {:ok, datetime} <- DateTime.new(date, ~T[00:00:00], "Etc/UTC") do
      datetime
    else
      _ -> nil
    end
  end

  defp parse_date_end(nil), do: nil

  defp parse_date_end(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         {:ok, datetime} <- DateTime.new(date, ~T[23:59:59], "Etc/UTC") do
      datetime
    else
      _ -> nil
    end
  end

  defp ceil_div(0, _), do: 1
  defp ceil_div(value, size), do: div(value + size - 1, size)

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_datetime(_), do: "--"

  defp format_decimal(nil), do: "--"

  defp format_decimal(%Decimal{} = decimal) do
    decimal
    |> Decimal.to_float()
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp format_decimal(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp format_decimal(_), do: "--"

  defp page_params(filters, page) do
    params = [
      {"page", page},
      {"city", filters[:city_slug]},
      {"start_date", date_param(filters[:start_date])},
      {"end_date", date_param(filters[:end_date])},
      {"min_confidence", filters[:min_confidence]},
      {"max_confidence", filters[:max_confidence]},
      {"sort_by", sort_key(filters[:sort_by])},
      {"sort_dir", if(filters[:sort_dir] == :asc, do: "asc", else: "desc")}
    ]

    Enum.reject(params, fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp sort_key(:confidence_score), do: "confidence"
  defp sort_key(:similarity_score), do: "similarity"
  defp sort_key(:distance_meters), do: "distance"
  defp sort_key(_), do: "date"

  defp date_param(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp date_param(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.to_date()
    |> Date.to_iso8601()
  end

  defp date_param(_), do: nil
end
