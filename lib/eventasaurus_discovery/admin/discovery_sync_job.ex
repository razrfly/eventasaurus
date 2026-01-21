defmodule EventasaurusDiscovery.Admin.DiscoverySyncJob do
  @moduledoc """
  Oban worker for running discovery sync operations from the admin dashboard.
  Wraps the mix discovery.sync functionality in an Oban job.
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args], states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 30s, 1min, 2min
    trunc(:math.pow(2, attempt - 1) * 30)
  end

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.SourceRegistry
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    source = args["source"]
    city_id = args["city_id"]
    limit = args["limit"] || 100
    _radius = args["radius"] || 50
    force = args["force"] || false

    # Log retry attempts
    if attempt > 1 do
      Logger.info("🔄 Retry attempt #{attempt}/3 for #{source} sync (city_id: #{city_id})")
    end

    if force do
      Logger.info("⚡ Force mode enabled for #{source} - bypassing EventFreshnessChecker")
    end

    # Broadcast start
    broadcast_progress(:started, %{source: source, city_id: city_id, attempt: attempt})

    # Check if source requires a city_id using SourceRegistry
    # "all" is a special case that always requires a city
    requires_city = source == "all" || SourceRegistry.requires_city_id?(source)

    # Find the city (only required for city-specific sources)
    city =
      if requires_city && city_id do
        JobRepo.get(City, city_id) |> JobRepo.preload(:country)
      else
        nil
      end

    # Only fail if city_id was explicitly provided but city doesn't exist
    # Allow nil city_id - regional/country sources will auto-create cities via VenueProcessor
    if requires_city && city_id && !city do
      error_msg = "Invalid city_id: #{city_id}"
      Logger.error("❌ #{error_msg} for #{source} sync")
      broadcast_progress(:error, %{message: error_msg, source: source, city_id: city_id})
      {:error, error_msg}
    else
      city_info =
        if requires_city && city do
          "City: #{city.name}, #{city.country.name}"
        else
          case SourceRegistry.get_scope(source) do
            {:ok, :country} -> "Country-wide source (will auto-create cities)"
            {:ok, :regional} -> "Regional source (will auto-create cities)"
            _ -> "Source without city (will auto-create cities)"
          end
        end

      Logger.info("""
      📊 Admin Dashboard: Starting #{source} sync
      #{city_info}
      Limit: #{limit} events
      """)

      # Handle different source types
      case source do
        "all" ->
          sync_all_sources(city, limit, args, force)

        source ->
          # Check if source is registered in SourceRegistry
          case SourceRegistry.get_sync_job(source) do
            {:ok, _job_module} ->
              # Build job arguments based on source (single source path only)
              options = build_source_options(source, args)
              sync_single_source(source, city, limit, options, force)

            {:error, :not_found} ->
              broadcast_progress(:error, %{message: "Unknown source: #{source}"})
              {:error, "Unknown source: #{source}"}
          end
      end
    end
  end

  defp sync_single_source(source_name, city, limit, options, force) do
    # Get job module from registry
    case SourceRegistry.get_sync_job(source_name) do
      {:error, :not_found} ->
        {:error, "Unknown source: #{source_name}"}

      {:ok, job_module} ->
        requires_city = SourceRegistry.requires_city_id?(source_name)

        # Build job args based on source type
        job_args =
          if requires_city && city do
            %{
              "city_id" => city.id,
              "limit" => limit,
              "options" => options,
              "force" => force
            }
          else
            # Regional/country sources or when city_id not provided
            %{
              "limit" => limit,
              "force" => force
            }
          end

        # Queue the actual sync job
        case job_module.new(job_args) |> Oban.insert() do
          {:ok, job} ->
            city_name =
              if requires_city && city, do: city.name, else: "N/A (#{source_name})"

            broadcast_progress(:completed, %{
              message: "Sync job queued for #{source_name}",
              job_id: job.id,
              source: source_name,
              city: city_name
            })

            {:ok, %{job_id: job.id, source: source_name}}

          {:error, reason} ->
            Logger.error("❌ Failed to queue sync job: #{inspect(reason)}")

            broadcast_progress(:error, %{
              message: "Failed to queue sync: #{inspect(reason)}",
              source: source_name
            })

            {:error, reason}
        end
    end
  end

  defp sync_all_sources(city, limit, args, force) do
    Logger.info("""
    📊 Admin Dashboard: Syncing from ALL sources
    City: #{city.name}
    Total limit: #{limit} events
    Force mode: #{force}
    """)

    # Get all sources from registry
    all_sources = SourceRegistry.sources_map()

    # Divide limit among sources
    source_limit =
      cond do
        limit <= 0 -> 0
        true -> max(1, div(limit, map_size(all_sources)))
      end

    # Queue jobs for each source
    results =
      Enum.map(all_sources, fn {source_name, job_module} ->
        per_source_options = build_source_options(source_name, args)
        requires_city = SourceRegistry.requires_city_id?(source_name)

        job_args =
          if requires_city do
            %{
              "city_id" => city.id,
              "limit" => source_limit,
              "options" => per_source_options,
              "force" => force
            }
          else
            %{
              "limit" => source_limit,
              "force" => force
            }
          end

        case job_module.new(job_args) |> Oban.insert() do
          {:ok, job} ->
            {:ok, %{source: source_name, job_id: job.id}}

          {:error, reason} ->
            {:error, %{source: source_name, reason: reason}}
        end
      end)

    successful = Enum.filter(results, fn {status, _} -> status == :ok end)
    failed = Enum.filter(results, fn {status, _} -> status == :error end)

    message =
      "Queued #{length(successful)} sync jobs" <>
        if(length(failed) > 0, do: " (#{length(failed)} failed)", else: "")

    broadcast_progress(:completed, %{
      message: message,
      successful: successful,
      failed: failed,
      city: city.name
    })

    if length(successful) > 0 do
      {:ok, %{successful: successful, failed: failed}}
    else
      {:error, "Failed to queue any sync jobs"}
    end
  end

  defp build_source_options("ticketmaster", args) do
    %{
      radius: args["radius"] || 50
    }
  end

  defp build_source_options("resident-advisor", %{"city_id" => city_id} = args) do
    # RA requires area_id mapping
    # Look up area_id from city using AreaMapper
    area_id =
      case JobRepo.get(City, city_id) |> JobRepo.preload(:country) do
        nil ->
          Logger.warning("⚠️ City not found for area_id lookup: #{city_id}")
          nil

        city ->
          case EventasaurusDiscovery.Sources.ResidentAdvisor.Helpers.AreaMapper.get_area_id(city) do
            {:ok, area_id} ->
              Logger.info("✅ Found RA area_id #{area_id} for #{city.name}")
              area_id

            {:error, :area_not_found} ->
              Logger.warning("⚠️ No area_id mapping for #{city.name}, #{city.country.name}")
              nil
          end
      end

    %{area_id: area_id || args["area_id"]}
  end

  defp build_source_options("cinema-city", %{"city_id" => city_id}) do
    # Cinema City requires city_name from the city's discovery_config
    case JobRepo.get(City, city_id) do
      nil ->
        Logger.warning("⚠️ City not found for cinema-city: #{city_id}")
        %{}

      city ->
        # Get city_name from discovery_config sources
        city_name = get_cinema_city_name_from_config(city)

        if city_name do
          Logger.info("✅ Found Cinema City city_name '#{city_name}' for #{city.name}")
          %{city_name: city_name}
        else
          Logger.warning("⚠️ No city_name configured for cinema-city source on #{city.name}")
          %{}
        end
    end
  end

  defp build_source_options("repertuary", %{"city_id" => city_id}) do
    # Repertuary requires city_key from the city's discovery_config
    # This maps to the repertuary.pl subdomain (e.g., "warszawa" -> warszawa.repertuary.pl)
    case JobRepo.get(City, city_id) do
      nil ->
        Logger.warning("⚠️ City not found for repertuary: #{city_id}")
        %{}

      city ->
        # Get city_key from discovery_config sources
        city_key = get_repertuary_city_key_from_config(city)

        if city_key do
          Logger.info("✅ Found Repertuary city_key '#{city_key}' for #{city.name}")
          %{city: city_key}
        else
          Logger.warning("⚠️ No city_key configured for repertuary source on #{city.name}")
          %{}
        end
    end
  end

  defp build_source_options(_source, _args), do: %{}

  # Extract city_key from city's discovery_config for repertuary source
  # Handles both struct-based and map-based configs with atom or string keys
  defp get_repertuary_city_key_from_config(city) do
    config = city.discovery_config || %{}

    sources =
      cond do
        is_map(config) and Map.has_key?(config, "sources") ->
          config["sources"] || []

        is_map(config) and Map.has_key?(config, :sources) ->
          config[:sources] || []

        true ->
          []
      end

    repertuary_source =
      Enum.find(sources, fn source ->
        is_map(source) && (source["name"] == "repertuary" || source[:name] == "repertuary")
      end)

    case repertuary_source do
      %{} = source ->
        settings = source["settings"] || source[:settings] || %{}

        case settings["city_key"] || settings[:city_key] do
          "" -> nil
          city_key -> city_key
        end

      _ ->
        nil
    end
  end

  # Extract city_name from city's discovery_config for cinema-city source
  # Handles both struct-based and map-based configs with atom or string keys
  defp get_cinema_city_name_from_config(city) do
    config = city.discovery_config || %{}

    sources =
      cond do
        is_map(config) and Map.has_key?(config, "sources") ->
          config["sources"] || []

        is_map(config) and Map.has_key?(config, :sources) ->
          config[:sources] || []

        true ->
          []
      end

    cinema_city_source =
      Enum.find(sources, fn source ->
        is_map(source) && (source["name"] == "cinema-city" || source[:name] == "cinema-city")
      end)

    case cinema_city_source do
      %{} = source ->
        settings = source["settings"] || source[:settings] || %{}

        case settings["city_name"] || settings[:city_name] do
          "" -> nil
          city_name -> city_name
        end

      _ ->
        nil
    end
  end

  defp broadcast_progress(status, data) do
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "discovery_progress",
      {:discovery_progress, Map.put(data, :status, status)}
    )
  end

  @doc """
  Convenience function to queue a sync job from other modules.
  """
  def queue_sync(source, city_id, limit \\ 100, radius \\ 50) do
    %{
      "source" => source,
      "city_id" => city_id,
      "limit" => limit,
      "radius" => radius
    }
    |> new()
    |> Oban.insert()
  end
end
