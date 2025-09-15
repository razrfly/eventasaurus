defmodule Mix.Tasks.Ticketmaster.Sync do
  @moduledoc """
  Sync events from Ticketmaster API for a specific city.

  Usage:
    mix ticketmaster.sync --city krakow
    mix ticketmaster.sync --city warsaw --radius 100
    mix ticketmaster.sync --city-id 1 --radius 50
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Apis.Ticketmaster.Jobs.CitySyncJob

  @shortdoc "Sync Ticketmaster events for a city"

  def run(args) do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:tesla)
    Application.ensure_all_started(:eventasaurus)

    {opts, _, _} = OptionParser.parse(args,
      switches: [
        city: :string,
        city_id: :integer,
        radius: :integer,
        max_pages: :integer,
        async: :boolean
      ]
    )

    radius = opts[:radius] || 50
    max_pages = opts[:max_pages] || 5
    async = opts[:async] || false

    # Find the city
    city = cond do
      opts[:city_id] ->
        Repo.get!(City, opts[:city_id]) |> Repo.preload(:country)

      opts[:city] ->
        city_name = opts[:city] |> String.downcase()
        case Repo.get_by(City, slug: city_name) do
          nil ->
            # Try searching by name
            import Ecto.Query
            query = from c in City,
              where: fragment("LOWER(?) LIKE ?", c.name, ^"%#{city_name}%"),
              limit: 1
            Repo.one!(query) |> Repo.preload(:country)
          city ->
            Repo.preload(city, :country)
        end

      true ->
        Logger.error("Please specify --city or --city-id")
        System.halt(1)
    end

    Logger.info("""

    🎫 Ticketmaster Sync Configuration
    =====================================
    City: #{city.name}, #{city.country.name}
    City ID: #{city.id}
    Coordinates: (#{city.latitude}, #{city.longitude})
    Radius: #{radius}km
    Max pages: #{max_pages}
    Mode: #{if async, do: "Async (Oban)", else: "Synchronous"}
    """)

    if async do
      # Queue as Oban job
      %{
        city_id: city.id,
        radius: radius,
        max_pages: max_pages
      }
      |> CitySyncJob.new()
      |> Oban.insert!()

      Logger.info("✅ Job queued for processing")
    else
      # Run synchronously
      job = %Oban.Job{
        args: %{
          "city_id" => city.id,
          "radius" => radius,
          "max_pages" => max_pages
        }
      }

      case CitySyncJob.perform(job) do
        {:ok, result} ->
          Logger.info("✅ Sync completed: #{inspect(result)}")
        {:error, reason} ->
          Logger.error("❌ Sync failed: #{inspect(reason)}")
          System.halt(1)
      end
    end
  end
end