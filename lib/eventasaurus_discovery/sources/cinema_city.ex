defmodule EventasaurusDiscovery.Sources.CinemaCity do
  @moduledoc """
  Cinema City API integration for movie showtime discovery.

  Cinema City is a regional cinema chain source (priority 15) providing:
  - Movie showtimes from Cinema City theaters
  - TMDB-enriched movie metadata
  - Cinema location data
  - Poland-wide coverage (32+ locations)

  ## Features
  - JSON API-based event discovery
  - GPS coordinates for cinema locations
  - Comprehensive movie metadata via TMDB
  - Showtime and screening format details
  - Cross-source deduplication

  ## Priority System
  Cinema City has priority 15, so it defers to:
  - Ticketmaster (90)
  - Bandsintown (80)
  - Resident Advisor (75)
  - Karnet (60)
  - PubQuiz (50)
  """

  alias EventasaurusDiscovery.Sources.CinemaCity.DedupHandler

  @doc """
  Process a Cinema City event through deduplication.

  Two-phase deduplication strategy:
  - Phase 1: Check if THIS source already imported it (same-source dedup)
  - Phase 2: Check if higher-priority source imported it (cross-source fuzzy match)

  ## Parameters
  - `event_data` - Event data with external_id, title, starts_at, venue_data
  - `source` - The Source struct (with priority and domains)

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
      priority: 15,
      name: "Cinema City",
      slug: "cinema-city",
      type: :api,
      provides_gps: true,
      provides_movies: true,
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
        {:error, "Cinema City source is disabled"}

      true ->
        {:ok, "Cinema City source configuration valid"}
    end
  end
end
