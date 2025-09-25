defmodule EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing BandsInTown events.

  Uses the standardized BaseJob behaviour for consistent processing across all sources.
  All events are processed through the unified Processor which enforces venue requirements.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.Bandsintown.{Config, Transformer}
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, _options) do
    Logger.info("""
    🎵 Fetching Bandsintown events
    City: #{city.name}, #{city.country.name}
    Target events: #{limit}
    """)

    # Use the API-based approach with coordinates (the original working method)
    latitude = Decimal.to_float(city.latitude)
    longitude = Decimal.to_float(city.longitude)
    city_slug = build_bandsintown_slug(city)
    max_pages = calculate_max_pages(limit)

    # Fetch events using the API (not Playwright)
    with {:ok, events} <- Client.fetch_all_city_events(latitude, longitude, city_slug, max_pages: max_pages) do
      # Limit events
      limited_events = Enum.take(events, limit)

      # The events from the API already have the data we need
      # No need to fetch additional details since the API provides complete info
      {:ok, limited_events}
    else
      {:error, reason} = error ->
        Logger.error("Failed to fetch Bandsintown events: #{inspect(reason)}")
        error
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Transform each event using our Transformer
    # Filter out events that fail venue validation
    raw_events
    |> Enum.map(&Transformer.transform_event/1)
    |> Enum.filter(fn
      {:ok, _event} -> true
      {:error, _reason} -> false
    end)
    |> Enum.map(fn {:ok, event} -> event end)
  end

  # Required by BaseJob for source configuration
  def source_config do
    Config.source_config()
  end

  # Private helper functions

  defp calculate_max_pages(limit) do
    # Estimate pages based on ~20 events per page
    pages = div(limit, 20)
    if rem(limit, 20) > 0, do: pages + 1, else: pages
  end

  defp build_bandsintown_slug(city) do
    # Convert city name to URL-friendly format
    city_part =
      city.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")

    # For US cities, try to use state code
    if city.country.code == "US" && city.state_code do
      "#{city_part}-#{String.downcase(city.state_code)}"
    else
      # For non-US, use country
      country_part =
        city.country.name
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9\s-]/, "")
        |> String.replace(~r/\s+/, "-")

      "#{city_part}-#{country_part}"
    end
  end
end
