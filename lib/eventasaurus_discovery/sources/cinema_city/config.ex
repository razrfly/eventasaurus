defmodule EventasaurusDiscovery.Sources.CinemaCity.Config do
  @moduledoc """
  Configuration for Cinema City API scraper.

  Cinema City provides a public JSON API for cinema listings and showtimes
  across Poland. This configuration defines API endpoints and scraper settings.
  """

  @site_id "10103"

  def base_url, do: "https://www.cinema-city.pl"

  def api_base_url, do: "#{base_url()}/pl/data-api-service/v1"

  @doc """
  Cinema list endpoint - returns all Cinema City locations with events until the specified date.

  ## Example
      cinema_list_url("2025-10-10")
      # => "https://www.cinema-city.pl/pl/data-api-service/v1/quickbook/10103/cinemas/with-event/until/2025-10-10"
  """
  def cinema_list_url(until_date) do
    "#{api_base_url()}/quickbook/#{@site_id}/cinemas/with-event/until/#{until_date}"
  end

  @doc """
  Film events endpoint - returns all movies and showtimes for a specific cinema on a specific date.

  ## Example
      film_events_url("1088", "2025-10-03")
      # => "https://www.cinema-city.pl/pl/data-api-service/v1/quickbook/10103/film-events/in-cinema/1088/at-date/2025-10-03"
  """
  def film_events_url(cinema_id, date) do
    "#{api_base_url()}/quickbook/#{@site_id}/film-events/in-cinema/#{cinema_id}/at-date/#{date}"
  end

  @doc """
  Cinema detail page URL (for reference/linking).

  ## Example
      cinema_url("krakow-bonarka")
      # => "https://www.cinema-city.pl/krakow-bonarka"
  """
  def cinema_url(cinema_slug) do
    "#{base_url()}/#{cinema_slug}"
  end

  # Site ID for Cinema City Poland
  def site_id, do: @site_id

  # Rate limiting in seconds (conservative for undocumented API)
  def rate_limit, do: 2

  # HTTP timeout (API is usually fast)
  def timeout, do: 10_000

  # Maximum retries for failed requests
  def max_retries, do: 3

  # Number of days ahead to fetch showtimes
  # Cinema City typically publishes 7-14 days ahead
  def days_ahead, do: 7

  # Target cities for initial implementation
  # Can be expanded to other Polish cities in the future
  def target_cities, do: Application.get_env(:eventasaurus_discovery, :cinema_city_cities, ["Kraków"])

  # HTTP headers for API requests
  def headers do
    [
      {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
      {"Accept", "application/json"},
      {"Accept-Language", "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7"}
    ]
  end

  @doc """
  Known Cinema City locations in Kraków.
  This is for reference/validation - actual data comes from API.
  """
  def krakow_cinemas do
    [
      %{id: "1088", name: "Kraków - Bonarka", slug: "krakow-bonarka"},
      %{id: "1089", name: "Kraków - Galeria Kazimierz", slug: "krakow-galeria-kazimierz"},
      %{id: "1090", name: "Kraków - Zakopianka", slug: "krakow-zakopianka"}
    ]
  end
end
