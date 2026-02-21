defmodule EventasaurusWeb.Admin.VenueExclusionsLive do
  @moduledoc """
  Admin page for viewing venue duplicate exclusions with filters.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Venues.VenueDeduplication

  @page_size 50
  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Venue Exclusions")
     |> assign(:loading, true)
     |> assign(:cities, [])
     |> assign(:filters, %{})
     |> assign(:exclusions, [])
     |> assign(:total_count, 0)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:current_user_id, get_user_id(session))}
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

  @impl true
  def handle_event("remove_exclusion", %{"venue_id_1" => id1, "venue_id_2" => id2}, socket) do
    user_id = socket.assigns.current_user_id

    with {venue_id_1, ""} <- Integer.parse(id1),
         {venue_id_2, ""} <- Integer.parse(id2),
         true <- not is_nil(user_id) do
      case VenueDeduplication.remove_exclusion(venue_id_1, venue_id_2, user_id: user_id) do
        {0, _} ->
          {:noreply, put_flash(socket, :error, "Exclusion already removed.")}

        {_count, _} ->
          {exclusions, total_count} =
            load_exclusions(socket.assigns.filters, socket.assigns.page)

          total_pages = max(1, ceil_div(total_count, @page_size))

          {:noreply,
           socket
           |> put_flash(:info, "Exclusion removed. Pair will be detected again.")
           |> assign(:exclusions, exclusions)
           |> assign(:total_count, total_count)
           |> assign(:total_pages, total_pages)}
      end
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, "Unable to remove exclusion. Please refresh and try again.")}
    end
  end

  defp load_exclusions(filters, page) do
    opts = [
      city_id: filters[:city_id],
      search: filters[:search],
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
    search = Map.get(params, "search")

    page = parse_page(Map.get(params, "page"))

    filters = %{
      city_slug: city_slug,
      city_id: city_id,
      search: search
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

  defp get_user_id(session) do
    case session do
      %{"current_user_id" => id} -> id
      _ -> nil
    end
  end

  defp page_params(filters, page) do
    params = [
      {"page", page},
      {"city", filters[:city_slug]},
      {"search", filters[:search]}
    ]

    Enum.reject(params, fn {_key, value} -> is_nil(value) or value == "" end)
  end
end
