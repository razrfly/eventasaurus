defmodule EventasaurusWeb.Helpers.EventDisplayHelpers do
  @moduledoc """
  Shared helper functions for displaying event information.

  These helpers are used across multiple LiveViews and components
  for consistent event display formatting.
  """

  alias EventasaurusApp.DateTimeHelper

  @doc """
  Returns the cover image URL for an event, with fallback to external image data
  or a generated placeholder.

  ## Examples

      iex> event_cover_image_url(%{cover_image_url: "https://example.com/image.jpg"})
      "https://example.com/image.jpg"

      iex> event_cover_image_url(%{cover_image_url: nil, external_image_data: %{"url" => "https://external.com/img.png"}})
      "https://external.com/img.png"

      iex> event_cover_image_url(%{cover_image_url: nil, external_image_data: nil, title: "My Event"})
      "https://api.dicebear.com/9.x/shapes/svg?seed=123456&backgroundColor=gradient"
  """
  @spec event_cover_image_url(map()) :: String.t()
  def event_cover_image_url(event) do
    cond do
      event.cover_image_url && event.cover_image_url != "" ->
        event.cover_image_url

      event.external_image_data && Map.get(event.external_image_data, "url") ->
        Map.get(event.external_image_data, "url")

      true ->
        seed = :erlang.phash2(event.title || "event")
        "https://api.dicebear.com/9.x/shapes/svg?seed=#{seed}&backgroundColor=gradient"
    end
  end

  @doc """
  Formats an event datetime with timezone conversion.

  Returns a formatted string like "Wed, Jan 15, 19:30" or "Date TBD" for nil.

  ## Parameters
  - `datetime` - The DateTime to format (in UTC)
  - `timezone` - The timezone string to convert to (e.g., "America/New_York")

  ## Examples

      iex> format_event_date(~U[2025-01-15 19:30:00Z], "America/New_York")
      "Wed, Jan 15, 14:30"

      iex> format_event_date(nil, "America/New_York")
      "Date TBD"
  """
  @spec format_event_date(DateTime.t() | nil, String.t() | nil) :: String.t()
  def format_event_date(%DateTime{} = datetime, timezone) do
    case timezone do
      tz when is_binary(tz) ->
        try do
          datetime
          |> DateTimeHelper.utc_to_timezone(tz)
          |> Calendar.strftime("%a, %b %d, %H:%M")
        rescue
          ArgumentError -> Calendar.strftime(datetime, "%a, %b %d, %H:%M UTC")
        end

      _ ->
        Calendar.strftime(datetime, "%a, %b %d, %H:%M UTC")
    end
  end

  def format_event_date(nil, _timezone), do: "Date TBD"

  @doc """
  Formats a location string for an event based on venue or virtual status.

  ## Examples

      iex> format_event_location(%{venue: %{name: "Madison Square Garden"}})
      "Madison Square Garden"

      iex> format_event_location(%{is_virtual: true})
      "Virtual Event"

      iex> format_event_location(%{venue: nil})
      "Location TBD"
  """
  @spec format_event_location(map()) :: String.t()
  def format_event_location(event) do
    cond do
      event.venue && event.venue.name ->
        event.venue.name

      Map.get(event, :virtual_venue_url) && event.virtual_venue_url != "" ->
        "Virtual Event"

      Map.get(event, :is_virtual) == true ->
        "Virtual Event"

      true ->
        "Location TBD"
    end
  end
end
