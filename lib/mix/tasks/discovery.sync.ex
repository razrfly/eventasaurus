defmodule Mix.Tasks.Discovery.Sync do
  @moduledoc """
  Unified task for syncing events from any discovery source.

  ## Usage

      # Sync from Ticketmaster
      mix discovery.sync ticketmaster --city krakow --limit 500 --radius 50

      # Sync from BandsInTown
      mix discovery.sync bandsintown --city krakow --limit 500

      # Sync from Karnet (Kraków only)
      mix discovery.sync karnet --city krakow --limit 500

      # Sync from Cinema City (Kraków only, no city needed)
      mix discovery.sync cinema-city --limit 100

      # Sync from Repertuary (Poland-wide, no city needed)
      mix discovery.sync repertuary --limit 100

      # Sync from PubQuiz (Poland-wide, no city needed)
      mix discovery.sync pubquiz-pl --limit 5

      # Sync from Kupbilecik (Poland-wide, no city needed)
      mix discovery.sync kupbilecik --limit 100

      # Sync from all sources
      mix discovery.sync all --city krakow --limit 500

  ## Options

    * `--city` - City slug to sync events for (required for city-specific sources)
    * `--city-id` - City database ID (alternative to --city)
    * `--limit` - Maximum number of events/cities to fetch (default: 100)
    * `--radius` - Search radius in km (Ticketmaster only, default: 50)
    * `--inline` - Run job synchronously for debugging (default: false, async via Oban)

  ## Examples

      mix discovery.sync ticketmaster --city warsaw --limit 200
      mix discovery.sync bandsintown --city-id 1 --limit 50
      mix discovery.sync karnet --city krakow --limit 100  # Kraków only
      mix discovery.sync cinema-city --limit 50  # Kraków movie showtimes
      mix discovery.sync repertuary --limit 50  # Poland movie showtimes
      mix discovery.sync pubquiz-pl --limit 10  # Poland-wide trivia events
      mix discovery.sync all --city krakow --limit 1000
      mix discovery.sync bandsintown --city krakow --limit 10 --inline  # Debug mode
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  @shortdoc "Sync events from discovery sources"

  @sources %{
    "ticketmaster" => EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob,
    "bandsintown" => EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob,
    "resident-advisor" => EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob,
    "karnet" => EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob,
    "cinema-city" => EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob,
    "repertuary" => EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob,
    "pubquiz-pl" => EventasaurusDiscovery.Sources.PubquizPl.Jobs.SyncJob,
    "waw4free" => EventasaurusDiscovery.Sources.Waw4free.Jobs.SyncJob,
    "kupbilecik" => EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJob
  }

  # Sources that don't require a city (country-wide or city-hardcoded)
  @country_wide_sources ["pubquiz-pl", "cinema-city", "repertuary", "kupbilecik"]

  def run(args) do
    Application.ensure_all_started(:eventasaurus)

    {source_name, opts} = parse_args(args)

    # Find the city (only required for city-specific sources)
    city =
      if source_name in @country_wide_sources do
        nil
      else
        find_city(opts)
      end

    # Validate city for city-specific sources
    if !city && source_name not in @country_wide_sources && source_name != "all" do
      exit_with_error("City is required for #{source_name}")
    end

    # Get options
    limit = opts[:limit] || 100
    inline = opts[:inline] || false

    # Enforce limit for inline mode to prevent rate limiting
    limit =
      if inline && limit > 10 do
        Logger.warning("⚠️  Inline mode limited to max 10 events to prevent rate limiting")
        10
      else
        limit
      end

    options = build_source_options(source_name, city, opts)

    # Run sync
    case source_name do
      "all" ->
        sync_all_sources(city, limit, options, inline)

      source when is_map_key(@sources, source) ->
        sync_source(source, city, limit, options, inline)

      _ ->
        exit_with_error("Unknown source: #{source_name}")
    end
  end

  defp parse_args(args) do
    {opts, remaining, _} =
      OptionParser.parse(args,
        switches: [
          city: :string,
          city_id: :integer,
          limit: :integer,
          radius: :integer,
          inline: :boolean
        ]
      )

    source = List.first(remaining) || "all"
    {String.downcase(source), opts}
  end

  defp find_city(opts) do
    cond do
      opts[:city_id] ->
        Repo.get(City, opts[:city_id]) |> Repo.preload(:country)

      opts[:city] ->
        slug = opts[:city] |> String.downcase() |> create_slug()
        Repo.get_by(City, slug: slug) |> Repo.preload(:country)

      true ->
        nil
    end
  end

  defp create_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp build_source_options("ticketmaster", _city, opts) do
    %{
      radius: opts[:radius] || 50
    }
  end

  defp build_source_options("resident-advisor", city, _opts) do
    # Get area_id from AreaMapper
    if city do
      city = Repo.preload(city, :country)

      case EventasaurusDiscovery.Sources.ResidentAdvisor.Helpers.AreaMapper.get_area_id(city) do
        {:ok, area_id} ->
          Logger.info("✅ Found RA area_id #{area_id} for #{city.name}")
          # Use string key for Oban job args compatibility
          %{"area_id" => area_id}

        {:error, :area_not_found} ->
          Logger.warning("⚠️ No area_id mapping for #{city.name}, #{city.country.name}")
          %{}
      end
    else
      %{}
    end
  end

  defp build_source_options(_source, _city, _opts), do: %{}

  defp sync_source(source_name, city, limit, options, inline) do
    job_module = @sources[source_name]

    # Build appropriate log message
    city_info =
      if source_name in @country_wide_sources do
        "Country: Poland (all cities)"
      else
        "City: #{city.name}, #{city.country.name}"
      end

    Logger.info("""

    📊 Starting #{source_name} sync
    #{city_info}
    Limit: #{limit} events
    Mode: #{if inline, do: "inline (debugging)", else: "async (Oban)"}
    """)

    # Build job args based on source type
    job_args =
      if source_name in @country_wide_sources do
        %{
          "limit" => limit
        }
      else
        %{
          "city_id" => city.id,
          "limit" => limit,
          "options" => options
        }
      end

    if inline do
      # Run synchronously for debugging
      Logger.warning("🔍 Running in INLINE mode - for debugging only!")
      job = %Oban.Job{args: job_args}

      case job_module.perform(job) do
        {:ok, result} ->
          Logger.info("✅ Successfully synced from #{source_name}: #{inspect(result)}")

        {:error, reason} ->
          Logger.error("❌ Sync failed: #{inspect(reason)}")
      end
    else
      # Default: Run asynchronously via Oban
      case job_module.new(job_args) |> Oban.insert() do
        {:ok, job} ->
          Logger.info("✅ Job #{job.id} enqueued for #{source_name}")
          Logger.info("Monitor progress in Oban dashboard or logs")

        {:error, reason} ->
          Logger.error("❌ Failed to enqueue job: #{inspect(reason)}")
      end
    end
  end

  defp sync_all_sources(city, limit, options, inline) do
    Logger.info("""

    📊 Syncing from ALL sources
    City: #{city.name}
    Total limit: #{limit} events
    """)

    # Divide limit among sources
    source_limit = div(limit, map_size(@sources))

    Enum.each(@sources, fn {source_name, _job_module} ->
      sync_source(source_name, city, source_limit, options, inline)
      # Small delay between sources to avoid overwhelming the system
      if inline, do: Process.sleep(1000)
    end)
  end

  defp exit_with_error(message) do
    Logger.error("❌ #{message}")

    Logger.info("""

    Usage: mix discovery.sync [source] --city [city_slug] --limit [number]

    Available sources: #{Map.keys(@sources) |> Enum.join(", ")}, all

    Examples:
      mix discovery.sync ticketmaster --city krakow --limit 100
      mix discovery.sync bandsintown --city warsaw --limit 50
      mix discovery.sync all --city krakow --limit 500
    """)

    System.halt(1)
  end
end
