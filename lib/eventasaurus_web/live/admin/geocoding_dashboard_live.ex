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
    |> assign(:page_title, "Geocoding Cost Dashboard")
    |> assign(:loading, true)
    |> assign(:summary, nil)
    |> assign(:by_provider, [])
    |> assign(:by_scraper, [])
    |> assign(:failed_venues, [])
    |> assign(:error, nil)
    |> assign(:manual_report, nil)
  end

  defp load_stats(socket) do
    case GeocodingStats.summary() do
      {:ok, summary} ->
        failed_venues = case GeocodingStats.failed_geocoding_venues(10) do
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

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> assign(:summary, nil)
        |> assign(:by_provider, [])
        |> assign(:by_scraper, [])
        |> assign(:failed_venues, [])
        |> assign(:error, "Failed to load stats: #{inspect(reason)}")
    end
  end

  # Helper functions for template

  defp provider_badge_class("google_places"), do: "bg-blue-100 text-blue-800"
  defp provider_badge_class("google_maps"), do: "bg-purple-100 text-purple-800"
  defp provider_badge_class("openstreetmap"), do: "bg-green-100 text-green-800"
  defp provider_badge_class("city_resolver_offline"), do: "bg-gray-100 text-gray-800"
  defp provider_badge_class("provided"), do: "bg-indigo-100 text-indigo-800"
  defp provider_badge_class("deferred"), do: "bg-yellow-100 text-yellow-800"
  defp provider_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_provider_name("google_places"), do: "Google Places"
  defp format_provider_name("google_maps"), do: "Google Maps"
  defp format_provider_name("openstreetmap"), do: "OpenStreetMap"
  defp format_provider_name("city_resolver_offline"), do: "CityResolver (Offline)"
  defp format_provider_name("provided"), do: "Provided Coordinates"
  defp format_provider_name("deferred"), do: "Deferred"
  defp format_provider_name(nil), do: "Unknown"
  defp format_provider_name(name), do: name |> String.replace("_", " ") |> String.capitalize()

  defp format_scraper_name("question_one"), do: "QuestionOne"
  defp format_scraper_name("kino_krakow"), do: "Kino Krakow"
  defp format_scraper_name("resident_advisor"), do: "Resident Advisor"
  defp format_scraper_name("karnet"), do: "Karnet"
  defp format_scraper_name("cinema_city"), do: "Cinema City"
  defp format_scraper_name(nil), do: "Unknown"
  defp format_scraper_name(name), do: name |> String.replace("_", " ") |> String.capitalize()
end
