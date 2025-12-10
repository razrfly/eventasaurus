defmodule EventasaurusDiscovery.Sources.Repertuary.Cities do
  @moduledoc """
  City configuration for the Repertuary.pl cinema network.

  This module defines all supported cities across the repertuary.pl network.
  Each city has its own subdomain (e.g., warszawa.repertuary.pl) except for
  Krakow which uses the legacy branded domain (kino.krakow.pl).

  ## Architecture Note (Cinema City Pattern)

  All cities share a SINGLE source record with slug "repertuary".
  The city is passed via job args, not used for source lookup.
  The `slug` field in city configs is DEPRECATED and kept only for
  backwards compatibility with existing code references.

  ## Usage

      iex> Cities.get("warszawa")
      %{name: "Warszawa", base_url: "https://warszawa.repertuary.pl", ...}

      iex> Cities.enabled()
      [%{key: "krakow", ...}, %{key: "warszawa", ...}]

  ## Adding New Cities

  To enable a new city:
  1. Ensure it's defined in @cities below
  2. Add the city key to the :repertuary_enabled_cities config
  3. Configure the city in Admin UI discovery settings with city_key
  """

  @cities %{
    # Legacy branded domain - Krakow uses different URL pattern
    "krakow" => %{
      name: "Kraków",
      slug: "repertuary-krakow",
      base_url: "https://www.kino.krakow.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    # Warsaw - primary expansion target
    "warszawa" => %{
      name: "Warszawa",
      slug: "repertuary-warszawa",
      base_url: "https://warszawa.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    # Major Polish cities
    "gdansk" => %{
      name: "Gdańsk",
      slug: "repertuary-gdansk",
      base_url: "https://gdansk.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "wroclaw" => %{
      name: "Wrocław",
      slug: "repertuary-wroclaw",
      base_url: "https://wroclaw.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "poznan" => %{
      name: "Poznań",
      slug: "repertuary-poznan",
      base_url: "https://poznan.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "lodz" => %{
      name: "Łódź",
      slug: "repertuary-lodz",
      base_url: "https://lodz.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "katowice" => %{
      name: "Katowice",
      slug: "repertuary-katowice",
      base_url: "https://katowice.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "szczecin" => %{
      name: "Szczecin",
      slug: "repertuary-szczecin",
      base_url: "https://szczecin.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "lublin" => %{
      name: "Lublin",
      slug: "repertuary-lublin",
      base_url: "https://lublin.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "bialystok" => %{
      name: "Białystok",
      slug: "repertuary-bialystok",
      base_url: "https://bialystok.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "bydgoszcz" => %{
      name: "Bydgoszcz",
      slug: "repertuary-bydgoszcz",
      base_url: "https://bydgoszcz.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "kielce" => %{
      name: "Kielce",
      slug: "repertuary-kielce",
      base_url: "https://kielce.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "olsztyn" => %{
      name: "Olsztyn",
      slug: "repertuary-olsztyn",
      base_url: "https://olsztyn.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "rzeszow" => %{
      name: "Rzeszów",
      slug: "repertuary-rzeszow",
      base_url: "https://rzeszow.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "torun" => %{
      name: "Toruń",
      slug: "repertuary-torun",
      base_url: "https://torun.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "radom" => %{
      name: "Radom",
      slug: "repertuary-radom",
      base_url: "https://radom.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    # Tri-City area
    "gdynia" => %{
      name: "Gdynia",
      slug: "repertuary-gdynia",
      base_url: "https://gdynia.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "sopot" => %{
      name: "Sopot",
      slug: "repertuary-sopot",
      base_url: "https://sopot.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "trojmiasto" => %{
      name: "Trójmiasto",
      slug: "repertuary-trojmiasto",
      base_url: "https://trojmiasto.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    # Silesian region
    "bielsko-biala" => %{
      name: "Bielsko-Biała",
      slug: "repertuary-bielsko-biala",
      base_url: "https://bielsko-biala.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "bytom" => %{
      name: "Bytom",
      slug: "repertuary-bytom",
      base_url: "https://bytom.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "czestochowa" => %{
      name: "Częstochowa",
      slug: "repertuary-czestochowa",
      base_url: "https://czestochowa.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "dabrowa-gornicza" => %{
      name: "Dąbrowa Górnicza",
      slug: "repertuary-dabrowa-gornicza",
      base_url: "https://dabrowa-gornicza.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "gliwice" => %{
      name: "Gliwice",
      slug: "repertuary-gliwice",
      base_url: "https://gliwice.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "jaworzno" => %{
      name: "Jaworzno",
      slug: "repertuary-jaworzno",
      base_url: "https://jaworzno.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "ruda-slaska" => %{
      name: "Ruda Śląska",
      slug: "repertuary-ruda-slaska",
      base_url: "https://ruda-slaska.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "rybnik" => %{
      name: "Rybnik",
      slug: "repertuary-rybnik",
      base_url: "https://rybnik.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "sosnowiec" => %{
      name: "Sosnowiec",
      slug: "repertuary-sosnowiec",
      base_url: "https://sosnowiec.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    },
    "zabrze" => %{
      name: "Zabrze",
      slug: "repertuary-zabrze",
      base_url: "https://zabrze.repertuary.pl",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL"
    }
  }

  @doc """
  Get city configuration by key.

  ## Examples

      iex> Cities.get("warszawa")
      %{name: "Warszawa", slug: "repertuary-warszawa", ...}

      iex> Cities.get("invalid")
      nil
  """
  def get(city_key) when is_binary(city_key) do
    case Map.get(@cities, city_key) do
      nil -> nil
      config -> Map.put(config, :key, city_key)
    end
  end

  @doc """
  Get all city configurations.

  Returns a map of city_key => config.
  """
  def all do
    @cities
    |> Enum.map(fn {key, config} -> {key, Map.put(config, :key, key)} end)
    |> Map.new()
  end

  @doc """
  Get all city keys.
  """
  def keys, do: Map.keys(@cities)

  @doc """
  Get enabled cities based on application configuration.

  Configure enabled cities via:
      config :eventasaurus, :repertuary_enabled_cities, ["krakow", "warszawa"]

  Defaults to ["krakow"] for backward compatibility.
  """
  def enabled do
    enabled_keys = Application.get_env(:eventasaurus, :repertuary_enabled_cities, ["krakow"])

    enabled_keys
    |> Enum.map(&get/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Check if a city is enabled.
  """
  def enabled?(city_key) do
    enabled_keys = Application.get_env(:eventasaurus, :repertuary_enabled_cities, ["krakow"])
    city_key in enabled_keys
  end

  @doc """
  Get base URL for a city.
  """
  def base_url(city_key) do
    case get(city_key) do
      nil -> nil
      config -> config.base_url
    end
  end

  @doc """
  Get the source slug for a city.
  """
  def source_slug(city_key) do
    case get(city_key) do
      nil -> nil
      config -> config.slug
    end
  end

  @doc """
  Get the display name for a city.
  """
  def display_name(city_key) do
    case get(city_key) do
      nil -> nil
      config -> config.name
    end
  end

  @doc """
  Build the showtimes URL for a city.
  """
  def showtimes_url(city_key) do
    case base_url(city_key) do
      nil -> nil
      url -> "#{url}/cinema_program/by_movie"
    end
  end

  @doc """
  Build the movie detail URL for a city.
  """
  def movie_detail_url(city_key, movie_slug) do
    case base_url(city_key) do
      nil -> nil
      url -> "#{url}/film/#{movie_slug}.html"
    end
  end

  @doc """
  Build the cinema info URL for a city.
  """
  def cinema_info_url(city_key, cinema_slug) do
    case base_url(city_key) do
      nil -> nil
      url -> "#{url}/#{cinema_slug}/info"
    end
  end

  @doc """
  Get the default city key (for backward compatibility).
  """
  def default_city, do: "krakow"
end
