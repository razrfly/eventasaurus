defmodule EventasaurusDiscovery.Sources.Ticketmaster.Config do
  @moduledoc """
  Configuration for Ticketmaster Discovery API using unified source structure.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://app.ticketmaster.com/discovery/v2"
  @default_radius 50
  @default_page_size 100
  # Job staggering delay (seconds between scheduled jobs)
  @rate_limit 2

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Ticketmaster Discovery API",
      slug: "ticketmaster",
      # Highest priority - authoritative source
      priority: 100,
      # requests per second
      rate_limit: 5,
      timeout: 10_000,
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      api_key: api_key(),
      api_secret: api_secret()
    })
  end

  def base_url, do: @base_url
  def default_radius, do: @default_radius
  def default_page_size, do: @default_page_size
  def rate_limit, do: @rate_limit

  @doc """
  Returns the appropriate Ticketmaster locales for a given country.
  Uses the Countries library to detect official languages.
  Always includes English as international fallback unless English is already the primary language.
  """
  def country_locales(country_code) when is_binary(country_code) do
    case Countries.get(country_code) do
      nil ->
        # Country not found, default to English
        ["en-us"]

      country ->
        # Get official languages from the country data
        languages =
          case country.languages_official do
            nil ->
              []

            langs when is_binary(langs) ->
              # Split by comma if multiple languages
              langs
              |> String.split(",")
              |> Enum.map(&String.trim/1)

            _ ->
              []
          end

        # Convert language codes to Ticketmaster locale format
        locales =
          languages
          |> Enum.map(&language_to_locale(&1, country.alpha2))
          |> Enum.reject(&is_nil/1)

        # Add English if it's not already included
        if Enum.any?(locales, &String.starts_with?(&1, "en-")) do
          locales
        else
          locales ++ ["en-us"]
        end
    end
  end

  def country_locales(_), do: ["en-us"]

  # Convert ISO 639-1 language codes to Ticketmaster locale format
  defp language_to_locale(lang_code, country_code) do
    lang = String.downcase(lang_code)
    country = String.downcase(country_code)

    # Build the locale string (e.g., "pl-pl", "en-us")
    "#{lang}-#{country}"
  end

  def api_key do
    System.get_env("TICKETMASTER_CONSUMER_KEY") ||
      get_in(Application.get_env(:eventasaurus, :ticketmaster, []), [:api_key])
  end

  def api_secret do
    System.get_env("TICKETMASTER_CONSUMER_SECRET") ||
      get_in(Application.get_env(:eventasaurus, :ticketmaster, []), [:api_secret])
  end

  def build_url(endpoint) do
    "#{@base_url}#{endpoint}"
  end

  def default_params(opts \\ []) do
    base_params = %{
      apikey: api_key(),
      size: @default_page_size,
      sort: "date,asc",
      includeTest: "no",
      # Include embedded resources for complete event data
      includeLicensedContent: "yes"
    }

    # Add locale if provided
    case Keyword.get(opts, :locale) do
      nil -> base_params
      locale -> Map.put(base_params, :locale, locale)
    end
  end
end
