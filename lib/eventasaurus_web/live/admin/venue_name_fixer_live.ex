defmodule EventasaurusWeb.Admin.VenueNameFixerLive do
  @moduledoc """
  Admin page for fixing venue names using geocoding metadata.

  Features:
  - View venues with name quality issues by city
  - Filter by severity (severe, moderate, all)
  - Preview current vs. geocoded names with similarity scores
  - Individual fix/skip actions
  - Bulk fix functionality
  - Duplicate detection warnings
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Venues.VenueNameFixer
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Venue Name Fixer")
      |> assign(:cities, load_cities())
      |> assign(:selected_city, nil)
      |> assign(:severity_filter, :all)
      |> assign(:venues, [])
      |> assign(:loading, false)
      |> assign(:processing, MapSet.new())
      |> assign(:show_fixed, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_city", %{"slug" => slug}, socket) do
    case Repo.get_by(City, slug: slug) do
      nil ->
        socket = put_flash(socket, :error, "City not found")
        {:noreply, socket}

      city ->
        socket =
          socket
          |> assign(:selected_city, city)
          |> assign(:loading, true)
          |> load_venues()
          |> assign(:loading, false)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_severity", %{"severity" => severity}, socket) do
    severity_filter =
      case severity do
        "severe" -> :severe
        "moderate" -> :moderate
        "all" -> :all
        _ -> :all
      end

    socket =
      socket
      |> assign(:severity_filter, severity_filter)
      |> assign(:loading, true)
      |> load_venues()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_show_fixed", _params, socket) do
    {:noreply, assign(socket, :show_fixed, !socket.assigns.show_fixed)}
  end

  @impl true
  def handle_event("fix_venue", %{"venue_id" => venue_id_str}, socket) do
    venue_id = String.to_integer(venue_id_str)

    # Find the venue assessment
    assessment = Enum.find(socket.assigns.venues, &(&1.venue.id == venue_id))

    if assessment do
      # Mark as processing
      processing = MapSet.put(socket.assigns.processing, venue_id)
      socket = assign(socket, :processing, processing)

      # Apply fix
      result = VenueNameFixer.fix_venue_name(assessment, dry_run: false, check_duplicates: true)

      socket =
        case result do
          {:renamed, updated_venue, event_count} ->
            socket
            |> put_flash(:info, "✓ Renamed venue ##{venue_id} to \"#{updated_venue.name}\" (#{event_count} events)")
            |> reload_venues()

          {:duplicate_detected, existing_venue, _event_count} ->
            socket
            |> put_flash(:warning, "⚠️  Venue ##{venue_id} is a duplicate of venue ##{existing_venue.id} - skipped")
            |> reload_venues()

          {:skip, reason} ->
            socket
            |> put_flash(:warning, "Skipped venue ##{venue_id}: #{reason}")

          {:error, reason} ->
            socket
            |> put_flash(:error, "Error fixing venue ##{venue_id}: #{reason}")
        end

      # Remove from processing
      processing = MapSet.delete(socket.assigns.processing, venue_id)
      {:noreply, assign(socket, :processing, processing)}
    else
      {:noreply, put_flash(socket, :error, "Venue not found")}
    end
  end

  @impl true
  def handle_event("fix_all", _params, socket) do
    venues = socket.assigns.venues
    total = length(venues)

    if total == 0 do
      {:noreply, put_flash(socket, :warning, "No venues to fix")}
    else
      # Mark all as processing
      processing = venues |> Enum.map(& &1.venue.id) |> MapSet.new()
      socket = assign(socket, :processing, processing)

      # Process all venues
      results =
        Enum.map(venues, fn assessment ->
          VenueNameFixer.fix_venue_name(assessment, dry_run: false, check_duplicates: true)
        end)

      # Count results
      renamed = Enum.count(results, &match?({:renamed, _, _}, &1))
      duplicates = Enum.count(results, &match?({:duplicate_detected, _, _}, &1))
      skipped = Enum.count(results, &match?({:skip, _}, &1))
      errors = Enum.count(results, &match?({:error, _}, &1))

      message = "Fixed #{renamed} venues. #{duplicates} duplicates detected, #{skipped} skipped, #{errors} errors."

      socket =
        socket
        |> put_flash(:info, message)
        |> assign(:processing, MapSet.new())
        |> reload_venues()

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_venues()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  # Private functions

  defp load_cities do
    from(c in City,
      where: c.discovery_enabled == true,
      order_by: [asc: c.name]
    )
    |> Repo.all()
  end

  defp load_venues(socket) do
    city = socket.assigns.selected_city
    severity = socket.assigns.severity_filter

    if city do
      venues = VenueNameFixer.find_venues_with_quality_issues(city.slug, severity)
      assign(socket, :venues, venues)
    else
      assign(socket, :venues, [])
    end
  end

  defp reload_venues(socket) do
    if socket.assigns.selected_city do
      socket
      |> assign(:loading, true)
      |> load_venues()
      |> assign(:loading, false)
    else
      socket
    end
  end

  def format_similarity(nil), do: "N/A"
  def format_similarity(score), do: "#{Float.round(score * 100, 0)}%"

  def severity_badge(:severe), do: "severe"
  def severity_badge(:moderate), do: "moderate"
  def severity_badge(_), do: "acceptable"

  def severity_icon(:severe), do: "🔴"
  def severity_icon(:moderate), do: "⚠️"
  def severity_icon(_), do: "✅"

  def is_processing?(socket, venue_id) do
    MapSet.member?(socket.assigns.processing, venue_id)
  end
end
