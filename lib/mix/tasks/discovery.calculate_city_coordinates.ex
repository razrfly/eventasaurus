defmodule Mix.Tasks.Discovery.CalculateCityCoordinates do
  @moduledoc """
  Calculate coordinates for cities based on their venue locations.

  This task calculates the average latitude and longitude of all venues
  in each city and updates the city's coordinates accordingly.

  ## Usage

      # Calculate coordinates for all cities
      mix discovery.calculate_city_coordinates

      # Calculate coordinates for a specific city
      mix discovery.calculate_city_coordinates --city-id=123

      # Force recalculation even if recently updated
      mix discovery.calculate_city_coordinates --force

  ## Options

    * `--city-id` - Calculate coordinates for a specific city ID
    * `--force` - Force recalculation even if city was recently updated
  """

  use Mix.Task
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob

  require Logger

  @shortdoc "Calculate city coordinates from venue locations"

  def run(args) do
    Mix.Task.run("app.start")

    {parsed, _, _} = OptionParser.parse(args,
      strict: [
        city_id: :integer,
        force: :boolean
      ],
      aliases: [
        c: :city_id,
        f: :force
      ]
    )

    force = Keyword.get(parsed, :force, false)

    case Keyword.get(parsed, :city_id) do
      nil ->
        calculate_all_cities(force)
      city_id ->
        calculate_single_city(city_id, force)
    end
  end

  defp calculate_all_cities(force) do
    cities = Repo.all(from c in City, select: %{id: c.id, name: c.name})

    IO.puts("📍 Calculating coordinates for #{length(cities)} cities...")
    IO.puts("")

    scheduled_count = Enum.reduce(cities, 0, fn city, count ->
      case schedule_calculation(city.id, city.name, force) do
        :scheduled ->
          IO.write(".")
          count + 1
        :skipped ->
          IO.write("s")
          count
        :error ->
          IO.write("x")
          count
      end
    end)

    IO.puts("")
    IO.puts("")
    IO.puts("✅ Scheduled coordinate calculation for #{scheduled_count} cities")

    if scheduled_count < length(cities) do
      IO.puts("ℹ️  Some cities were skipped (recently updated) or had errors")
      IO.puts("   Use --force to recalculate all cities")
    end
  end

  defp calculate_single_city(city_id, force) do
    case Repo.get(City, city_id) do
      nil ->
        IO.puts("❌ City with ID #{city_id} not found")
      city ->
        IO.puts("📍 Calculating coordinates for #{city.name}...")

        case schedule_calculation(city_id, city.name, force) do
          :scheduled ->
            IO.puts("✅ Scheduled coordinate calculation for #{city.name}")
          :skipped ->
            IO.puts("ℹ️  Skipped - #{city.name} was recently updated")
            IO.puts("   Use --force to recalculate anyway")
          :error ->
            IO.puts("❌ Failed to schedule calculation for #{city.name}")
        end
    end
  end

  defp schedule_calculation(city_id, city_name, force) do
    case CityCoordinateCalculationJob.schedule_update(city_id, force) do
      {:ok, _job} ->
        :scheduled
      {:error, %Ecto.Changeset{errors: [args: {"has already been scheduled", _}]}} ->
        Logger.debug("Job already scheduled for city #{city_name}")
        :skipped
      {:error, reason} ->
        Logger.error("Failed to schedule calculation for city #{city_name}: #{inspect(reason)}")
        :error
    end
  rescue
    error ->
      Logger.error("Error scheduling calculation for city #{city_name}: #{inspect(error)}")
      :error
  end
end