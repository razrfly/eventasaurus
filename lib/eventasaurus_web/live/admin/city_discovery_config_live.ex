defmodule EventasaurusWeb.Admin.CityDiscoveryConfigLive do
  @moduledoc """
  Admin page for configuring automated discovery for individual cities.
  Allows managing sources, settings, and viewing statistics.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Locations.City.DiscoveryConfig
  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
  alias EventasaurusDiscovery.Admin.DiscoveryStatsCollector

  import Ecto.Query
  require Logger

  # Cinema City Poland locations (from API: addressInfo.city)
  # These rarely change - update if Cinema City adds/removes locations
  @cinema_city_cities [
    "Bielsko-Biała",
    "Bydgoszcz",
    "Bytom",
    "Cieszyn",
    "Częstochowa",
    "Elbląg",
    "Gliwice",
    "Janki",
    "Katowice",
    "Kraków",
    "Lublin",
    "Łódź",
    "Poznań",
    "Ruda Śląska",
    "Rybnik",
    "Sosnowiec",
    "Starogard Gdański",
    "Toruń",
    "Wałbrzych",
    "Warszawa",
    "Wrocław",
    "Zielona Góra"
  ]

  # Resident Advisor area IDs (discovered via browser DevTools on ra.co)
  # Format: {display_name, area_id}
  # To find new area IDs:
  # 1. Open https://ra.co/events/{country}/{city} in browser
  # 2. Open DevTools → Network → Filter "graphql"
  # 3. Scroll page to trigger event listing query
  # 4. Inspect request payload → variables.filters.areas.eq
  @resident_advisor_areas [
    {"Kraków, Poland", 455},
    {"Warsaw, Poland", 454},
    {"London, UK", 34},
    {"Berlin, Germany", 143},
    {"Amsterdam, Netherlands", 29},
    {"Barcelona, Spain", 88},
    {"Paris, France", 44},
    {"New York, USA", 8},
    {"Los Angeles, USA", 23},
    {"Tokyo, Japan", 297},
    {"Sydney, Australia", 113},
    {"Melbourne, Australia", 85},
    {"Ibiza, Spain", 25},
    {"Detroit, USA", 26},
    {"Chicago, USA", 37},
    {"San Francisco, USA", 54},
    {"Manchester, UK", 21},
    {"Bristol, UK", 98},
    {"Glasgow, UK", 101},
    {"Lisbon, Portugal", 153},
    {"Vienna, Austria", 103},
    {"Prague, Czech Republic", 120},
    {"Budapest, Hungary", 307}
  ]

  # Repertuary.pl city keys - loaded from Cities module
  # Format: {display_name, city_key}
  # city_key is used to construct the URL (e.g., "warszawa" -> warszawa.repertuary.pl)
  @repertuary_cities EventasaurusDiscovery.Sources.Repertuary.Cities.all()
                     |> Enum.map(fn {key, config} -> {config.name, key} end)
                     |> Enum.sort_by(fn {name, _key} -> name end)

  @impl true
  def mount(%{"slug" => city_slug}, _session, socket) do
    city = Repo.get_by!(City, slug: city_slug) |> Repo.preload(:country)

    # Subscribe to discovery progress updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "discovery_progress")
    end

    socket =
      socket
      |> assign(:page_title, "Configure #{city.name}")
      |> assign(:city, city)
      |> assign(:available_sources, DiscoveryConfig.valid_source_names())
      |> assign(:show_add_source_modal, false)
      |> assign(:selected_source, nil)
      |> assign(:source_settings, %{})
      |> assign(:editing_source, false)
      |> assign(:loading_stats, true)
      |> assign(:stats_error, nil)
      |> load_stats()

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    cities = Repo.replica().all(from(c in City, order_by: c.name, preload: :country))

    socket =
      socket
      |> assign(:page_title, "City Discovery Configuration")
      |> assign(:cities, cities)
      |> assign(:selected_city, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("enable_discovery", %{"city_id" => city_id}, socket) do
    case parse_city_id(city_id) do
      {:ok, city_id} ->
        case DiscoveryConfigManager.enable_city(city_id) do
          {:ok, _city} ->
            city = Repo.get!(City, city_id) |> Repo.preload(:country)

            socket =
              socket
              |> put_flash(:info, "Discovery enabled for #{city.name}")
              |> assign(:city, city)
              |> load_stats()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to enable discovery: #{inspect(reason)}")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid city id")}
    end
  end

  @impl true
  def handle_event("disable_discovery", %{"city_id" => city_id}, socket) do
    case parse_city_id(city_id) do
      {:ok, city_id} ->
        case DiscoveryConfigManager.disable_city(city_id) do
          {:ok, _city} ->
            city = Repo.get!(City, city_id) |> Repo.preload(:country)

            socket =
              socket
              |> put_flash(:info, "Discovery disabled for #{city.name}")
              |> assign(:city, city)
              |> load_stats()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to disable discovery: #{inspect(reason)}")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid city id")}
    end
  end

  @impl true
  def handle_event("show_add_source", _params, socket) do
    {:noreply, assign(socket, :show_add_source_modal, true)}
  end

  @impl true
  def handle_event("hide_add_source", _params, socket) do
    socket =
      socket
      |> assign(:show_add_source_modal, false)
      |> assign(:selected_source, nil)
      |> assign(:source_settings, %{})
      |> assign(:editing_source, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("form_change", params, socket) do
    source = params["source"]
    editing = socket.assigns.editing_source

    socket =
      if !editing and source != "" and source != socket.assigns.selected_source do
        # Switching to a new source - load default settings
        default_settings = get_default_settings(source)

        socket
        |> assign(:selected_source, source)
        |> assign(:source_settings, default_settings)
      else
        # Update settings from form (either editing existing source or updating new source settings)
        updated_settings =
          Enum.reduce(params, socket.assigns.source_settings, fn
            {"setting_" <> key, value}, acc ->
              Map.put(acc, key, parse_setting_value(value))

            _, acc ->
              acc
          end)

        assign(socket, :source_settings, updated_settings)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_source", %{"city_id" => city_id}, socket) do
    case parse_city_id(city_id) do
      {:ok, city_id} ->
        source_name = socket.assigns.selected_source
        settings = socket.assigns.source_settings
        editing = socket.assigns.editing_source

        result =
          if editing do
            DiscoveryConfigManager.update_source_settings(city_id, source_name, settings)
          else
            DiscoveryConfigManager.enable_source(city_id, source_name, settings)
          end

        case result do
          {:ok, _city} ->
            city = Repo.get!(City, city_id) |> Repo.preload(:country)
            action = if editing, do: "updated", else: "added"

            socket =
              socket
              |> put_flash(:info, "Successfully #{action} #{source_name} source")
              |> assign(:city, city)
              |> assign(:show_add_source_modal, false)
              |> assign(:selected_source, nil)
              |> assign(:source_settings, %{})
              |> assign(:editing_source, false)
              |> load_stats()

            {:noreply, socket}

          {:error, reason} ->
            action = if editing, do: "update", else: "add"

            {:noreply,
             put_flash(socket, :error, "Failed to #{action} source: #{inspect(reason)}")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid city id")}
    end
  end

  @impl true
  def handle_event("show_edit_source", %{"source" => source_name}, socket) do
    city = socket.assigns.city
    config = normalize_config(city.discovery_config)
    sources = Map.get(config, "sources", [])
    source = Enum.find(sources, &(&1["name"] == source_name))

    if source do
      stored_settings = source["settings"] || %{}
      # Merge default settings with stored settings so new fields appear
      default_settings = get_default_settings(source_name)
      settings = Map.merge(default_settings, stringify_keys(stored_settings))

      socket =
        socket
        |> assign(:show_add_source_modal, true)
        |> assign(:selected_source, source_name)
        |> assign(:source_settings, settings)
        |> assign(:editing_source, true)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Source not found")}
    end
  end

  @impl true
  def handle_event("toggle_source", %{"city_id" => city_id, "source" => source_name}, socket) do
    case parse_city_id(city_id) do
      {:ok, city_id} ->
        # Reload city from database to get fresh data
        city = Repo.get!(City, city_id) |> Repo.preload(:country)
        config = normalize_config(city.discovery_config)
        sources = Map.get(config, "sources", [])
        source = Enum.find(sources, &(&1["name"] == source_name))

        result =
          if source && source["enabled"] do
            DiscoveryConfigManager.disable_source(city_id, source_name)
          else
            # Re-enable with existing settings
            settings = (source && source["settings"]) || %{}
            DiscoveryConfigManager.enable_source(city_id, source_name, settings)
          end

        case result do
          {:ok, _city} ->
            city = Repo.get!(City, city_id) |> Repo.preload(:country)
            action = if source && source["enabled"], do: "disabled", else: "enabled"

            socket =
              socket
              |> put_flash(:info, "Source #{source_name} #{action}")
              |> assign(:city, city)
              |> load_stats()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to toggle source: #{inspect(reason)}")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid city id")}
    end
  end

  @impl true
  def handle_event("delete_source", %{"city_id" => city_id, "source" => source_name}, socket) do
    case parse_city_id(city_id) do
      {:ok, city_id} ->
        case DiscoveryConfigManager.delete_source(city_id, source_name) do
          {:ok, _city} ->
            city = Repo.get!(City, city_id) |> Repo.preload(:country)

            socket =
              socket
              |> put_flash(:info, "Successfully deleted #{source_name} source")
              |> assign(:city, city)
              |> load_stats()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete source: #{inspect(reason)}")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid city id")}
    end
  end

  @impl true
  def handle_info({:discovery_progress, %{city_id: city_id, status: _status}}, socket) do
    # Only refresh if this is the city we're viewing
    if socket.assigns[:city] && socket.assigns.city.id == city_id do
      # Reload city data and stats
      city = Repo.get!(City, city_id) |> Repo.preload(:country)

      socket =
        socket
        |> assign(:city, city)
        |> load_stats()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Catch-all for other messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Private helper functions

  defp load_stats(socket) do
    city = socket.assigns[:city]

    if city do
      try do
        config = normalize_config(city.discovery_config)
        sources = Map.get(config, "sources", [])
        source_names = Enum.map(sources, & &1["name"])

        # Get real-time stats from Oban with batched queries
        stats = DiscoveryStatsCollector.get_all_source_stats(city.id, source_names)

        socket
        |> assign(:source_stats, stats)
        |> assign(:loading_stats, false)
        |> assign(:stats_error, nil)
      rescue
        error ->
          Logger.error("Failed to load discovery stats: #{inspect(error)}")

          socket
          |> assign(:source_stats, %{})
          |> assign(:loading_stats, false)
          |> assign(:stats_error, "Failed to load statistics. Please refresh the page.")
      end
    else
      socket
      |> assign(:source_stats, %{})
      |> assign(:loading_stats, false)
      |> assign(:stats_error, nil)
    end
  end

  defp get_default_settings("bandsintown"), do: %{"limit" => 100, "radius" => 50}
  defp get_default_settings("ticketmaster"), do: %{"limit" => 100, "radius" => 50}
  defp get_default_settings("resident-advisor"), do: %{"limit" => 100, "area_id" => nil}
  defp get_default_settings("karnet"), do: %{"limit" => 100, "max_pages" => 10}
  defp get_default_settings("repertuary"), do: %{"limit" => 100, "city_key" => nil}
  defp get_default_settings("cinema-city"), do: %{"limit" => 100, "city_name" => nil}
  defp get_default_settings("pubquiz-pl"), do: %{"limit" => 100}
  defp get_default_settings("question-one"), do: %{"limit" => 100}
  defp get_default_settings("geeks-who-drink"), do: %{"limit" => 100}
  defp get_default_settings(_), do: %{"limit" => 100}

  defp parse_setting_value(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> value
    end
  end

  defp format_datetime(nil), do: "Never"

  defp format_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %Y %H:%M")
      _ -> "Invalid date"
    end
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end

  defp format_datetime(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%b %d, %Y %H:%M")
  end

  defp source_icon("bandsintown"), do: "🎵"
  defp source_icon("ticketmaster"), do: "🎫"
  defp source_icon("resident-advisor"), do: "🎧"
  defp source_icon("karnet"), do: "🎭"
  defp source_icon("repertuary"), do: "🎬"
  defp source_icon("cinema-city"), do: "🍿"
  defp source_icon("pubquiz-pl"), do: "🧠"
  defp source_icon("question-one"), do: "❓"
  defp source_icon("geeks-who-drink"), do: "🍺"
  defp source_icon(_), do: "📅"

  defp parse_city_id(city_id) when is_integer(city_id), do: {:ok, city_id}

  defp parse_city_id(city_id) when is_binary(city_id) do
    case Integer.parse(city_id) do
      {id, _} -> {:ok, id}
      :error -> :error
    end
  end

  defp parse_city_id(_), do: :error

  defp normalize_config(nil), do: %{}

  defp normalize_config(config) when is_struct(config) do
    config
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp normalize_config(config) when is_map(config), do: config

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  # Expose Cinema City cities for dropdown in template
  def cinema_city_cities, do: @cinema_city_cities

  # Expose Resident Advisor areas for dropdown in template
  @spec resident_advisor_areas() :: [{String.t(), integer()}]
  def resident_advisor_areas, do: @resident_advisor_areas

  # Expose Repertuary cities for dropdown in template
  @spec repertuary_cities() :: [{String.t(), atom()}]
  def repertuary_cities, do: @repertuary_cities
end
