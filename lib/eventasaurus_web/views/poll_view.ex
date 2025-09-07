defmodule EventasaurusWeb.PollView do
  @moduledoc """
  Utility functions for poll display helpers.
  """

  @emoji_map %{
    "movie" => "🎬",
    "places" => "📍",
    "time" => "⏰",
    "date_selection" => "📅",
    "custom" => "📝",
    "music_track" => "🎵",
    "music_artist" => "🎤",
    "music_album" => "💿",
    "music_playlist" => "🎶"
  }

  @doc """
  Returns the emoji for the given poll type.
  Falls back to 📝 for any unknown type.
  """
  def poll_emoji(type), do: Map.get(@emoji_map, type, "📝")
end
