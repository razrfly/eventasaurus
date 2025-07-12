defmodule EventasaurusWeb.PollView do
  @moduledoc """
  Utility functions for poll display helpers.
  """

  @emoji_map %{
    "movie" => "🎬",
    "places" => "📍",
    "time" => "⏰",
    "custom" => "📝"
  }

  @doc """
  Returns the emoji for the given poll type.
  Falls back to 📝 for any unknown type.
  """
  def poll_emoji(type), do: Map.get(@emoji_map, type, "📝")
end
