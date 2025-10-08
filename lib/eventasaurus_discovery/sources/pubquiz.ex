defmodule EventasaurusDiscovery.Sources.Pubquiz do
  @moduledoc """
  PubQuiz.pl API integration for recurring trivia event discovery.

  PubQuiz is a Polish trivia night source (priority 50) providing:
  - Weekly recurring trivia events
  - Venue location data
  - Host and schedule information
  - Poland-wide coverage

  ## Features
  - Recurring event pattern detection
  - Venue-based deduplication
  - Schedule matching for recurring events
  - GPS coordinate validation
  - Cross-source deduplication

  ## Priority System
  PubQuiz has priority 50, so it defers to:
  - Ticketmaster (90)
  - Bandsintown (80)
  - Resident Advisor (75)
  - Karnet (60)
  """

  alias EventasaurusDiscovery.Sources.Pubquiz.DedupHandler

  @doc """
  Process a PubQuiz event through deduplication.

  Two-phase deduplication strategy:
  - Phase 1: Check if THIS source already imported it (same-source dedup)
  - Phase 2: Check if higher-priority source imported it (cross-source fuzzy match)

  ## Parameters
  - `event_data` - Event data with external_id, title, starts_at, venue_data
  - `source_id` - ID of the PubQuiz source

  ## Returns
  - `{:unique, event_data}` - Event is unique, proceed with import
  - `{:duplicate, existing}` - Event already exists (same source or higher priority)
  - `{:error, reason}` - Event validation failed
  """
  def deduplicate_event(event_data, source) do
    case DedupHandler.validate_event_quality(event_data) do
      {:ok, validated} ->
        DedupHandler.check_duplicate(validated, source)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the source configuration.
  """
  def config do
    %{
      priority: 50,
      name: "PubQuiz",
      slug: "pubquiz-pl",
      type: :scraper,
      provides_gps: true,
      provides_recurring: true,
      coverage: :poland
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
        {:error, "PubQuiz source is disabled"}

      true ->
        {:ok, "PubQuiz source configuration valid"}
    end
  end
end
