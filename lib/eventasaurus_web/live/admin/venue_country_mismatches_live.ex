defmodule EventasaurusWeb.Admin.VenueCountryMismatchesLive do
  @moduledoc """
  Admin page for reviewing and fixing venue country mismatches.

  Features:
  - Dashboard with summary stats and country pair breakdown
  - Paginated list of mismatches with filtering
  - Fix individual mismatches (reassign to correct country)
  - Ignore false positives
  - Bulk fix HIGH confidence mismatches
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Admin.DataQualityChecker

  # Higher limit for admin tool - we want to find all mismatches
  # The geocoding check is fast (offline library), so 500 is reasonable
  @default_limit 500

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Venue Country Mismatches")
      |> assign(:loading, false)
      |> assign(:result, nil)
      |> assign(:filters, %{
        source: nil,
        from_country: nil,
        to_country: nil,
        confidence: nil
      })
      |> assign(:limit, @default_limit)
      |> assign(:active_tab, "dashboard")
      |> assign(:bulk_fixing, false)
      |> load_mismatches()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      source: params["source"],
      from_country: params["from"],
      to_country: params["to"],
      confidence: parse_confidence(params["confidence"])
    }

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:limit, parse_limit(params["limit"]))
      |> load_mismatches()

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_mismatches()
      |> assign(:loading, false)
      |> put_flash(:info, "Refreshed mismatch data")

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      source: blank_to_nil(params["source"]),
      from_country: blank_to_nil(params["from_country"]),
      to_country: blank_to_nil(params["to_country"]),
      confidence: parse_confidence(params["confidence"])
    }

    socket =
      socket
      |> assign(:filters, filters)
      |> load_mismatches()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(:filters, %{source: nil, from_country: nil, to_country: nil, confidence: nil})
      |> load_mismatches()

    {:noreply, socket}
  end

  @impl true
  def handle_event("fix_venue", %{"venue_id" => venue_id_str}, socket) do
    venue_id = String.to_integer(venue_id_str)

    case DataQualityChecker.fix_venue_country(venue_id) do
      {:ok, fix_result} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Fixed venue: #{fix_result.venue.name} moved from #{fix_result.old_country} to #{fix_result.new_country}"
          )
          |> load_mismatches()

        {:noreply, socket}

      {:error, reason} ->
        error_msg = format_error(reason)
        {:noreply, put_flash(socket, :error, "Failed to fix venue: #{error_msg}")}
    end
  end

  @impl true
  def handle_event("ignore_venue", %{"venue_id" => venue_id_str}, socket) do
    venue_id = String.to_integer(venue_id_str)

    case DataQualityChecker.ignore_venue_country_mismatch(venue_id) do
      {:ok, _venue} ->
        socket =
          socket
          |> put_flash(:info, "Venue marked as ignored (false positive)")
          |> load_mismatches()

        {:noreply, socket}

      {:error, reason} ->
        error_msg = format_error(reason)
        {:noreply, put_flash(socket, :error, "Failed to ignore venue: #{error_msg}")}
    end
  end

  @impl true
  def handle_event("bulk_fix", _params, socket) do
    socket = assign(socket, :bulk_fixing, true)

    filters = socket.assigns.filters

    options = [
      confidence: :high,
      from_country: filters.from_country,
      to_country: filters.to_country,
      limit: @default_limit
    ]

    case DataQualityChecker.bulk_fix_venue_countries(options) do
      {:ok, result} ->
        socket =
          socket
          |> assign(:bulk_fixing, false)
          |> put_flash(
            :info,
            "Bulk fix complete: #{result.fixed} fixed, #{result.failed} failed"
          )
          |> load_mismatches()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:bulk_fixing, false)
          |> put_flash(:error, "Bulk fix failed: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("export_json", _params, socket) do
    # Generate export data
    result = socket.assigns.result

    if result do
      export_data = DataQualityChecker.export_venue_country_report(limit: 1000)
      json = Jason.encode!(export_data, pretty: true)

      {:noreply,
       push_event(socket, "download", %{
         filename: "venue_country_mismatches_#{Date.utc_today()}.json",
         content: json,
         content_type: "application/json"
       })}
    else
      {:noreply, put_flash(socket, :error, "No data to export")}
    end
  end

  # Private functions

  defp load_mismatches(socket) do
    filters = socket.assigns.filters
    limit = socket.assigns.limit

    options =
      [limit: limit]
      |> maybe_add_filter(:source, filters.source)
      |> maybe_add_filter(:country, filters.from_country)

    result = DataQualityChecker.check_venue_countries(options)

    # Apply client-side filters for to_country and confidence
    filtered_mismatches =
      result.mismatches
      |> filter_by_to_country(filters.to_country)
      |> filter_by_confidence(filters.confidence)

    filtered_result = %{
      result
      | mismatches: filtered_mismatches,
        mismatch_count: length(filtered_mismatches)
    }

    # Get unique sources and country pairs for filter dropdowns
    sources = get_unique_sources(result.mismatches)
    country_pairs = get_country_pairs(result.by_country_pair)

    socket
    |> assign(:result, filtered_result)
    |> assign(:sources, sources)
    |> assign(:country_pairs, country_pairs)
  end

  defp maybe_add_filter(options, _key, nil), do: options
  defp maybe_add_filter(options, key, value), do: [{key, value} | options]

  defp filter_by_to_country(mismatches, nil), do: mismatches

  defp filter_by_to_country(mismatches, to_country) do
    Enum.filter(mismatches, &(&1.expected_country == to_country))
  end

  defp filter_by_confidence(mismatches, nil), do: mismatches

  defp filter_by_confidence(mismatches, confidence) do
    Enum.filter(mismatches, &(&1.confidence == confidence))
  end

  defp get_unique_sources(mismatches) do
    mismatches
    |> Enum.map(& &1.source)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp get_country_pairs(by_country_pair) do
    by_country_pair
    |> Enum.map(fn {{from, to}, count} -> %{from: from, to: to, count: count} end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp parse_confidence(nil), do: nil
  defp parse_confidence(""), do: nil
  defp parse_confidence("high"), do: :high
  defp parse_confidence("medium"), do: :medium
  defp parse_confidence("low"), do: :low
  defp parse_confidence(_), do: nil

  defp parse_limit(nil), do: @default_limit

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {n, _} when n > 0 -> n
      _ -> @default_limit
    end
  end

  defp parse_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp parse_limit(_), do: @default_limit

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_error(:venue_not_found), do: "Venue not found"
  defp format_error(:no_coordinates), do: "Venue has no GPS coordinates"
  defp format_error(:not_a_mismatch), do: "Venue is not a mismatch"
  defp format_error({:geocoding_failed, reason}), do: "Geocoding failed: #{inspect(reason)}"
  defp format_error({:city_creation_failed, reason}), do: "City creation failed: #{inspect(reason)}"
  defp format_error({:update_failed, _}), do: "Database update failed"
  defp format_error(reason), do: inspect(reason)

  # Helper functions for template
  def confidence_color(:high), do: "bg-green-100 text-green-800"
  def confidence_color(:medium), do: "bg-yellow-100 text-yellow-800"
  def confidence_color(:low), do: "bg-red-100 text-red-800"
  def confidence_color(_), do: "bg-gray-100 text-gray-800"

  def confidence_label(:high), do: "HIGH"
  def confidence_label(:medium), do: "MEDIUM"
  def confidence_label(:low), do: "LOW"
  def confidence_label(_), do: "UNKNOWN"

  def format_coords(lat, lng) when is_float(lat) and is_float(lng) do
    "#{Float.round(lat, 4)}, #{Float.round(lng, 4)}"
  end

  def format_coords(_, _), do: "N/A"

  def truncate(str, max_len) when is_binary(str) and max_len >= 4 do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len - 3) <> "..."
    else
      str
    end
  end

  def truncate(str, max_len) when is_binary(str) and max_len < 4 do
    String.slice(str, 0, max_len)
  end

  def truncate(str, _max_len), do: str
end
