defmodule EventasaurusDiscovery.Sources.WeekPl.Jobs.EventAvailabilityRefreshJob do
  @moduledoc """
  User-initiated availability refresh job for week.pl restaurant events.

  ## Purpose
  Allows users to manually refresh availability data for a specific restaurant event
  without waiting for the next scheduled sync. Provides live, up-to-date availability
  information on demand.

  ## Implementation (Issue #2351 - Phase 2)
  - Lightweight job designed for single-event refresh
  - Async execution with retry logic via Oban
  - Rate limited per user to prevent abuse
  - Broadcasts updates via Phoenix PubSub for real-time UI updates

  ## Job Arguments
  - event_id: Public event database ID
  - source_key: "week_pl"
  - restaurant_id: Restaurant ID from event metadata
  - restaurant_slug: Restaurant slug for logging
  - requested_by_user_id: User ID (optional, for rate limiting)

  ## Flow
  1. Extract restaurant details from event metadata
  2. Fetch latest availability from week.pl GraphQL API
  3. Update event metadata with fresh availability
  4. Broadcast update to connected LiveView clients
  5. Return success/error status
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 2,
    # High priority for user-initiated requests
    priority: 0

  require Logger
  import Ecto.Query
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Sources.WeekPl.Client
  alias Phoenix.PubSub
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    event_id = args["event_id"]
    restaurant_slug = args["restaurant_slug"]
    requested_by = args["requested_by_user_id"]
    external_id = "week_pl_refresh_#{event_id}"

    Logger.info(
      "🔄 [WeekPl.RefreshJob] Refreshing availability for event #{event_id} (#{restaurant_slug}), requested by user #{requested_by || "anonymous"}"
    )

    # Load event with metadata
    case JobRepo.get(PublicEvent, event_id) do
      nil ->
        Logger.error("[WeekPl.RefreshJob] Event #{event_id} not found")
        MetricsTracker.record_failure(job, :data_integrity_error, external_id)
        {:error, :event_not_found}

      event ->
        result = refresh_event_availability(event, args)

        # Track success/failure based on result
        # Error messages use trigger words for ErrorCategories.categorize_error/1
        # See docs/error-handling-guide.md for category definitions
        case result do
          {:ok, _} ->
            MetricsTracker.record_success(job, external_id)
            result

          {:error, :event_not_found} ->
            MetricsTracker.record_failure(job, :data_integrity_error, external_id)
            result

          {:error, :source_not_found} ->
            MetricsTracker.record_failure(job, :data_integrity_error, external_id)
            result

          {:error, :restaurant_not_found} ->
            MetricsTracker.record_failure(job, :venue_error, external_id)
            result

          {:error, :missing_restaurant_data} ->
            MetricsTracker.record_failure(job, :validation_error, external_id)
            result

          {:error, :invalid_api_response} ->
            MetricsTracker.record_failure(job, :parsing_error, external_id)
            result

          {:error, :update_failed} ->
            MetricsTracker.record_failure(job, :data_integrity_error, external_id)
            result

          {:error, reason} ->
            MetricsTracker.record_failure(job, reason, external_id)
            result
        end
    end
  end

  defp refresh_event_availability(event, args) do
    restaurant_id = args["restaurant_id"]
    restaurant_slug = args["restaurant_slug"]

    if restaurant_id && restaurant_slug do
      # Load event with sources to find the week_pl source
      event_with_sources =
        from(pe in PublicEvent,
          where: pe.id == ^event.id,
          preload: [sources: :source]
        )
        |> JobRepo.one()

      if is_nil(event_with_sources) do
        Logger.error("[WeekPl.RefreshJob] Event #{event.id} not found when loading sources")

        {:error, :event_not_found}
      else
        # Find the week_pl source
        week_pl_source =
          Enum.find(event_with_sources.sources, fn source ->
            source.source && source.source.slug == "week_pl"
          end)

        if week_pl_source do
          # Safely extract region_name from metadata
          metadata = week_pl_source.metadata || %{}
          region_name = Map.get(metadata, "region_name", "Unknown")

          # Use today as the base date for fetching availability
          today = Date.utc_today() |> Date.to_string()

          # Fetch latest restaurant availability from week.pl API
          case Client.fetch_restaurant_detail(
                 restaurant_id,
                 restaurant_slug,
                 region_name,
                 today,
                 1140,
                 2
               ) do
            {:ok, response} ->
              update_source_with_fresh_availability(week_pl_source, response, args)

            {:error, :not_found} ->
              Logger.warning(
                "[WeekPl.RefreshJob] Restaurant #{restaurant_slug} not found in API (may be removed from festival)"
              )

              {:error, :restaurant_not_found}

            {:error, reason} ->
              Logger.error(
                "[WeekPl.RefreshJob] Failed to fetch availability for #{restaurant_slug}: #{inspect(reason)}"
              )

              {:error, reason}
          end
        else
          Logger.error("[WeekPl.RefreshJob] week_pl source not found for event #{event.id}")
          {:error, :source_not_found}
        end
      end
    else
      Logger.error(
        "[WeekPl.RefreshJob] Missing restaurant_id or restaurant_slug in event #{event.id}"
      )

      {:error, :missing_restaurant_data}
    end
  end

  defp update_source_with_fresh_availability(source, api_response, args) do
    # Extract availability data from API response
    apollo_state = get_in(api_response, ["pageProps", "apolloState"]) || %{}

    # Find the restaurant object
    restaurant_data =
      apollo_state
      |> Enum.find(fn {key, _} -> String.starts_with?(key, "Restaurant:") end)
      |> case do
        {_, restaurant} -> restaurant
        nil -> nil
      end

    if restaurant_data do
      # Extract availability slots from Daily objects
      availability_summary = extract_availability_summary(apollo_state)

      # Update source metadata with fresh availability
      updated_metadata =
        (source.metadata || %{})
        |> Map.put("availability_last_refreshed_at", DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put("availability_last_refreshed_by", args["requested_by_user_id"])
        |> Map.put("availability_summary", availability_summary)
        |> Map.put("available_dates_count", length(availability_summary["available_dates"] || []))
        |> Map.put(
          "total_timeslots_count",
          availability_summary["total_timeslots"] || 0
        )

      # Update source in database with fresh metadata and timestamp
      case source
           |> Ecto.Changeset.change(
             metadata: updated_metadata,
             last_seen_at: DateTime.utc_now()
           )
           |> JobRepo.update() do
        {:ok, _updated_source} ->
          Logger.info(
            "[WeekPl.RefreshJob] ✅ Refreshed availability for event #{source.event_id}: #{availability_summary["available_dates_count"]} dates, #{availability_summary["total_timeslots"]} timeslots"
          )

          # Broadcast update to LiveView clients
          broadcast_availability_update(source.event_id, availability_summary)

          {:ok,
           %{
             "event_id" => source.event_id,
             "status" => "success",
             "available_dates" => length(availability_summary["available_dates"] || []),
             "total_timeslots" => availability_summary["total_timeslots"] || 0,
             "refreshed_at" => updated_metadata["availability_last_refreshed_at"]
           }}

        {:error, changeset} ->
          Logger.error(
            "[WeekPl.RefreshJob] Failed to update source #{source.id}: #{inspect(changeset.errors)}"
          )

          {:error, :update_failed}
      end
    else
      Logger.error("[WeekPl.RefreshJob] No restaurant data in API response")
      {:error, :invalid_api_response}
    end
  end

  defp extract_availability_summary(apollo_state) do
    # Extract Daily objects from apollo_state
    daily_objects =
      apollo_state
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "Daily:") end)
      |> Enum.map(fn {_, daily} -> daily end)

    # Group by date and collect timeslots
    availability_by_date =
      daily_objects
      |> Enum.group_by(& &1["date"])
      |> Enum.map(fn {date, dailies} ->
        timeslots =
          dailies
          |> Enum.flat_map(&(&1["possibleSlots"] || []))
          |> Enum.uniq()
          |> Enum.sort()

        %{
          "date" => date,
          "timeslot_count" => length(timeslots),
          "timeslots" => timeslots
        }
      end)
      |> Enum.sort_by(& &1["date"])

    %{
      "available_dates" => Enum.map(availability_by_date, & &1["date"]),
      "available_dates_count" => length(availability_by_date),
      "total_timeslots" => availability_by_date |> Enum.map(& &1["timeslot_count"]) |> Enum.sum(),
      "by_date" => availability_by_date
    }
  end

  defp broadcast_availability_update(event_id, availability_summary) do
    # Broadcast to event detail page subscribers
    PubSub.broadcast(
      Eventasaurus.PubSub,
      "event:#{event_id}",
      {:availability_refreshed,
       %{
         event_id: event_id,
         available_dates: availability_summary["available_dates"],
         total_timeslots: availability_summary["total_timeslots"],
         refreshed_at: DateTime.utc_now()
       }}
    )
  end
end
