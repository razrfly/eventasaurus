defmodule EventasaurusWeb.Helpers.VenueHelpers do
  @moduledoc """
  Shared helpers for venue display logic across mobile API controllers.
  """

  @doc """
  Returns the venue's trimmed name when it is a non-empty binary,
  otherwise returns a fallback string.
  """
  @spec venue_display_name(any(), String.t()) :: String.t()
  def venue_display_name(name, fallback \\ "Unknown Venue")

  def venue_display_name(name, fallback) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed != "", do: name, else: fallback
  end

  def venue_display_name(_name, fallback), do: fallback
end
