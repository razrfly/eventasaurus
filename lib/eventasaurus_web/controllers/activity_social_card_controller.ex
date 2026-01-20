defmodule EventasaurusWeb.ActivitySocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for public activities (events).

  This controller generates social cards with Wombie branding for activities,
  including title, date/time, venue, and city information.

  Route: GET /social-cards/activity/:slug/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :activity

  import Ecto.Query, only: [from: 2]

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Utils.TimezoneUtils
  import EventasaurusWeb.SocialCardView, only: [sanitize_activity: 1, render_activity_card_svg: 1]

  @doc """
  Generates a social card by activity slug. Legacy route compatibility wrapper.
  """
  @spec generate_card_by_slug(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def generate_card_by_slug(conn, params) do
    generate_card(conn, params)
  end

  @impl true
  def lookup_entity(%{"slug" => slug}) do
    case fetch_activity(slug) do
      nil -> {:error, :not_found, "Activity not found for slug: #{slug}"}
      activity -> {:ok, activity}
    end
  end

  @impl true
  def build_card_data(activity), do: activity

  @impl true
  def build_slug(_params, activity), do: activity.slug

  @impl true
  def sanitize(data), do: sanitize_activity(data)

  @impl true
  def render_svg(data), do: render_activity_card_svg(data)

  # Fetch activity (public event) by slug with required preloads
  defp fetch_activity(slug) do
    event =
      from(pe in PublicEvent,
        where: pe.slug == ^slug,
        preload: [venue: [city_ref: :country]]
      )
      |> Repo.one()

    if event do
      # Enrich with cover image
      enriched_event =
        [event]
        |> PublicEventsEnhanced.preload_for_image_enrichment()
        |> PublicEventsEnhanced.enrich_event_images(strategy: :own_city)
        |> List.first()

      # Parse occurrences for date/time display
      enriched_event
      |> Map.put(:occurrence_list, parse_occurrences(enriched_event))
    else
      nil
    end
  end

  # Parse occurrences from event data
  # Simplified version for social card - only need first occurrence
  defp parse_occurrences(%{occurrences: nil}), do: nil

  defp parse_occurrences(%{occurrences: %{"dates" => dates}} = event) when is_list(dates) do
    timezone = TimezoneUtils.get_event_timezone(event)

    # Use local time for comparison since occurrence times are local
    # Handle timezone errors gracefully
    now =
      case DateTime.now(timezone) do
        {:ok, dt} -> dt
        {:error, _} -> DateTime.utc_now()
      end

    dates
    |> Enum.map(fn date_info ->
      with {:ok, date} <- Date.from_iso8601(date_info["date"]),
           {:ok, time} <- parse_time(date_info["time"]) do
        # IMPORTANT: Times in occurrences.dates are LOCAL times, NOT UTC.
        # See docs/SCRAPER_QUALITY_GUIDELINES.md - "Always store times in event's local timezone"
        # Handle DST transitions gracefully:
        # - {:ambiguous, dt1, dt2} = fall-back (DST ends, pick earlier)
        # - {:gap, before, after} = spring-forward (DST starts, use after)
        case DateTime.new(date, time, timezone) do
          {:ok, dt} ->
            %{datetime: dt, date: date, time: time}

          {:ambiguous, dt, _later} ->
            %{datetime: dt, date: date, time: time}

          {:gap, _before, after_dt} ->
            %{datetime: after_dt, date: date, time: time}

          {:error, _} ->
            nil
        end
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.datetime, DateTime)
    # Select the best occurrence to display:
    # - Prefer the first FUTURE occurrence if any exist
    # - Otherwise show the MOST RECENT past occurrence
    # This ensures historical events still display their date on social cards
    |> select_best_occurrence_for_display(now)
  end

  defp parse_occurrences(%{occurrences: %{"type" => "pattern", "pattern" => pattern}} = event) do
    timezone = TimezoneUtils.get_event_timezone(event)
    calculate_upcoming_from_pattern(pattern, timezone, 1)
  end

  defp parse_occurrences(_), do: nil

  # Select the best occurrence to display on the social card
  # Returns a list with a single occurrence (for consistency with existing code)
  # Prefers future occurrences, falls back to most recent past occurrence
  defp select_best_occurrence_for_display([], _now), do: []

  defp select_best_occurrence_for_display(sorted_occurrences, now) do
    # Find first future occurrence
    future_occurrence =
      Enum.find(sorted_occurrences, fn occ ->
        DateTime.compare(occ.datetime, now) in [:gt, :eq]
      end)

    case future_occurrence do
      nil ->
        # All occurrences are in the past - show the most recent one
        # sorted_occurrences is already sorted ascending, so last is most recent
        case List.last(sorted_occurrences) do
          nil -> []
          most_recent -> [most_recent]
        end

      occurrence ->
        # Has future occurrence - show the first upcoming one
        [occurrence]
    end
  end

  # Parse time string to Time struct
  defp parse_time(nil), do: {:ok, ~T[00:00:00]}

  defp parse_time(time_str) when is_binary(time_str) do
    case Time.from_iso8601(time_str <> ":00") do
      {:ok, time} -> {:ok, time}
      _ -> Time.from_iso8601(time_str)
    end
  end

  defp parse_time(_), do: {:ok, ~T[00:00:00]}

  # Calculate upcoming occurrences from a recurring pattern
  defp calculate_upcoming_from_pattern(pattern, timezone, count) do
    time_str = Map.fetch!(pattern, "time")
    days_of_week = Map.get(pattern, "days_of_week", [])
    tz = pattern["timezone"] || timezone

    {:ok, time} = parse_time(time_str)

    # Handle timezone errors gracefully
    now =
      case DateTime.now(tz) do
        {:ok, dt} -> dt
        {:error, _} -> DateTime.utc_now()
      end

    today = DateTime.to_date(now)

    target_weekdays =
      days_of_week
      |> Enum.map(&day_name_to_number/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(target_weekdays) do
      []
    else
      0..30
      |> Enum.map(&Date.add(today, &1))
      |> Enum.filter(fn date -> Date.day_of_week(date) in target_weekdays end)
      |> Enum.take(count)
      |> Enum.flat_map(fn date ->
        # Handle DST transitions gracefully
        case DateTime.new(date, time, tz) do
          {:ok, dt} ->
            [%{datetime: dt, date: date, time: time}]

          {:ambiguous, dt, _later} ->
            [%{datetime: dt, date: date, time: time}]

          {:gap, _before, after_dt} ->
            [%{datetime: after_dt, date: date, time: time}]

          {:error, _} ->
            []
        end
      end)
      |> Enum.filter(fn occ -> DateTime.compare(occ.datetime, now) in [:gt, :eq] end)
    end
  end

  defp day_name_to_number("monday"), do: 1
  defp day_name_to_number("tuesday"), do: 2
  defp day_name_to_number("wednesday"), do: 3
  defp day_name_to_number("thursday"), do: 4
  defp day_name_to_number("friday"), do: 5
  defp day_name_to_number("saturday"), do: 6
  defp day_name_to_number("sunday"), do: 7
  defp day_name_to_number(_), do: nil
end
