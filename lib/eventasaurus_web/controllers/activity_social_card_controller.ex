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
  import EventasaurusWeb.SocialCardView, only: [sanitize_activity: 1, render_activity_card_svg: 1]

  # Keep the old function name for route compatibility
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
    timezone = get_event_timezone(event)
    now = DateTime.utc_now()

    dates
    |> Enum.map(fn date_info ->
      with {:ok, date} <- Date.from_iso8601(date_info["date"]),
           {:ok, time} <- parse_time(date_info["time"]) do
        # Create datetime in UTC (as stored in database)
        utc_datetime = DateTime.new!(date, time, "Etc/UTC")

        # Convert to local timezone for display
        local_datetime = DateTime.shift_zone!(utc_datetime, timezone)

        %{
          datetime: local_datetime,
          date: DateTime.to_date(local_datetime),
          time: DateTime.to_time(local_datetime)
        }
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    # Filter out past occurrences
    |> Enum.filter(fn occ ->
      DateTime.compare(occ.datetime, now) in [:gt, :eq]
    end)
    |> Enum.sort_by(& &1.datetime, DateTime)
  end

  defp parse_occurrences(%{occurrences: %{"type" => "pattern", "pattern" => pattern}} = event) do
    timezone = get_event_timezone(event)
    calculate_upcoming_from_pattern(pattern, timezone, 1)
  end

  defp parse_occurrences(_), do: nil

  # Get timezone for event based on venue location
  defp get_event_timezone(%{venue: %{latitude: lat, longitude: lng}})
       when not is_nil(lat) and not is_nil(lng) do
    case TzWorld.timezone_at({lng, lat}) do
      {:ok, tz} -> tz
      _ -> "Europe/Warsaw"
    end
  end

  defp get_event_timezone(_), do: "Europe/Warsaw"

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

    now = DateTime.now!(tz)
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
      |> Enum.map(fn date ->
        dt = DateTime.new!(date, time, tz)

        %{
          datetime: dt,
          date: date,
          time: time
        }
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
