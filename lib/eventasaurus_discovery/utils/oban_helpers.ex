defmodule EventasaurusDiscovery.Utils.ObanHelpers do
  @moduledoc """
  Helper functions for Oban job processing and debugging.
  """

  @doc """
  Truncates large metadata fields in job args for cleaner error display.
  Keeps only essential fields for debugging.
  """
  def truncate_job_args(args) when is_map(args) do
    args
    |> Map.update("event_data", %{}, &truncate_event_data/1)
    |> Map.update("raw_event_data", "[truncated]", fn _ -> "[truncated]" end)
  end

  def truncate_job_args(args), do: args

  defp truncate_event_data(event_data) when is_map(event_data) do
    event_data
    |> Map.take(["external_id", "title", "starts_at", "venue_data", "category_id", "status"])
    |> Map.update("venue_data", %{}, &truncate_venue_data/1)
    |> Map.put("metadata", "[truncated]")
    |> Map.put("performers", "[truncated]")
    |> Map.put("title_translations", "[truncated]")
    |> Map.put("description_translations", "[truncated]")
  end

  defp truncate_event_data(data), do: data

  defp truncate_venue_data(venue_data) when is_map(venue_data) do
    Map.take(venue_data, ["name", "city", "country", "external_id", "latitude", "longitude"])
  end

  defp truncate_venue_data(data), do: data
end