defmodule EventasaurusDiscovery.Sources.KinoKrakow.Config do
  @moduledoc """
  Configuration for Kino Krakow cinema scraper.
  """

  def base_url, do: "https://www.kino.krakow.pl"

  def showtimes_url, do: "#{base_url()}/cinema_program/by_movie"

  def cinema_info_url(cinema_slug), do: "#{base_url()}/#{cinema_slug}/info"

  def movie_detail_url(movie_slug), do: "#{base_url()}/film/#{movie_slug}.html"

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
