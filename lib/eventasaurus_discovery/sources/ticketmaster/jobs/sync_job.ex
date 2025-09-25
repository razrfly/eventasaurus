defmodule EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing Ticketmaster events.

  Uses the standardized BaseJob behaviour for consistent processing across all sources.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger
  alias EventasaurusDiscovery.Sources.Ticketmaster.{Config, Client, Transformer}

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, options) do
    radius = options["radius"] || options[:radius] || Config.default_radius()
    max_pages = calculate_max_pages(limit)

    Logger.info("""
    🎫 Fetching Ticketmaster events
    City: #{city.name}, #{city.country.name}
    Coordinates: (#{city.latitude}, #{city.longitude})
    Radius: #{radius}km
    Max pages: #{max_pages}
    Target events: #{limit}
    """)

    fetch_all_pages(city, radius, max_pages, limit)
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Transform each event using our Transformer
    # Filter out events that fail venue validation
    raw_events
    |> Enum.flat_map(fn raw_event ->
      case Transformer.transform_event(raw_event) do
        {:ok, event} ->
          [event]
        {:error, reason} ->
          Logger.debug("Ticketmaster event transformation failed: #{reason}")
          []
      end
    end)
  end

  def source_config do
    Config.source_config()
  end

  # Private functions

  defp calculate_max_pages(limit) do
    # Each page returns up to 100 events
    pages = div(limit, Config.default_page_size())
    if rem(limit, Config.default_page_size()) > 0, do: pages + 1, else: pages
  end

  defp fetch_all_pages(city, radius, max_pages, target_limit) do
    fetch_pages_recursive(city, radius, 0, max_pages, [], target_limit)
  end

  defp fetch_pages_recursive(_city, _radius, page, max_pages, events, _limit)
       when page >= max_pages do
    {:ok, events}
  end

  defp fetch_pages_recursive(_city, _radius, _page, _max_pages, events, limit)
       when length(events) >= limit do
    {:ok, Enum.take(events, limit)}
  end

  defp fetch_pages_recursive(city, radius, page, max_pages, accumulated_events, limit) do
    case Client.fetch_events_by_location(city.latitude, city.longitude, radius, page) do
      {:ok, %{"_embedded" => %{"events" => page_events}}} when is_list(page_events) ->
        all_events = accumulated_events ++ page_events

        if length(all_events) >= limit do
          {:ok, Enum.take(all_events, limit)}
        else
          # Rate limiting with safety checks
          rate_limit = max(Config.source_config().rate_limit, 1)
          # Minimum 100ms between requests
          sleep_ms = max(div(1000, rate_limit), 100)
          Process.sleep(sleep_ms)
          fetch_pages_recursive(city, radius, page + 1, max_pages, all_events, limit)
        end

      {:ok, _} ->
        # No more events
        {:ok, accumulated_events}

      {:error, reason} = error ->
        if page == 0 do
          # First page failed, return error
          error
        else
          # Subsequent page failed, return what we have
          Logger.warning("Failed to fetch page #{page}: #{inspect(reason)}")
          {:ok, accumulated_events}
        end
    end
  end
end
