defmodule EventasaurusDiscovery.Admin.SourceOptionsBuilder do
  @moduledoc """
  Builds source-specific options for discovery sync jobs.

  Extracts common logic for building job arguments from both manual
  dashboard triggers and automated cron orchestration.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Helpers.AreaMapper
  require Logger

  @doc """
  Build source-specific options for a discovery job.

  ## Parameters
    - `source_name` - Name of the source (e.g., "bandsintown", "resident-advisor")
    - `city` - City struct (preloaded with country)
    - `base_settings` - Base settings map from config or params

  ## Returns
    Map of options specific to the source
  """
  def build_options(source_name, city, base_settings \\ %{})

  def build_options("ticketmaster", _city, base_settings) do
    %{
      radius: base_settings["radius"] || base_settings[:radius] || 50
    }
  end

  def build_options("resident-advisor", city, base_settings) do
    # RA requires area_id mapping from city
    area_id =
      if city do
        case AreaMapper.get_area_id(city) do
          {:ok, area_id} ->
            Logger.info("✅ Found RA area_id #{area_id} for #{city.name}")
            area_id

          {:error, :area_not_found} ->
            Logger.warning("⚠️ No area_id mapping for #{city.name}, #{city.country.name}")
            base_settings["area_id"] || base_settings[:area_id]
        end
      else
        Logger.warning("⚠️ City not found, using area_id from settings")
        base_settings["area_id"] || base_settings[:area_id]
      end

    %{area_id: area_id}
  end

  def build_options("bandsintown", _city, base_settings) do
    %{
      limit: base_settings["limit"] || base_settings[:limit] || 100,
      radius: base_settings["radius"] || base_settings[:radius] || 50
    }
  end

  def build_options("karnet", _city, base_settings) do
    %{
      limit: base_settings["limit"] || base_settings[:limit] || 100,
      max_pages: base_settings["max_pages"] || base_settings[:max_pages] || 10
    }
  end

  def build_options("repertuary", _city, base_settings) do
    # city_key is the Repertuary city slug (e.g., "krakow", "warszawa")
    # used to construct the URL (e.g., "krakow" -> krakow.repertuary.pl)
    city_key = base_settings["city_key"] || base_settings[:city_key]

    if is_nil(city_key) do
      Logger.warning("⚠️ No city_key configured for repertuary source")
    end

    %{
      city_key: city_key,
      days_ahead: base_settings["days_ahead"] || base_settings[:days_ahead] || 14
    }
  end

  def build_options("cinema-city", _city, base_settings) do
    # city_name is the Polish city name as returned by Cinema City API
    # e.g., "Kraków", "Warszawa", "Wrocław"
    city_name = base_settings["city_name"] || base_settings[:city_name]

    if is_nil(city_name) do
      Logger.warning("⚠️ No city_name configured for cinema-city source")
    end

    %{
      city_name: city_name,
      days_ahead: base_settings["days_ahead"] || base_settings[:days_ahead] || 14
    }
  end

  def build_options("pubquiz-pl", _city, _base_settings) do
    # Country-wide source, no specific options needed
    %{}
  end

  # Fallback for unknown sources
  def build_options(_source_name, _city, _base_settings) do
    %{}
  end

  @doc """
  Build complete job arguments for a discovery sync job.

  ## Parameters
    - `source_name` - Name of the source
    - `city_id` - City ID (nil for country-wide sources)
    - `limit` - Event limit (default: 100)
    - `source_settings` - Source-specific settings from config

  ## Returns
    Map of job arguments ready for Oban
  """
  def build_job_args(source_name, city_id, limit \\ 100, source_settings \\ %{}) do
    base_args = %{
      "source" => source_name,
      "limit" => limit
    }

    # Add city_id if provided (not for country-wide sources)
    args_with_city =
      if city_id do
        Map.put(base_args, "city_id", city_id)
      else
        base_args
      end

    # Load city and build source-specific options
    city = if city_id, do: Repo.get(City, city_id) |> Repo.preload(:country)
    options = build_options(source_name, city, source_settings)

    # Add options if any
    if map_size(options) > 0 do
      Map.put(args_with_city, "options", options)
    else
      args_with_city
    end
  end

  @doc """
  Check if a source requires city context.

  Country-wide sources don't need a city_id.
  """
  def requires_city?(source_name) do
    source_name not in ["pubquiz-pl"]
  end
end
