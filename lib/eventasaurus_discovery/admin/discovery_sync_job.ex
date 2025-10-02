defmodule EventasaurusDiscovery.Admin.DiscoverySyncJob do
  @moduledoc """
  Oban worker for running discovery sync operations from the admin dashboard.
  Wraps the mix discovery.sync functionality in an Oban job.
  """

  use Oban.Worker, queue: :discovery_sync, max_attempts: 3

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  require Logger

  @sources %{
    "ticketmaster" => EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob,
    "bandsintown" => EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob,
    "karnet" => EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob,
    "kino-krakow" => EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob,
    "pubquiz-pl" => EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob
  }

  # Sources that don't require a city (country-wide)
  @country_wide_sources ["pubquiz-pl"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source = args["source"]
    city_id = args["city_id"]
    limit = args["limit"] || 100
    _radius = args["radius"] || 50

    # Broadcast start
    broadcast_progress(:started, %{source: source, city_id: city_id})

    # Find the city (only required for city-specific sources)
    city =
      if source in @country_wide_sources do
        nil
      else
        Repo.get(City, city_id) |> Repo.preload(:country)
      end

    # Check if city is required but not found
    if !city && source not in @country_wide_sources && source != "all" do
      broadcast_progress(:error, %{message: "City not found"})
      {:error, "City not found"}
    else
      city_info =
        if source in @country_wide_sources do
          "Country: Poland (all cities)"
        else
          "City: #{city.name}, #{city.country.name}"
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

        source when is_map_key(@sources, source) ->
          # Build job arguments based on source (single source path only)
          options = build_source_options(source, args)
          sync_single_source(source, city, limit, options)

        _ ->
          broadcast_progress(:error, %{message: "Unknown source: #{source}"})
          {:error, "Unknown source: #{source}"}
      end
    end
  end

  defp sync_single_source(source_name, city, limit, options) do
    job_module = @sources[source_name]

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

    # Queue the actual sync job
    case job_module.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        city_name =
          if source_name in @country_wide_sources, do: "Poland (all cities)", else: city.name

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

  defp sync_all_sources(city, limit, args) do
    Logger.info("""
    📊 Admin Dashboard: Syncing from ALL sources
    City: #{city.name}
    Total limit: #{limit} events
    """)

    # Divide limit among sources
    source_limit =
      cond do
        limit <= 0 -> 0
        true -> max(1, div(limit, map_size(@sources)))
      end

    # Queue jobs for each source
    results =
      Enum.map(@sources, fn {source_name, job_module} ->
        per_source_options = build_source_options(source_name, args)

        job_args = %{
          "city_id" => city.id,
          "limit" => source_limit,
          "options" => per_source_options
        }

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
