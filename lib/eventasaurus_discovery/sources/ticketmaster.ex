defmodule EventasaurusDiscovery.Sources.Ticketmaster do
  @moduledoc """
  Ticketmaster API integration for event discovery.

  Ticketmaster is the highest-priority source (priority 90) providing:
  - Official ticketing data
  - Venue seating information
  - Artist tour schedules
  - International event coverage

  ## Features
  - API-based event discovery
  - GPS coordinates for all venues
  - Comprehensive event metadata
  - Ticket pricing and availability
  - Cross-source deduplication
  """

  alias EventasaurusDiscovery.Sources.Ticketmaster.DedupHandler

  @doc """
  Process a Ticketmaster event through deduplication.

  Checks if event exists from any source (including Ticketmaster itself).
  Validates event quality before processing.

  Returns:
  - `{:unique, event_data}` - Event is unique, proceed with import
  - `{:duplicate, existing}` - Event already exists (same external_id or fuzzy match)
  - `{:error, reason}` - Event validation failed
  """
  def deduplicate_event(event_data) do
    case DedupHandler.validate_event_quality(event_data) do
      {:ok, validated} ->
        DedupHandler.check_duplicate(validated)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the source configuration.
  """
  def config do
    %{
      priority: 90,
      name: "Ticketmaster",
      slug: "ticketmaster",
      type: :api,
      provides_gps: true,
      provides_tickets: true,
      coverage: :international
    }
  end

  @doc """
  Check if the source is enabled.
  """
  def enabled?, do: true

  @doc """
  Validate source configuration.
  """
  def validate do
    cond do
      !enabled?() ->
        {:error, "Ticketmaster source is disabled"}

      true ->
        {:ok, "Ticketmaster source configuration valid"}
    end
  end
end
