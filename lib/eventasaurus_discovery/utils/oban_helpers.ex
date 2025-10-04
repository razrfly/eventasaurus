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
    # Keep essential fields for debugging AND preserve ticket type metadata
    base_fields = %{
      "external_id" => Map.get(event_data, "external_id", "[missing]"),
      "title" => event_data |> Map.get("title", "") |> String.slice(0, 100),
      "starts_at" => Map.get(event_data, "starts_at"),
      "status" => Map.get(event_data, "status", "unknown")
    }

    # Preserve critical ticket type metadata from Ticketmaster
    metadata = Map.get(event_data, "metadata", %{})

    preserved_metadata =
      if is_map(metadata) do
        ticketmaster_data = Map.get(metadata, "ticketmaster_data", %{})

        if is_map(ticketmaster_data) do
          # Extract and preserve ONLY the ticket-critical fields
          preserved_tm_data = %{}

          # Preserve products (contains ticket type names!)
          preserved_tm_data =
            if products = Map.get(ticketmaster_data, "products") do
              Map.put(preserved_tm_data, "products", products)
            else
              preserved_tm_data
            end

          # Preserve price_ranges (pricing tiers for different ticket types)
          preserved_tm_data =
            if price_ranges = Map.get(ticketmaster_data, "price_ranges") do
              Map.put(preserved_tm_data, "price_ranges", price_ranges)
            else
              preserved_tm_data
            end

          # Only include metadata if we have something to preserve
          if map_size(preserved_tm_data) > 0 do
            %{"ticketmaster_data" => preserved_tm_data}
          else
            %{}
          end
        else
          %{}
        end
      else
        %{}
      end

    # Add metadata to base fields if we have any to preserve
    if map_size(preserved_metadata) > 0 do
      Map.put(base_fields, "metadata", preserved_metadata)
    else
      base_fields
    end
  end

  defp truncate_event_data(data), do: data
end
