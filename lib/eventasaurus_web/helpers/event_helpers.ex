defmodule EventasaurusWeb.Helpers.EventHelpers do
  @moduledoc """
  Shared helper functions for event creation and editing.
  These functions were extracted from both edit.ex and new.ex to eliminate duplication.
  """

  @doc """
  Filter locations based on search query.
  Searches in name, address, and city fields, with special handling for virtual events.
  """
  def filter_locations(locations, query) when is_binary(query) and byte_size(query) > 0 do
    query_lower = String.downcase(query)

    Enum.filter(locations, fn location ->
      # Check name
      name_match = location.name && String.contains?(String.downcase(location.name), query_lower)

      # Check address
      address_match = location.address &&
        String.contains?(String.downcase(location.address), query_lower)

      # Check city
      city_match = location.city &&
        String.contains?(String.downcase(location.city), query_lower)

      name_match || address_match || city_match
    end)
  end

  def filter_locations(locations, _query), do: locations

  @doc """
  Generate a random Zoom meeting URL.
  """
  def generate_zoom_meeting_url do
    meeting_id = generate_random_meeting_id(11) # Zoom meeting IDs are typically 11 digits
    "https://zoom.us/j/#{meeting_id}"
  end

  @doc """
  Generate a random Google Meet URL.
  """
  def generate_google_meet_url do
    meeting_id = generate_random_meeting_id(10, :alphanum) # Google Meet uses alphanumeric codes
    "https://meet.google.com/#{meeting_id}"
  end

  @doc """
  Generate a random meeting ID with specified length and type.
  """
  def generate_random_meeting_id(length, type \\ :numeric) do
    case type do
      :numeric ->
        1..length
        |> Enum.map(fn _ -> Enum.random(0..9) end)
        |> Enum.join("")

      :alphanum ->
        chars = "abcdefghijklmnopqrstuvwxyz"
        1..length
        |> Enum.map(fn _ ->
          case rem(Enum.random(1..36), 2) do
            0 -> Enum.random(0..9) |> to_string()
            1 -> String.at(chars, Enum.random(0..25))
          end
        end)
        |> Enum.join("")
        |> String.replace(~r/(.{3})(.{4})(.{3})/, "\\1-\\2-\\3") # Add hyphens for Google Meet format
    end
  end
end
