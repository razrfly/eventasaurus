defmodule EventasaurusDiscovery.Admin.DiscoverySyncJob do
  @moduledoc """
  Oban worker for running discovery sync operations from the admin dashboard.
  Wraps the mix discovery.sync functionality in an Oban job.
  """

  use Oban.Worker,
    queue: :discovery_sync,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args], states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 30s, 1min, 2min
    trunc(:math.pow(2, attempt - 1) * 30)
  end

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.SourceRegistry
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    source = args["source"]
    city_id = args["city_id"]
    limit = args["limit"] || 100
    _radius = args["radius"] || 50

    # Log retry attempts
    if attempt > 1 do
      Logger.info("🔄 Retry attempt #{attempt}/3 for #{source} sync (city_id: #{city_id})")
    end

    # Broadcast start
    broadcast_progress(:started, %{source: source, city_id: city_id, attempt: attempt})

    # Check if source requires a city_id using SourceRegistry
    # "all" is a special case that always requires a city
    requires_city = source == "all" || SourceRegistry.requires_city_id?(source)

    # Find the city (only required for city-specific sources)
    city =
      if requires_city do
        Repo.get(City, city_id) |> Repo.preload(:country)
      else
        nil
      end

    # Check if city is required but not found
    if !city && requires_city do
      error_msg = "City not found (id: #{city_id})"
      Logger.error("❌ #{error_msg} for #{source} sync")
      broadcast_progress(:error, %{message: error_msg, source: source, city_id: city_id})
      {:error, error_msg}
    else
      city_info =
        if requires_city do
          "City: #{city.name}, #{city.country.name}"
        else
          case SourceRegistry.get_scope(source) do
            {:ok, :country} -> "Country-wide source"
            {:ok, :regional} -> "Regional source"
            _ -> "Source without city"
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
          sync_all_sources(city, limit, args)

        source ->
          # Check if source is registered in SourceRegistry
          case SourceRegistry.get_sync_job(source) do
            {:ok, _job_module} ->
              # Build job arguments based on source (single source path only)
              options = build_source_options(source, args)
              sync_single_source(source, city, limit, options)

            {:error, :not_found} ->
              broadcast_progress(:error, %{message: "Unknown source: #{source}"})
              {:error, "Unknown source: #{source}"}
          end
      end
    end
  end

  defp sync_single_source(source_name, city, limit, options) do
    # Get job module from registry
    case SourceRegistry.get_sync_job(source_name) do
      {:error, :not_found} ->
        {:error, "Unknown source: #{source_name}"}

      {:ok, job_module} ->
        requires_city = SourceRegistry.requires_city_id?(source_name)

        # Build job args based on source type
        job_args =
          if requires_city do
            %{
              "city_id" => city.id,
              "limit" => limit,
              "options" => options
            }
          else
            %{
              "limit" => limit
            }
          end

        # Queue the actual sync job
        case job_module.new(job_args) |> Oban.insert() do
          {:ok, job} ->
            city_name =
              if requires_city, do: city.name, else: "N/A (#{source_name})"

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

  defp sync_all_sources(city, limit, args) do
    Logger.info("""
    📊 Admin Dashboard: Syncing from ALL sources
    City: #{city.name}
    Total limit: #{limit} events
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
              "options" => per_source_options
            }
          else
            %{
              "limit" => source_limit
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
      case Repo.get(City, city_id) |> Repo.preload(:country) do
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

  defp build_source_options(_source, _args), do: %{}

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
