defmodule EventasaurusWeb.OptionSuggestionHelpers do
  @moduledoc """
  Shared helper functions for option suggestion components.
  
  Contains utility functions for formatting, validation, text generation,
  and other common operations used across option suggestion components.
  """


  @doc """
  Validates a parameter exists in params map.
  """
  def validate_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      nil -> {:error, "Missing required parameter: #{key}"}
      "" -> {:error, "Empty parameter: #{key}"}
      value -> {:ok, value}
    end
  end
  def validate_param(_params, key), do: {:error, "params is not a map for #{key}"}

  @doc """
  Safely converts a string to integer.
  """
  def safe_string_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_format}
    end
  end
  def safe_string_to_integer(_), do: {:error, :invalid_input}

  @doc """
  Adds a parameter to params map only if value is not nil or empty.
  """
  def maybe_put_param(params, _key, nil), do: params
  def maybe_put_param(params, _key, ""), do: params
  def maybe_put_param(params, key, value), do: Map.put(params, key, value)

  @doc """
  Checks if poll type should use API search functionality.
  """
  def should_use_api_search?(poll_type) do
    poll_type in ["movie", "music"]
  end

  @doc """
  Gets suggest button text based on poll type.
  """
  def suggest_button_text(%{poll_type: poll_type} = _poll) do
    suggest_button_text(poll_type)
  end

  def suggest_button_text(poll_type) when is_binary(poll_type) do
    case poll_type do
      "date_selection" -> "Add Date"
      "movie" -> "Add Movie"
      "music" -> "Add Song"
      "place" -> "Add Place"
      "book" -> "Add Book"
      "general" -> "Add Option"
      _ -> "Add #{String.capitalize(poll_type)}"
    end
  end

  @doc """
  Gets option title label based on poll type.
  """
  def option_title_label(%{poll_type: poll_type} = _poll) do
    option_title_label(poll_type)
  end

  def option_title_label(poll_type) when is_binary(poll_type) do
    case poll_type do
      "date_selection" -> "Date"
      "movie" -> "Movie Title"
      "music" -> "Song Title"
      "place" -> "Place Name"
      "book" -> "Book Title"
      "general" -> "Option"
      _ -> String.capitalize(poll_type)
    end
  end

  @doc """
  Gets option title placeholder based on poll type.
  """
  def option_title_placeholder(%{poll_type: poll_type} = _poll) do
    option_title_placeholder(poll_type)
  end

  def option_title_placeholder(poll_type) when is_binary(poll_type) do
    case poll_type do
      "date_selection" -> "Select a date..."
      "movie" -> "Search for a movie..."
      "music" -> "Search for a song..."
      "place" -> "Enter a place name..."
      "book" -> "Enter a book title..."
      "general" -> "Enter your suggestion..."
      _ -> "Enter #{poll_type}..."
    end
  end

  @doc """
  Gets option description placeholder based on poll type.
  """
  def option_description_placeholder(poll_type) do
    case poll_type do
      "date_selection" -> "Add details about this date..."
      "movie" -> "Why should we watch this movie?"
      "music" -> "Why should we listen to this song?"
      "place" -> "What makes this place special?"
      "book" -> "Why should we read this book?"
      "general" -> "Add more details about this option..."
      _ -> "Add more details..."
    end
  end

  @doc """
  Gets option type text for display.
  """
  def option_type_text(poll_type) do
    case poll_type do
      "date_selection" -> "date"
      "movie" -> "movie"
      "music" -> "song"
      "place" -> "place"
      "book" -> "book"
      "general" -> "option"
      _ -> poll_type
    end
  end

  @doc """
  Formats a datetime relative to now.
  """
  def format_relative_time(datetime) do
    now = DateTime.utc_now()

    # Convert NaiveDateTime to DateTime if needed
    target_datetime = case datetime do
      %NaiveDateTime{} = ndt ->
        DateTime.from_naive!(ndt, "Etc/UTC")
      %DateTime{} = dt ->
        dt
      _ ->
        DateTime.utc_now()
    end

    diff = DateTime.diff(now, target_datetime, :second)
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 2_592_000 -> "#{div(diff, 86400)} days ago"
      true -> "#{div(diff, 2_592_000)} months ago"
    end
  end

  @doc """
  Formats a deadline for display.
  """
  def format_deadline(deadline) do
    case deadline do
      %DateTime{} = dt ->
        Calendar.strftime(dt, "%B %d, %Y at %I:%M %p")
      %NaiveDateTime{} = ndt ->
        Calendar.strftime(ndt, "%B %d, %Y at %I:%M %p")
      _ ->
        "Invalid deadline"
    end
  end

  @doc """
  Gets empty state title based on poll type.
  """
  def get_empty_state_title(poll_type) do
    case poll_type do
      "date_selection" -> "No dates added yet"
      "movie" -> "No movies added yet"
      "music" -> "No songs added yet"
      "place" -> "No places added yet"
      "book" -> "No books added yet"
      "general" -> "No options added yet"
      _ -> "No #{poll_type}s added yet"
    end
  end

  @doc """
  Gets empty state description based on poll type and voting system.
  """
  def get_empty_state_description(poll_type, voting_system) do
    base_action = case voting_system do
      "binary" -> "vote yes or no on"
      "approval" -> "approve"
      "ranked" -> "rank"
      "star" -> "rate"
      _ -> "vote on"
    end

    case poll_type do
      "date_selection" -> "Start by adding dates that people can #{base_action}."
      "movie" -> "Start by adding movies that people can #{base_action}."
      "music" -> "Start by adding songs that people can #{base_action}."
      "place" -> "Start by adding places that people can #{base_action}."
      "book" -> "Start by adding books that people can #{base_action}."
      "general" -> "Start by adding options that people can #{base_action}."
      _ -> "Start by adding #{poll_type}s that people can #{base_action}."
    end
  end

  @doc """
  Gets empty state guidance based on poll type.
  """
  def get_empty_state_guidance(poll_type) do
    case poll_type do
      "date_selection" -> "Use the calendar to select available dates and times."
      "movie" -> "Search for movies or add custom entries."
      "music" -> "Search for songs or add custom entries."
      "place" -> "Search for places or add custom locations."
      "book" -> "Add book titles and authors."
      "general" -> "Add any options you want people to choose between."
      _ -> "Add #{poll_type} options for people to choose from."
    end
  end

  @doc """
  Gets empty state button text based on poll type.
  """
  def get_empty_state_button_text(poll_type) do
    suggest_button_text(poll_type)
  end

  @doc """
  Gets empty state help text based on poll type.
  """
  def get_empty_state_help_text(poll_type) do
    case poll_type do
      "date_selection" -> "💡 Tip: You can add multiple dates at once using the calendar"
      "movie" -> "💡 Tip: Search for movies to get posters and details automatically"
      "music" -> "💡 Tip: Search for songs to get album art and artist info automatically"
      "place" -> "💡 Tip: Use specific addresses for better location details"
      "book" -> "💡 Tip: Include author names to help people identify the right book"
      "general" -> "💡 Tip: Add descriptions to help people understand each option"
      _ -> "💡 Tip: Add detailed descriptions to help people make informed choices"
    end
  end

  @doc """
  Safely encodes data to JSON.
  """
  def safe_json_encode(data) do
    case Jason.encode(data) do
      {:ok, json} -> json
      {:error, _} -> "{}"
    end
  end

  @doc """
  Checks if suggestions are allowed for the current phase.
  """
  def suggestions_allowed_for_phase?(phase) do
    case phase do
      "list_building" -> true
      "voting_with_suggestions" -> true
      "voting" -> true  # Legacy phase support
      _ -> false
    end
  end

  @doc """
  Gets phase suggestion restriction message.
  """
  def get_phase_suggestion_message(phase) do
    case phase do
      "voting_only" -> "Suggestions disabled during voting-only phase"
      "closed" -> "Poll is closed - no more suggestions allowed"
      _ -> nil
    end
  end

  @doc """
  Gets display name for poll phase.
  """
  def get_phase_display_name(phase) do
    case phase do
      "list_building" -> "Building List"
      "voting_with_suggestions" -> "Voting (with suggestions)"
      "voting_only" -> "Voting Only"
      "voting" -> "Voting"  # Legacy phase
      "closed" -> "Closed"
      _ -> String.capitalize(phase)
    end
  end

  @doc """
  Formats a date for display in the UI.
  """
  def format_date_for_display(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} ->
        Calendar.strftime(parsed_date, "%A, %B %d, %Y")
      {:error, _} ->
        date
    end
  end

  @doc """
  Formats a date for use as an option title.
  """
  def format_date_for_option_title(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} ->
        Calendar.strftime(parsed_date, "%A, %B %d")
      {:error, _} ->
        date
    end
  end

  @doc """
  Extracts dates from poll options for calendar display.
  """
  def extract_dates_from_poll_options(poll_options) do
    poll_options
    |> Enum.map(& &1.title)
    |> Enum.filter(&is_valid_date_string?/1)
    |> Enum.map(&Date.from_iso8601!/1)
  end

  defp is_valid_date_string?(string) do
    case Date.from_iso8601(string) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Gets time remaining until option can be deleted (in seconds).
  """
  def get_deletion_time_remaining(inserted_at) when is_nil(inserted_at), do: 0
  def get_deletion_time_remaining(inserted_at) do
    elapsed_seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second)
    max(300 - elapsed_seconds, 0)
  end

  @doc """
  Formats deletion time remaining for display.
  """
  def format_deletion_time_remaining(seconds) when seconds <= 0, do: ""
  def format_deletion_time_remaining(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    
    cond do
      minutes > 0 -> "#{minutes}m #{remaining_seconds}s"
      true -> "#{remaining_seconds}s"
    end
  end

  @doc """
  Gets location scope setting from poll.
  """
  def get_location_scope(poll) do
    poll.settings["location_scope"] || "place"
  end

  @doc """
  Gets search location data as JSON from poll settings.
  """
  def get_search_location_json(poll) do
    case poll.settings["search_location_data"] do
      nil -> "{}"
      data when is_map(data) -> safe_json_encode(data)
      json when is_binary(json) -> json
      _ -> "{}"
    end
  end

  @doc """
  Checks if description appears to be enhanced with rich data.
  """
  def has_enhanced_description?(description) when is_binary(description) do
    enhanced_indicators = [
      "Runtime:", "Director:", "Cast:", "Genre:", "Release Date:",
      "Artist:", "Album:", "Duration:", "Released:"
    ]
    
    Enum.any?(enhanced_indicators, &String.contains?(description, &1))
  end
  def has_enhanced_description?(_), do: false

  @doc """
  Preserves user input over API data when user has provided meaningful content.
  """
  def maybe_preserve_user_input(prepared_data, key, user_value) when is_binary(user_value) and user_value != "" do
    # Only preserve if user value is substantially different from API value
    api_value = Map.get(prepared_data, key, "")
    
    cond do
      String.length(user_value) > String.length(api_value) * 1.5 -> 
        Map.put(prepared_data, key, user_value)
      has_enhanced_description?(user_value) and not has_enhanced_description?(api_value) ->
        Map.put(prepared_data, key, user_value)
      true -> 
        prepared_data
    end
  end
  def maybe_preserve_user_input(prepared_data, _key, _user_value), do: prepared_data

  @doc """
  Gets movie poster URL from movie data.
  """
  def get_movie_poster_url(movie) do
    cond do
      movie.poster_path && movie.poster_path != "" -> 
        "https://image.tmdb.org/t/p/w200#{movie.poster_path}"
      movie.image_url && movie.image_url != "" -> 
        movie.image_url
      true -> 
        nil
    end
  end

  @doc """
  Available time options for time selection.
  """
  def time_options do
    [
      {"6:00 AM", "06:00"},
      {"6:30 AM", "06:30"},
      {"7:00 AM", "07:00"},
      {"7:30 AM", "07:30"},
      {"8:00 AM", "08:00"},
      {"8:30 AM", "08:30"},
      {"9:00 AM", "09:00"},
      {"9:30 AM", "09:30"},
      {"10:00 AM", "10:00"},
      {"10:30 AM", "10:30"},
      {"11:00 AM", "11:00"},
      {"11:30 AM", "11:30"},
      {"12:00 PM", "12:00"},
      {"12:30 PM", "12:30"},
      {"1:00 PM", "13:00"},
      {"1:30 PM", "13:30"},
      {"2:00 PM", "14:00"},
      {"2:30 PM", "14:30"},
      {"3:00 PM", "15:00"},
      {"3:30 PM", "15:30"},
      {"4:00 PM", "16:00"},
      {"4:30 PM", "16:30"},
      {"5:00 PM", "17:00"},
      {"5:30 PM", "17:30"},
      {"6:00 PM", "18:00"},
      {"6:30 PM", "18:30"},
      {"7:00 PM", "19:00"},
      {"7:30 PM", "19:30"},
      {"8:00 PM", "20:00"},
      {"8:30 PM", "20:30"},
      {"9:00 PM", "21:00"},
      {"9:30 PM", "21:30"},
      {"10:00 PM", "22:00"},
      {"10:30 PM", "22:30"},
      {"11:00 PM", "23:00"},
      {"11:30 PM", "23:30"}
    ]
  end

  @doc """
  Formats time for display (converts 24h to 12h format with AM/PM).
  """
  def format_time_for_display(time) do
    case Time.from_iso8601("#{time}:00") do
      {:ok, parsed_time} ->
        Calendar.strftime(parsed_time, "%I:%M %p")
        |> String.replace_leading("0", "")
      {:error, _} ->
        time
    end
  end

  @doc """
  Checks for duplicate options (placeholder for future enhancement).
  """
  def check_for_duplicates(_poll, _option) do
    # Placeholder for duplicate detection logic
    :ok
  end
end