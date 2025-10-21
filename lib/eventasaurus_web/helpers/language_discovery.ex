defmodule EventasaurusWeb.Helpers.LanguageDiscovery do
  @moduledoc """
  Dynamic language discovery based on country data and available translations.
  No hard-coded country-to-language mappings.

  This module determines what languages should be displayed based on:
  1. What languages are spoken in the country (from Countries library)
  2. What translations actually exist in the database
  3. Always includes English as a fallback
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query
  require Logger

  @doc """
  Get languages that should be displayed for a city.

  Returns intersection of:
  1. Languages spoken in the country (from Countries library)
  2. Languages with actual translations in database for city's activities
  3. Always includes English as fallback

  ## Examples

      iex> get_available_languages_for_city("paris")
      ["en", "fr"]  # French from country + translations exist, plus English

      iex> get_available_languages_for_city("london")
      ["en"]  # Only English needed

      iex> get_available_languages_for_city("unknown-city")
      ["en"]  # Falls back to English for unknown cities
  """
  def get_available_languages_for_city(nil), do: ["en"]
  def get_available_languages_for_city(""), do: ["en"]
  def get_available_languages_for_city(city_slug) when is_binary(city_slug) do
    with {:ok, city} <- get_city_with_country(city_slug),
         country_languages <- get_country_languages(city.country_code),
         db_languages <- get_db_languages_for_city(city.id) do
      # Intersection of country languages and DB languages, plus English
      (country_languages ++ db_languages ++ ["en"])
      |> Enum.uniq()
      |> Enum.sort()
    else
      {:error, :city_not_found} ->
        Logger.debug("City not found: #{city_slug}, falling back to English only")
        ["en"]

      error ->
        Logger.error("Error getting languages for city #{city_slug}: #{inspect(error)}")
        ["en"]
    end
  end

  @doc """
  Get languages available for a specific activity.

  Returns list of language codes that have translations for this activity.
  Always includes English as fallback.

  ## Examples

      iex> get_available_languages_for_activity(123)
      ["en", "fr"]  # Activity has French and English translations

      iex> get_available_languages_for_activity(999)
      ["en"]  # Activity not found or no translations
  """
  def get_available_languages_for_activity(activity_id) when is_integer(activity_id) do
    case Repo.get(PublicEvent, activity_id) do
      nil ->
        Logger.debug("Activity not found: #{activity_id}")
        ["en"]

      activity ->
        languages =
          if activity.title_translations && map_size(activity.title_translations) > 0 do
            activity.title_translations
            |> Map.keys()
            |> Enum.sort()
          else
            []
          end

        # Always include English
        (languages ++ ["en"])
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  @doc """
  Get all languages that should be shown on an activity page.

  Returns a map with:
  - `:available` - Languages with translations for this activity
  - `:unavailable` - Languages available in city but not for this activity
  - `:all` - All languages that should be shown (for rendering buttons)

  This allows the UI to show all city languages but gray out unavailable ones,
  giving users context about what's generally available vs. what's available
  for this specific activity.

  ## Examples

      iex> get_activity_language_context(123, "paris")
      %{
        available: ["en", "fr"],
        unavailable: [],
        all: ["en", "fr"]
      }

      iex> get_activity_language_context(456, "paris")
      %{
        available: ["en"],
        unavailable: ["fr"],
        all: ["en", "fr"]
      }
  """
  def get_activity_language_context(activity_id, city_slug)
      when is_integer(activity_id) and is_binary(city_slug) do
    city_languages = get_available_languages_for_city(city_slug)
    activity_languages = get_available_languages_for_activity(activity_id)

    %{
      available: activity_languages,
      unavailable: city_languages -- activity_languages,
      all: city_languages
    }
  end

  # Private helper functions

  defp get_city_with_country(city_slug) do
    query =
      from c in City,
        where: c.slug == ^city_slug,
        join: country in assoc(c, :country),
        select: %{id: c.id, name: c.name, country_code: country.code}

    case Repo.one(query) do
      nil -> {:error, :city_not_found}
      city -> {:ok, city}
    end
  end

  defp get_country_languages(country_code) do
    case Countries.get(country_code) do
      nil ->
        Logger.debug("Country not found: #{country_code}")
        []

      country ->
        # Get official and spoken languages from Countries library
        official = parse_languages(country.languages_official)
        spoken = parse_languages(country.languages_spoken)

        (official ++ spoken)
        |> Enum.uniq()
        |> Enum.map(&String.downcase/1)
    end
  end

  defp parse_languages(nil), do: []
  defp parse_languages(lang) when is_binary(lang), do: [lang]
  defp parse_languages(langs) when is_list(langs), do: langs

  defp get_db_languages_for_city(city_id) do
    # Query what translation languages actually exist for events in this city
    query =
      from pe in PublicEvent,
        join: v in assoc(pe, :venue),
        where: v.city_id == ^city_id,
        where: not is_nil(pe.title_translations),
        where: fragment("jsonb_typeof(?)", pe.title_translations) == "object",
        select: fragment("jsonb_object_keys(?)", pe.title_translations)

    query
    |> Repo.all()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  rescue
    error ->
      Logger.error("Error querying DB languages for city #{city_id}: #{inspect(error)}")
      []
  end
end
