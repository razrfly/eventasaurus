defmodule EventasaurusDiscovery.Sources.Repertuary.Config do
  @moduledoc """
  Configuration for the Repertuary.pl cinema network scraper.

  This module provides configuration for scraping cinema showtimes from the
  repertuary.pl network, which covers 29+ Polish cities. All URL functions
  now accept an optional city parameter, defaulting to "krakow" for backward
  compatibility.

  ## Usage

      # Default (Krakow)
      Config.base_url()
      # => "https://www.kino.krakow.pl"

      # Specific city
      Config.base_url("warszawa")
      # => "https://warszawa.repertuary.pl"

  See `EventasaurusDiscovery.Sources.Repertuary.Cities` for all available cities.

  ## Deduplication Strategy

  Uses `:cross_source_fuzzy` - Cross-source matching for cinema showtimes
  using movie title, venue, and date. May overlap with Cinema City and
  other cinema sources.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  alias EventasaurusDiscovery.Sources.Repertuary.Cities

  @default_city "krakow"

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Repertuary.pl",
      slug: "repertuary",
      priority: 55,
      rate_limit: 2,
      timeout: 30_000,
      max_retries: 3,
      queue: :discovery,
      base_url: base_url(),
      api_key: nil,
      api_secret: nil
    })
  end

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def dedup_strategy, do: :cross_source_fuzzy

  @doc """
  Get the base URL for a city.

  Defaults to Krakow for backward compatibility.

  ## Examples

      iex> Config.base_url()
      "https://www.kino.krakow.pl"

      iex> Config.base_url("warszawa")
      "https://warszawa.repertuary.pl"
  """
  def base_url(city \\ @default_city) do
    Cities.base_url(city) || Cities.base_url(@default_city)
  end

  @doc """
  Get the showtimes listing URL for a city.
  """
  def showtimes_url(city \\ @default_city) do
    "#{base_url(city)}/cinema_program/by_movie"
  end

  @doc """
  Get the cinema info URL for a city.
  """
  def cinema_info_url(cinema_slug, city \\ @default_city) do
    "#{base_url(city)}/#{cinema_slug}/info"
  end

  @doc """
  Get the movie detail URL for a city.
  """
  def movie_detail_url(movie_slug, city \\ @default_city) do
    "#{base_url(city)}/film/#{movie_slug}.html"
  end

  @doc """
  Get the city configuration map.
  """
  def city_config(city \\ @default_city) do
    Cities.get(city)
  end

  @doc """
  Get the source slug for a city.
  """
  def source_slug(city \\ @default_city) do
    Cities.source_slug(city)
  end

  @doc """
  Get the display name for a city.
  """
  def city_name(city \\ @default_city) do
    Cities.display_name(city)
  end

  @doc """
  Get the default city key.
  """
  def default_city, do: @default_city

  # Rate limiting in seconds (be respectful)
  def rate_limit, do: 2

  # Maximum pages to scrape (if pagination exists)
  def max_pages, do: 1

  # HTTP timeout
  def timeout, do: 30_000

  # User agent
  def user_agent,
    do: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
end
