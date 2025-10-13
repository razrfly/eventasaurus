defmodule EventasaurusDiscovery.Helpers.TimezoneMapper do
  @moduledoc """
  Maps countries to their primary IANA timezone.

  For countries with multiple timezones, uses the most populous/common timezone.
  For precise timezone detection, use geocoding services with venue coordinates.
  """

  # Map of country codes to primary IANA timezone
  # Source: IANA timezone database via TimeZoneInfo library
  @country_timezones %{
    # Europe
    "GB" => "Europe/London",
    "PL" => "Europe/Warsaw",
    "DE" => "Europe/Berlin",
    "FR" => "Europe/Paris",
    "IT" => "Europe/Rome",
    "ES" => "Europe/Madrid",
    "NL" => "Europe/Amsterdam",
    "BE" => "Europe/Brussels",
    "CH" => "Europe/Zurich",
    "AT" => "Europe/Vienna",
    "CZ" => "Europe/Prague",
    "SE" => "Europe/Stockholm",
    "NO" => "Europe/Oslo",
    "DK" => "Europe/Copenhagen",
    "FI" => "Europe/Helsinki",
    "IE" => "Europe/Dublin",
    "PT" => "Europe/Lisbon",
    "GR" => "Europe/Athens",
    "RU" => "Europe/Moscow",
    "TR" => "Europe/Istanbul",
    "UA" => "Europe/Kiev",

    # Americas (using most populous timezone for multi-TZ countries)
    # Eastern time (most populous)
    "US" => "America/New_York",
    # Eastern time (most populous)
    "CA" => "America/Toronto",
    "MX" => "America/Mexico_City",
    "BR" => "America/Sao_Paulo",
    "AR" => "America/Argentina/Buenos_Aires",
    "CL" => "America/Santiago",
    "CO" => "America/Bogota",
    "PE" => "America/Lima",

    # Asia
    "JP" => "Asia/Tokyo",
    "CN" => "Asia/Shanghai",
    "IN" => "Asia/Kolkata",
    "KR" => "Asia/Seoul",
    "TH" => "Asia/Bangkok",
    "SG" => "Asia/Singapore",
    "MY" => "Asia/Kuala_Lumpur",
    "PH" => "Asia/Manila",
    "ID" => "Asia/Jakarta",
    "VN" => "Asia/Ho_Chi_Minh",
    "TW" => "Asia/Taipei",
    "HK" => "Asia/Hong_Kong",
    "AE" => "Asia/Dubai",

    # Oceania
    # Eastern time (most populous)
    "AU" => "Australia/Sydney",
    "NZ" => "Pacific/Auckland",

    # Africa
    "ZA" => "Africa/Johannesburg",
    "EG" => "Africa/Cairo",
    "NG" => "Africa/Lagos",
    "KE" => "Africa/Nairobi",
    "MA" => "Africa/Casablanca"
  }

  @doc """
  Get the primary timezone for a country code.
  Returns IANA timezone string (e.g., "Europe/London")
  Falls back to UTC if country not found.

  ## Examples

      iex> get_timezone_for_country("GB")
      "Europe/London"

      iex> get_timezone_for_country("PL")
      "Europe/Warsaw"

      iex> get_timezone_for_country("XX")
      "Etc/UTC"
  """
  def get_timezone_for_country(country_code) when is_binary(country_code) do
    Map.get(@country_timezones, String.upcase(country_code), "Etc/UTC")
  end

  def get_timezone_for_country(_), do: "Etc/UTC"

  @doc """
  Get timezone from a venue struct.
  Extracts country code from venue → city → country hierarchy.

  ## Examples

      iex> venue = %{city_ref: %{country: %{code: "GB"}}}
      iex> get_timezone_for_venue(venue)
      "Europe/London"
  """
  def get_timezone_for_venue(%{city_ref: %{country: %{code: country_code}}}) do
    get_timezone_for_country(country_code)
  end

  def get_timezone_for_venue(_), do: "Etc/UTC"

  @doc """
  Get timezone from a city struct.
  Extracts country code from city → country hierarchy.
  """
  def get_timezone_for_city(%{country: %{code: country_code}}) do
    get_timezone_for_country(country_code)
  end

  def get_timezone_for_city(_), do: "Etc/UTC"
end
