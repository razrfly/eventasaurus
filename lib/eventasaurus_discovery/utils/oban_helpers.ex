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
    # Only keep absolutely essential fields for debugging
    %{
      "external_id" => Map.get(event_data, "external_id", "[missing]"),
      "title" => event_data |> Map.get("title", "") |> String.slice(0, 50),
      "starts_at" => Map.get(event_data, "starts_at"),
      "status" => Map.get(event_data, "status", "unknown")
    }
  end

  defp truncate_event_data(data), do: data
end