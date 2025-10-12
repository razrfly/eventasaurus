defmodule EventasaurusWeb.Admin.GeocodingDashboardLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Metrics.GeocodingStats

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, load_stats(socket)}
    else
      {:ok, assign_defaults(socket)}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_stats(socket)}
  end

  @impl true
  def handle_event("generate_report", _params, socket) do
    # Trigger manual cost report generation
    case EventasaurusDiscovery.Workers.GeocodingCostReportWorker.generate_report() do
      {:ok, report} ->
        socket =
          socket
          |> put_flash(:info, "Cost report generated successfully!")
          |> assign(:manual_report, report)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate report: #{inspect(reason)}")}
    end
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:page_title, "Geocoding Performance Dashboard")
    |> assign(:loading, true)
    |> assign(:summary, nil)
    |> assign(:by_provider, [])
    |> assign(:by_scraper, [])
    |> assign(:failed_venues, [])
    |> assign(:error, nil)
    |> assign(:manual_report, nil)
    |> assign(:overall_success_rate, nil)
    |> assign(:provider_hit_rates, [])
    |> assign(:fallback_depth, [])
  end

  defp load_stats(socket) do
    case GeocodingStats.performance_summary() do
      {:ok, summary} ->
        failed_venues =
          case GeocodingStats.failed_geocoding_venues(10) do
            {:ok, venues} -> venues
            {:error, _} -> []
          end

        socket
        |> assign(:loading, false)
        |> assign(:summary, summary)
        |> assign(:by_provider, summary.by_provider)
        |> assign(:by_scraper, summary.by_scraper)
        |> assign(:failed_venues, failed_venues)
        |> assign(:error, nil)
        |> assign(:manual_report, nil)
        |> assign(:overall_success_rate, summary.overall_success_rate)
        |> assign(:provider_hit_rates, summary.provider_hit_rates)
        |> assign(:fallback_depth, summary.fallback_depth)

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> assign(:summary, nil)
        |> assign(:by_provider, [])
        |> assign(:by_scraper, [])
        |> assign(:failed_venues, [])
        |> assign(:error, "Failed to load stats: #{inspect(reason)}")
        |> assign(:overall_success_rate, nil)
        |> assign(:provider_hit_rates, [])
        |> assign(:fallback_depth, [])
    end
  end

  # Helper functions for template

  # Free providers (primary)
  defp provider_badge_class("mapbox"), do: "bg-blue-100 text-blue-800"
  defp provider_badge_class("here"), do: "bg-purple-100 text-purple-800"
  defp provider_badge_class("geoapify"), do: "bg-teal-100 text-teal-800"
  defp provider_badge_class("locationiq"), do: "bg-indigo-100 text-indigo-800"
  defp provider_badge_class("photon"), do: "bg-pink-100 text-pink-800"
  defp provider_badge_class("openstreetmap"), do: "bg-green-100 text-green-800"

  # Legacy/paid providers
  defp provider_badge_class("google_places"), do: "bg-orange-100 text-orange-800"
  defp provider_badge_class("google_maps"), do: "bg-orange-100 text-orange-800"

  # Other
  defp provider_badge_class("city_resolver_offline"), do: "bg-gray-100 text-gray-800"
  defp provider_badge_class("provided"), do: "bg-gray-100 text-gray-800"
  defp provider_badge_class("deferred"), do: "bg-yellow-100 text-yellow-800"
  defp provider_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_provider_name("mapbox"), do: "Mapbox"
  defp format_provider_name("here"), do: "HERE"
  defp format_provider_name("geoapify"), do: "Geoapify"
  defp format_provider_name("locationiq"), do: "LocationIQ"
  defp format_provider_name("photon"), do: "Photon"
  defp format_provider_name("openstreetmap"), do: "OpenStreetMap"
  defp format_provider_name("google_places"), do: "Google Places"
  defp format_provider_name("google_maps"), do: "Google Maps"
  defp format_provider_name("city_resolver_offline"), do: "CityResolver (Offline)"
  defp format_provider_name("provided"), do: "Provided Coordinates"
  defp format_provider_name("deferred"), do: "Deferred"
  defp format_provider_name(nil), do: "Unknown"
  defp format_provider_name(name), do: name |> String.replace("_", " ") |> String.capitalize()

  # Success rate badge colors
  defp success_rate_badge_class(rate) when rate >= 95.0, do: "bg-green-100 text-green-800"
  defp success_rate_badge_class(rate) when rate >= 85.0, do: "bg-yellow-100 text-yellow-800"
  defp success_rate_badge_class(_), do: "bg-red-100 text-red-800"

  defp format_scraper_name("question_one"), do: "QuestionOne"
  defp format_scraper_name("kino_krakow"), do: "Kino Krakow"
  defp format_scraper_name("resident_advisor"), do: "Resident Advisor"
  defp format_scraper_name("karnet"), do: "Karnet"
  defp format_scraper_name("cinema_city"), do: "Cinema City"
  defp format_scraper_name(nil), do: "Unknown"
  defp format_scraper_name(name), do: name |> String.replace("_", " ") |> String.capitalize()
end
