defmodule EventasaurusWeb.Utils.PollPhaseUtils do
  @moduledoc """
  Utility functions for consistent poll phase messaging and display across all poll types.
  """

  @doc """
  Returns a user-friendly description for the current poll phase.
  """
  def get_phase_description(phase, poll_type) do
    case {phase, poll_type} do
      {"list_building", "movie"} ->
        "Help build the movie list! Add your suggestions below."

      {"list_building", "date_selection"} ->
        "Help select potential dates! Click on calendar dates to suggest them."

      {"list_building", _} ->
        "Help build the list! Add your suggestions below."

      {"voting_with_suggestions", "movie"} ->
        "Vote on your favorite movies and add new suggestions."

      {"voting_with_suggestions", "date_selection"} ->
        "Vote on dates and suggest new ones."

      {"voting_with_suggestions", _} ->
        "Vote on options and add new suggestions."

      {"voting", _} ->
        # Legacy phase - treat as voting_with_suggestions
        get_phase_description("voting_with_suggestions", poll_type)

      {"voting_only", "movie"} ->
        "Vote on your favorite movies below."

      {"voting_only", "date_selection"} ->
        "Vote on your preferred dates below."

      {"voting_only", _} ->
        "Vote on your favorite options below."

      {"closed", _} ->
        "This poll is closed."

      _ ->
        "Participate in this poll."
    end
  end

  @doc """
  Returns true if suggestions are allowed in the current phase.
  """
  def suggestions_allowed?(phase) do
    phase in ["list_building", "voting_with_suggestions", "voting"]
  end

  @doc """
  Returns true if voting is allowed in the current phase.
  """
  def voting_allowed?(phase) do
    phase in ["voting", "voting_with_suggestions", "voting_only"]
  end

  @doc """
  Returns a user-friendly display name for the phase.
  """
  def phase_display_name(phase) do
    case phase do
      "list_building" -> "Building List"
      "voting_with_suggestions" -> "Voting Open"
      "voting" -> "Voting Open"
      "voting_only" -> "Voting Only"
      "closed" -> "Closed"
      _ -> "Unknown"
    end
  end

  @doc """
  Returns the appropriate loading state key for the poll type.
  """
  def get_loading_state_key(poll_type) do
    case poll_type do
      "movie" -> :adding_movie
      "date_selection" -> :loading
      _ -> :adding_option
    end
  end

  @doc """
  Returns a standardized "Add" button text for the poll type.
  """
  def get_add_button_text(poll_type) do
    case poll_type do
      "movie" -> "Add Movie Suggestion"
      "places" -> "Add Place Suggestion"
      "time" -> "Add Time Suggestion"
      "date_selection" -> "Suggest Dates"
      "custom" -> "Add Suggestion"
      _ -> "Add Suggestion"
    end
  end

  @doc """
  Returns a standardized "no suggestions yet" message.
  """
  def get_empty_state_message(poll_type) do
    case poll_type do
      "movie" -> {"No movies suggested yet", "Be the first to add a movie suggestion!"}
      "places" -> {"No places suggested yet", "Be the first to add a place suggestion!"}
      "time" -> {"No times suggested yet", "Be the first to add a time suggestion!"}
      "date_selection" -> {"No dates suggested yet", "Be the first to suggest dates!"}
      "custom" -> {"No options suggested yet", "Be the first to add a suggestion!"}
      _ -> {"No suggestions yet", "Be the first to add a suggestion!"}
    end
  end

  @doc """
  Returns a user-friendly display name for the poll type.
  Centralizes poll type formatting to ensure consistency across all components.
  Can accept either a poll type string or a poll struct.
  """
  def format_poll_type(%{poll_type: poll_type} = poll) do
    # For places polls, include the location scope
    case poll_type do
      "places" -> format_places_poll_type(poll)
      _ -> format_poll_type(poll_type)
    end
  end

  def format_poll_type(poll_type) when is_binary(poll_type) do
    case poll_type do
      "movie" -> "Movie"
      "music_track" -> "Music"
      "places" -> "Place"
      "time" -> "Time"
      "custom" -> "General"
      "date_selection" -> "DateTime"
      _ -> String.capitalize(to_string(poll_type))
    end
  end

  def format_poll_type(poll_type) do
    String.capitalize(to_string(poll_type))
  end

  # Format places poll type with location scope
  defp format_places_poll_type(poll) do
    alias EventasaurusApp.Events.Poll

    scope = Poll.get_location_scope(poll)

    case scope do
      "place" -> "Place"
      "city" -> "City"
      "region" -> "Region"
      "country" -> "Country"
      "custom" -> "Location"
      _ -> "Place"
    end
  end

  @doc """
  Returns the search location for a places poll if it's scoped to places.
  Returns nil if there's no search location or it's not a places poll.
  """
  def get_poll_search_location(%{poll_type: "places", settings: settings})
      when is_map(settings) do
    if Map.get(settings, "location_scope") == "place" do
      case Map.get(settings, "search_location_data") do
        %{} = data ->
          # Try to get the name first, then formatted_address as fallback
          Map.get(data, "name") || Map.get(data, "formatted_address")

        json_str when is_binary(json_str) and json_str != "" ->
          # Handle case where it's still a JSON string (shouldn't happen with normalization, but just in case)
          case Jason.decode(json_str) do
            {:ok, data} when is_map(data) ->
              Map.get(data, "name") || Map.get(data, "formatted_address")

            _ ->
              # Fall back to search_location if JSON decode fails
              Map.get(settings, "search_location")
          end

        _ ->
          # Fall back to search_location if search_location_data is not available
          Map.get(settings, "search_location")
      end
    end
  end

  def get_poll_search_location(_), do: nil
end
