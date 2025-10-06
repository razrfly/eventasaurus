defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob do
  @moduledoc """
  Oban job for syncing Resident Advisor events via GraphQL API.

  Unlike HTML scrapers, RA uses a GraphQL API which simplifies the job pipeline:
  1. SyncJob queries GraphQL with pagination
  2. Processes events inline (no separate EventDetailJob needed for most cases)
  3. Uses unified Processor for venue/event creation

  ## Job Arguments

  - `source_id` - Database ID of the RA source
  - `city_id` - Database ID of the target city
  - `area_id` - RA integer area ID (see AreaMapper)
  - `start_date` - ISO date string (default: today)
  - `end_date` - ISO date string (default: today + 30 days)
  - `page_size` - Results per page (default: 20, max: 100)

  ## Features

  - GraphQL pagination with cursor support
  - Inline event processing (no separate detail jobs)
  - Multi-strategy venue geocoding
  - Strict venue validation (rejects events without coordinates)
  - Rate limiting (2 req/s default)
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source

  alias EventasaurusDiscovery.Sources.ResidentAdvisor.{
    Client,
    Config,
    Transformer,
    Jobs.EventDetailJob
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Extract area_id from options if provided (dashboard integration)
    area_id_from_args = args["area_id"] || get_in(args, ["options", "area_id"])

    # Validate required arguments
    with {:ok, city_id} <- validate_integer(args["city_id"], "city_id"),
         {:ok, area_id} <- validate_integer(area_id_from_args, "area_id") do
      # Optional arguments with defaults
      start_date = args["start_date"] || default_start_date()
      end_date = args["end_date"] || default_end_date()
      page_size = args["page_size"] || 20

      Logger.info("""
      🎵 Starting Resident Advisor sync
      City ID: #{city_id}
      Area ID: #{area_id}
      Date range: #{start_date} to #{end_date}
      Page size: #{page_size}
      """)

      # Get city with country preloaded
      case Repo.get(City, city_id) do
        nil ->
          Logger.error("City not found: #{city_id}")
          {:error, :city_not_found}

        city ->
          city = Repo.preload(city, :country)
          source = get_or_create_ra_source()

          sync_events(city, area_id, start_date, end_date, page_size, source)
      end
    else
      {:error, field, reason} ->
        Logger.error("❌ Invalid job arguments - #{field}: #{reason}")
        {:error, "invalid_args_#{field}"}
    end
  end

  # Private functions

  defp sync_events(city, area_id, start_date, end_date, page_size, source) do
    Logger.info("🚀 Fetching RA events for #{city.name} (area #{area_id})")

    # GraphQL pagination state
    result =
      fetch_all_pages(
        area_id,
        start_date,
        end_date,
        page_size,
        _page = 1,
        _accumulated_events = []
      )

    case result do
      {:ok, all_events} ->
        Logger.info("📚 Fetched #{length(all_events)} events from RA GraphQL")

        # Transform events and queue individual processing jobs
        {queued_count, failed_count} = schedule_event_detail_jobs(all_events, city, source)

        Logger.info("""
        ✅ RA sync completed
        Total events fetched: #{length(all_events)}
        EventDetailJobs queued: #{queued_count}
        Failed validation: #{failed_count}
        """)

        {:ok,
         %{
           events_fetched: length(all_events),
           jobs_queued: queued_count,
           validation_failures: failed_count
         }}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch RA events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_all_pages(area_id, start_date, end_date, page_size, page, accumulated) do
    # Rate limiting
    if page > 1 do
      # Sleep between requests (2 req/s = 500ms delay)
      Process.sleep(div(1000, Config.rate_limit()))
    end

    Logger.debug("📄 Fetching RA page #{page} (#{length(accumulated)} events so far)")

    case Client.fetch_events(area_id, start_date, end_date, page, page_size) do
      {:ok, %{"eventListings" => %{"data" => events}}} when is_list(events) ->
        # Append new events
        all_events = accumulated ++ events

        # Check if we should continue pagination
        if length(events) >= page_size do
          # More pages likely available
          Logger.debug("🔄 Page #{page} has #{length(events)} events, fetching next page")
          fetch_all_pages(area_id, start_date, end_date, page_size, page + 1, all_events)
        else
          # Last page or empty page
          Logger.info("📭 Reached last page (#{page}), total events: #{length(all_events)}")
          {:ok, all_events}
        end

      {:ok, unexpected} ->
        Logger.warning("⚠️ Unexpected GraphQL response structure: #{inspect(unexpected)}")
        {:ok, accumulated}

      {:error, :rate_limited} ->
        Logger.warning("⚠️ Rate limited on page #{page}, waiting and retrying...")
        Process.sleep(5000)
        fetch_all_pages(area_id, start_date, end_date, page_size, page, accumulated)

      {:error, reason} ->
        Logger.error("❌ GraphQL query failed on page #{page}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_event_detail_jobs(raw_events, city, source) do
    # Transform events and queue individual EventDetailJobs
    {queued, failed} =
      raw_events
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {raw_event, index}, {queued_acc, failed_acc} ->
        case Transformer.transform_event(raw_event, city) do
          {:ok, transformed} ->
            # Stagger jobs to avoid overwhelming the system (Config.rate_limit() seconds apart)
            scheduled_at = DateTime.add(DateTime.utc_now(), index * Config.rate_limit(), :second)

            job_args = %{
              "event_data" => transformed,
              "source_id" => source.id
            }

            case EventDetailJob.new(job_args, scheduled_at: scheduled_at) |> Oban.insert() do
              {:ok, _job} ->
                {[transformed[:external_id] | queued_acc], failed_acc}

              {:error, reason} ->
                Logger.warning("⚠️ Failed to queue EventDetailJob for #{transformed[:external_id]}: #{inspect(reason)}")
                {queued_acc, [transformed[:external_id] | failed_acc]}
            end

          {:error, reason} ->
            external_id = get_in(raw_event, ["event", "id"]) || "unknown"

            Logger.warning("""
            ⚠️ Failed to transform RA event (venue validation failed)
            Event ID: #{external_id}
            Reason: #{inspect(reason)}
            """)

            {queued_acc, [external_id | failed_acc]}
        end
      end)

    {length(queued), length(failed)}
  end

  # Validation helpers

  defp validate_integer(nil, field), do: {:error, field, "is required"}
  defp validate_integer(value, _field) when is_integer(value), do: {:ok, value}

  defp validate_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, field, "invalid integer: #{inspect(value)}"}
    end
  end

  defp validate_integer(value, field),
    do: {:error, field, "expected integer, got: #{inspect(value)}"}

  defp default_start_date do
    Date.utc_today()
    |> Date.to_iso8601()
  end

  defp default_end_date do
    Date.utc_today()
    |> Date.add(30)
    |> Date.to_iso8601()
  end

  defp get_or_create_ra_source do
    case Repo.get_by(Source, slug: "resident-advisor") do
      nil ->
        Logger.warning("⚠️ RA source not found, creating from config")

        %Source{}
        |> Source.changeset(%{
          name: "Resident Advisor",
          slug: "resident-advisor",
          website_url: "https://ra.co",
          priority: 75,
          metadata: %{
            "rate_limit_seconds" => 0.5,
            "max_requests_per_hour" => 7200,
            "api_type" => "graphql",
            "supports_pagination" => true
          }
        })
        |> Repo.insert!()

      source ->
        source
    end
  end
end
