defmodule EventasaurusApp.Venues.VenueSourceCache do
  @moduledoc """
  ETS-based cache for venue source validation.

  Caches the list of allowed venue sources (geocoding providers + base sources)
  to avoid database queries on every venue changeset validation.

  Cache is populated at application startup and refreshed when geocoding
  providers are added/updated/removed.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider
  import Ecto.Query
  require Logger

  @table_name :venue_cache
  @cache_key :allowed_sources

  @base_sources ["user", "scraper", "provided"]

  @doc """
  Initialize the cache with allowed sources from database.
  Called at application startup.
  """
  def init do
    refresh()
  end

  @doc """
  Get the list of allowed venue sources.
  Returns from ETS cache (no database query).
  """
  def get_allowed_sources do
    case :ets.lookup(@table_name, @cache_key) do
      [{@cache_key, sources}] ->
        sources

      [] ->
        # Cache not initialized, refresh it
        Logger.warning("VenueSourceCache not initialized, refreshing...")
        refresh()
    end
  end

  @doc """
  Refresh the cache with current geocoding providers from database.
  Should be called when geocoding providers are added/updated/removed.
  """
  def refresh do
    providers =
      Repo.all(from p in GeocodingProvider, select: p.name)

    allowed_sources = @base_sources ++ providers

    :ets.insert(@table_name, {@cache_key, allowed_sources})

    Logger.info(
      "VenueSourceCache refreshed: #{length(allowed_sources)} allowed sources (#{length(providers)} geocoding providers)"
    )

    allowed_sources
  end

  @doc """
  Check if a source is allowed without fetching the full list.
  """
  def source_allowed?(source) do
    source in get_allowed_sources()
  end
end
