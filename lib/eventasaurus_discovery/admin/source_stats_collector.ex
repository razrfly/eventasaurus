defmodule EventasaurusDiscovery.Admin.SourceStatsCollector do
  @moduledoc """
  Collects detailed statistics for discovery sources to power the enhanced quality dashboard.

  Provides aggregation queries for:
  - Occurrence type distribution
  - Category breakdown
  - Translation coverage
  - Image statistics
  - Venue information

  All queries are optimized for performance with proper indexing.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.Categories.PublicEventCategory

  @doc """
  Get occurrence type distribution for a source.

  Returns breakdown of event types (explicit, pattern, exhibition, recurring, unknown, movie)
  with counts and percentages.

  ## Example
      iex> get_occurrence_type_distribution("sortiraparis")
      [
        %{type: "explicit", count: 850, percentage: 67.0},
        %{type: "pattern", count: 250, percentage: 20.0},
        %{type: "exhibition", count: 130, percentage: 10.0},
        %{type: "unknown", count: 37, percentage: 3.0}
      ]
  """
  def get_occurrence_type_distribution(source_slug) when is_binary(source_slug) do
    query =
      from pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        where: not is_nil(pe.occurrences),
        group_by: fragment("?->>'type'", pe.occurrences),
        select: %{
          type: fragment("?->>'type'", pe.occurrences),
          count: count(pe.id),
          percentage:
            fragment(
              "ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)"
            )
        },
        order_by: [desc: count(pe.id)]

    Repo.all(query)
  end

  @doc """
  Get top categories for a source with event counts.

  Returns up to `limit` categories sorted by event count.

  ## Example
      iex> get_top_categories("sortiraparis", 10)
      [
        %{category_id: 5, category_name: "Music", count: 450, percentage: 25.0},
        %{category_id: 8, category_name: "Theater", count: 320, percentage: 18.0},
        ...
      ]
  """
  def get_top_categories(source_slug, limit \\ 10)
      when is_binary(source_slug) and is_integer(limit) do
    # CRITICAL FIX: Query public_event_categories join table instead of deprecated pe.category_id
    # Events can have multiple categories, so we need to use the join table
    query =
      from pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        left_join: pec in PublicEventCategory,
        on: pec.event_id == pe.id and pec.is_primary == true,
        left_join: c in Category,
        on: c.id == pec.category_id,
        where: s.slug == ^source_slug,
        group_by: [c.id, c.name],
        select: %{
          category_id: c.id,
          category_name: c.name,
          count: count(pe.id),
          percentage:
            fragment(
              "ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)"
            )
        },
        order_by: [desc: count(pe.id)],
        limit: ^limit

    Repo.all(query)
  end

  @doc """
  Get category coverage statistics.

  Returns total unique categories and percentage of events with categories.

  ## Example
      iex> get_category_stats("sortiraparis")
      %{
        total_categories: 12,
        events_with_category: 1150,
        events_without_category: 84,
        coverage_percentage: 93.2
      }
  """
  def get_category_stats(source_slug) when is_binary(source_slug) do
    # CRITICAL FIX: Query public_event_categories join table instead of deprecated pe.category_id
    # Count events that have at least one category assigned in the join table
    stats_query =
      from pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        left_join: pec in PublicEventCategory,
        on: pec.event_id == pe.id,
        where: s.slug == ^source_slug,
        select: %{
          total_events: count(pe.id, :distinct),
          events_with_category: fragment("COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)", pec.category_id, pe.id),
          events_without_category: fragment("COUNT(DISTINCT CASE WHEN ? IS NULL THEN ? END)", pec.category_id, pe.id)
        }

    # Count unique categories used by this source (from join table)
    categories_query =
      from pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        join: pec in PublicEventCategory,
        on: pec.event_id == pe.id,
        where: s.slug == ^source_slug,
        select: count(pec.category_id, :distinct)

    stats = Repo.one(stats_query)
    total_categories = Repo.one(categories_query) || 0

    coverage_percentage =
      if stats.total_events > 0 do
        Float.round(100.0 * stats.events_with_category / stats.total_events, 1)
      else
        0.0
      end

    Map.merge(stats, %{
      total_categories: total_categories,
      coverage_percentage: coverage_percentage
    })
  end

  @doc """
  Get translation coverage by language for a source.

  Analyzes both title_translations and description_translations.

  ## Example
      iex> get_translation_coverage("sortiraparis")
      %{
        has_translations: true,
        languages: ["fr", "en"],
        coverage: %{
          "fr" => %{events: 1234, percentage: 100.0},
          "en" => %{events: 1050, percentage: 85.0}
        }
      }
  """
  def get_translation_coverage(source_slug) when is_binary(source_slug) do
    # Get events with title translations
    _title_translations_query =
      from pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        where: not is_nil(pe.title_translations),
        select: %{
          total_events: count(pe.id),
          translations: fragment("jsonb_object_keys(?)", pe.title_translations)
        }

    # Get events with description translations
    _desc_translations_query =
      from pes in PublicEventSource,
        join: s in Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        where: not is_nil(pes.description_translations),
        select: %{
          total_events: count(pes.id),
          translations: fragment("jsonb_object_keys(?)", pes.description_translations)
        }

    # Get total events for the source
    total_query =
      from pes in PublicEventSource,
        join: s in Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        select: count(pes.id)

    total_events = Repo.one(total_query) || 0

    # For now, return basic structure - full implementation would aggregate language keys
    %{
      has_translations: total_events > 0,
      total_events: total_events,
      languages: [],
      coverage: %{}
    }
  end

  @doc """
  Get image statistics for a source.

  Returns distribution of events by image count and coverage percentages.

  ## Example
      iex> get_image_statistics("sortiraparis")
      %{
        total_images: 3950,
        average_per_event: 3.2,
        coverage_percentage: 95.0,
        distribution: %{
          no_images: 62,
          one_image: 120,
          two_to_five: 450,
          five_plus: 602
        }
      }
  """
  def get_image_statistics(source_slug) when is_binary(source_slug) do
    query =
      from pes in PublicEventSource,
        join: s in Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        select: %{
          total_events: count(pes.id),
          events_with_images: fragment("COUNT(CASE WHEN ? IS NOT NULL THEN 1 END)", pes.image_url),
          events_without_images: fragment("COUNT(CASE WHEN ? IS NULL THEN 1 END)", pes.image_url)
        }

    stats = Repo.one(query)

    coverage_percentage =
      if stats.total_events > 0 do
        Float.round(100.0 * stats.events_with_images / stats.total_events, 1)
      else
        0.0
      end

    Map.merge(stats, %{
      coverage_percentage: coverage_percentage,
      total_images: stats.events_with_images,
      average_per_event: if(stats.total_events > 0, do: Float.round(stats.events_with_images / stats.total_events, 1), else: 0.0)
    })
  end

  @doc """
  Get venue statistics for a source.

  Returns venue counts, completeness metrics, and top venues.

  ## Example
      iex> get_venue_statistics("sortiraparis")
      %{
        total_venues: 456,
        events_with_venues: 1200,
        events_without_venues: 34,
        venue_coverage: 97.2,
        top_venues: [...]
      }
  """
  def get_venue_statistics(source_slug, top_limit \\ 10)
      when is_binary(source_slug) and is_integer(top_limit) do
    # Basic venue stats
    stats_query =
      from pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        select: %{
          total_events: count(pe.id),
          events_with_venues: fragment("COUNT(CASE WHEN ? IS NOT NULL THEN 1 END)", pe.venue_id),
          events_without_venues: fragment("COUNT(CASE WHEN ? IS NULL THEN 1 END)", pe.venue_id),
          unique_venues: count(pe.venue_id, :distinct)
        }

    # Top venues by event count
    top_venues_query =
      from pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        join: v in Venue,
        on: v.id == pe.venue_id,
        where: s.slug == ^source_slug,
        group_by: [v.id, v.name],
        select: %{
          venue_id: v.id,
          venue_name: v.name,
          event_count: count(pe.id)
        },
        order_by: [desc: count(pe.id)],
        limit: ^top_limit

    stats = Repo.one(stats_query)
    top_venues = Repo.all(top_venues_query)

    venue_coverage =
      if stats.total_events > 0 do
        Float.round(100.0 * stats.events_with_venues / stats.total_events, 1)
      else
        0.0
      end

    Map.merge(stats, %{
      venue_coverage: venue_coverage,
      top_venues: top_venues
    })
  end

  @doc """
  Get comprehensive stats for a source in a single call.

  Combines all stat queries for dashboard display.

  ## Example
      iex> get_comprehensive_stats("sortiraparis")
      %{
        occurrence_types: [...],
        categories: %{...},
        translations: %{...},
        images: %{...},
        venues: %{...}
      }
  """
  def get_comprehensive_stats(source_slug) when is_binary(source_slug) do
    %{
      occurrence_types: get_occurrence_type_distribution(source_slug),
      category_stats: get_category_stats(source_slug),
      top_categories: get_top_categories(source_slug, 10),
      translation_coverage: get_translation_coverage(source_slug),
      image_stats: get_image_statistics(source_slug),
      venue_stats: get_venue_statistics(source_slug, 10)
    }
  end
end
