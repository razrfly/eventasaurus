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

    # Determine locales based on country
    locales = determine_locales(city, options)

    Logger.info("""
    🎫 Fetching Ticketmaster events
    City: #{city.name}, #{city.country.name}
    Coordinates: (#{city.latitude}, #{city.longitude})
    Radius: #{radius}km
    Locales: #{inspect(locales)}
    Max pages: #{max_pages}
    Target events: #{limit}
    """)

    # Fetch events for each locale and combine results
    # We need to keep all versions to get translations in different languages
    all_events =
      locales
      |> Enum.flat_map(fn locale ->
        Logger.info("🌐 Fetching events with locale: #{locale}")

        case fetch_all_pages(city, radius, max_pages, limit, locale) do
          {:ok, events} ->
            # Tag each event with its locale for transformation
            Enum.map(events, &Map.put(&1, "_locale", locale))
          {:error, reason} ->
            Logger.warning("Failed to fetch events for locale #{locale}: #{inspect(reason)}")
            []
        end
      end)
      # Don't deduplicate here - we want all language versions!
      # The EventProcessor will merge translations for the same external_id
      |> Enum.take(limit * length(locales))  # Take more since we have duplicates

    {:ok, all_events}
  end

  defp determine_locales(city, options) do
    # Check if locale was explicitly provided
    case options["locale"] || options[:locale] do
      nil ->
        # No explicit locale, use country-based detection with safe fallback
        case Config.country_locales(city.country.code) do
          locales when is_list(locales) and locales != [] -> locales
          _ -> ["en-us"]  # safe fallback if country detection fails
        end
      locale ->
        # Explicit locale provided, use only that one
        [locale]
    end
  end


  # Keep @impl on the 1-arity variant to satisfy BaseJob behaviour
  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    transform_events(raw_events, %{})
  end

  def transform_events(raw_events, options) do
    # Extract city context from options (passed by BaseJob)
    city = options["city"]

    # Transform each event using our Transformer
    # Each event has its locale tagged in "_locale" field
    raw_events
    |> Enum.flat_map(fn raw_event ->
      # Extract the locale that was tagged on this event
      locale = Map.get(raw_event, "_locale")
      # Remove the temporary locale tag before transformation
      event_data = Map.delete(raw_event, "_locale")

      case Transformer.transform_event(event_data, locale, city) do
        {:ok, event} ->
          [event]
        {:error, reason} ->
          Logger.debug("Ticketmaster event transformation failed: #{reason}")
          []
      end
    end)
  end

  # Override the helper from BaseJob to use our version with options
  defp transform_events_with_options(raw_events, options) do
    transform_events(raw_events, options)
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

  defp fetch_all_pages(city, radius, max_pages, target_limit, locale) do
    fetch_pages_recursive(city, radius, 0, max_pages, [], target_limit, locale)
  end

  defp fetch_pages_recursive(_city, _radius, page, max_pages, events, _limit, _locale)
       when page >= max_pages do
    {:ok, events}
  end

  defp fetch_pages_recursive(_city, _radius, _page, _max_pages, events, limit, _locale)
       when length(events) >= limit do
    {:ok, Enum.take(events, limit)}
  end

  defp fetch_pages_recursive(city, radius, page, max_pages, accumulated_events, limit, locale) do
    case Client.fetch_events_by_location(city.latitude, city.longitude, radius, page, locale) do
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
          fetch_pages_recursive(city, radius, page + 1, max_pages, all_events, limit, locale)
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
