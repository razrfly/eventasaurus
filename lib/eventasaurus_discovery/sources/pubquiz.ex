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

  Checks if event exists from any source (including PubQuiz itself).
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
