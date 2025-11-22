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
    queue: :week_pl_refresh,
    max_attempts: 2,
    priority: 0  # High priority for user-initiated requests

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Sources.WeekPl.Client
  alias Phoenix.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = _job) do
    event_id = args["event_id"]
    restaurant_slug = args["restaurant_slug"]
    requested_by = args["requested_by_user_id"]

    Logger.info(
      "🔄 [WeekPl.RefreshJob] Refreshing availability for event #{event_id} (#{restaurant_slug}), requested by user #{requested_by || "anonymous"}"
    )

    # Load event with metadata
    case Repo.get(PublicEvent, event_id) do
      nil ->
        Logger.error("[WeekPl.RefreshJob] Event #{event_id} not found")
        {:error, :event_not_found}

      event ->
        refresh_event_availability(event, args)
    end
  end

  defp refresh_event_availability(event, args) do
    # Extract restaurant details from event metadata
    metadata = event.metadata || %{}
    restaurant_id = args["restaurant_id"] || metadata["restaurant_id"]
    restaurant_slug = args["restaurant_slug"] || metadata["restaurant_slug"]
    region_name = metadata["region_name"] || "Unknown"

    if restaurant_id && restaurant_slug do
      # Use today as the base date for fetching availability
      today = Date.utc_today() |> Date.to_string()

      # Fetch latest restaurant availability from week.pl API
      case Client.fetch_restaurant_detail(restaurant_id, restaurant_slug, region_name, today, 1140,
             2
           ) do
        {:ok, response} ->
          update_event_with_fresh_availability(event, response, args)

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
      Logger.error(
        "[WeekPl.RefreshJob] Missing restaurant_id or restaurant_slug in event #{event.id}"
      )

      {:error, :missing_restaurant_data}
    end
  end

  defp update_event_with_fresh_availability(event, api_response, args) do
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

      # Update event metadata with fresh availability
      updated_metadata =
        (event.metadata || %{})
        |> Map.put("availability_last_refreshed_at", DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put("availability_last_refreshed_by", args["requested_by_user_id"])
        |> Map.put("availability_summary", availability_summary)
        |> Map.put("available_dates_count", length(availability_summary["available_dates"] || []))
        |> Map.put(
          "total_timeslots_count",
          availability_summary["total_timeslots"] || 0
        )

      # Update event in database
      case event
           |> Ecto.Changeset.change(metadata: updated_metadata)
           |> Repo.update() do
        {:ok, updated_event} ->
          Logger.info(
            "[WeekPl.RefreshJob] ✅ Refreshed availability for event #{event.id}: #{availability_summary["available_dates_count"]} dates, #{availability_summary["total_timeslots"]} timeslots"
          )

          # Broadcast update to LiveView clients
          broadcast_availability_update(updated_event, availability_summary)

          {:ok,
           %{
             "event_id" => event.id,
             "status" => "success",
             "available_dates" => length(availability_summary["available_dates"] || []),
             "total_timeslots" => availability_summary["total_timeslots"] || 0,
             "refreshed_at" => updated_metadata["availability_last_refreshed_at"]
           }}

        {:error, changeset} ->
          Logger.error(
            "[WeekPl.RefreshJob] Failed to update event #{event.id}: #{inspect(changeset.errors)}"
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
          |> Enum.flat_map(& &1["possibleSlots"] || [])
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
      "total_timeslots" =>
        availability_by_date |> Enum.map(& &1["timeslot_count"]) |> Enum.sum(),
      "by_date" => availability_by_date
    }
  end

  defp broadcast_availability_update(event, availability_summary) do
    # Broadcast to event detail page subscribers
    PubSub.broadcast(
      Eventasaurus.PubSub,
      "event:#{event.id}",
      {:availability_refreshed,
       %{
         event_id: event.id,
         available_dates: availability_summary["available_dates"],
         total_timeslots: availability_summary["total_timeslots"],
         refreshed_at: DateTime.utc_now()
       }}
    )
  end
end
