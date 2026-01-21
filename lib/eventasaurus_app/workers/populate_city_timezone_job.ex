defmodule EventasaurusApp.Workers.PopulateCityTimezoneJob do
  @moduledoc """
  Oban job to populate timezone for a single city.

  This job uses TzWorld to determine the timezone from coordinates,
  with country-level fallback for cities without coordinates.

  ## Usage

  Enqueue for a single city:

      %{city_id: 123}
      |> PopulateCityTimezoneJob.new()
      |> Oban.insert()

  Or use the release task to enqueue all cities:

      EventasaurusApp.ReleaseTasks.enqueue_timezone_jobs()
  """

  use Oban.Worker,
    queue: :timezone,
    max_attempts: 3,
    unique: [period: :timer.minutes(10), keys: [:city_id]]

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Helpers.TimezoneMapper

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_id" => city_id}}) do
    city =
      City
      |> Repo.get(city_id)
      |> Repo.preload(:country)

    case city do
      nil ->
        Logger.warning("[PopulateCityTimezoneJob] City #{city_id} not found")
        {:ok, :not_found}

      %{timezone: tz} when is_binary(tz) and tz != "" ->
        # Already has timezone, skip
        {:ok, :already_set}

      city ->
        case get_timezone_for_city(city) do
          {:ok, timezone, source} ->
            case update_city_timezone(city, timezone) do
              {:ok, _} ->
                Logger.info(
                  "[PopulateCityTimezoneJob] Set #{city.name} timezone to #{timezone} (#{source})"
                )

                {:ok, %{timezone: timezone, source: source}}

              {:error, changeset} ->
                Logger.error(
                  "[PopulateCityTimezoneJob] Failed to update #{city.name}: #{inspect(changeset.errors)}"
                )

                {:error, "Failed to update city"}
            end

          {:error, reason} ->
            Logger.warning(
              "[PopulateCityTimezoneJob] Could not determine timezone for #{city.name}: #{reason}"
            )

            {:ok, %{skipped: true, reason: reason}}
        end
    end
  end

  # 5 minute timeout - ETS backend needs time to warm up on first access
  @tzworld_timeout :timer.minutes(5)

  defp get_timezone_for_city(%{latitude: lat, longitude: lng} = city)
       when not is_nil(lat) and not is_nil(lng) do
    lat_float = to_float(lat)
    lng_float = to_float(lng)

    # Call TzWorld backend directly with extended timeout
    # The ETS backend can take a while to load data on first access
    point = %Geo.Point{coordinates: {lng_float, lat_float}}

    try do
      case GenServer.call(
             TzWorld.Backend.EtsWithIndexCache,
             {:timezone_at, point},
             @tzworld_timeout
           ) do
        {:ok, timezone} ->
          {:ok, timezone, :coordinates}

        {:error, :time_zone_not_found} ->
          get_timezone_from_country(city)

        {:error, reason} ->
          Logger.warning(
            "[PopulateCityTimezoneJob] TzWorld error for #{city.name}: #{inspect(reason)}, trying country fallback"
          )

          get_timezone_from_country(city)
      end
    catch
      :exit, {:timeout, _} ->
        Logger.warning(
          "[PopulateCityTimezoneJob] TzWorld timeout for #{city.name} after 5min, using country fallback"
        )

        get_timezone_from_country(city)

      :exit, reason ->
        Logger.warning(
          "[PopulateCityTimezoneJob] TzWorld exit for #{city.name}: #{inspect(reason)}, using country fallback"
        )

        get_timezone_from_country(city)
    end
  end

  defp get_timezone_for_city(city) do
    get_timezone_from_country(city)
  end

  defp get_timezone_from_country(%{country: %{code: code}}) when is_binary(code) do
    timezone = TimezoneMapper.get_timezone_for_country(code)

    if timezone == "Etc/UTC" do
      {:error, "No timezone mapping for country #{code}"}
    else
      {:ok, timezone, :country_fallback}
    end
  end

  defp get_timezone_from_country(_city) do
    {:error, "No coordinates and no country association"}
  end

  defp update_city_timezone(city, timezone) do
    city
    |> City.timezone_changeset(timezone)
    |> Repo.update()
  end

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
end
