defmodule EventasaurusDiscovery.Workers.PostHogPopularitySyncWorker do
  @moduledoc """
  Oban worker that syncs PostHog pageview data to database for popularity sorting.

  This worker:
  1. Queries PostHog for unique visitors per page (last 7 days)
  2. Parses URL paths to extract entity slugs (events, movies, venues, performers)
  3. Batch updates the `posthog_view_count` column on respective tables

  ## Scheduling

  Configured to run daily at 3am UTC via Oban cron. Can also be triggered manually:

      # In IEx
      %{}
      |> EventasaurusDiscovery.Workers.PostHogPopularitySyncWorker.new()
      |> Oban.insert()

  ## Configuration

  Requires PostHog API credentials:
  - `POSTHOG_PRIVATE_API_KEY` - Personal API key for HogQL queries
  - `POSTHOG_PROJECT_ID` - PostHog project ID

  ## Metrics

  Logs summary statistics after each sync:
  - Number of entities updated per type
  - Total view counts synced
  - Any errors encountered

  """

  use Oban.Worker,
    queue: :analytics,
    max_attempts: 3,
    # 10 minute timeout for slow PostHog queries
    priority: 3

  require Logger
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusDiscovery.PostHog.{PathParser, ViewCountQuery}
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    days = Map.get(args, "days", 7)
    Logger.info("Starting PostHog popularity sync for last #{days} days")

    case sync_all_view_counts(days) do
      {:ok, stats} ->
        Logger.info(
          "PostHog popularity sync completed: " <>
            "#{stats.events_updated} events, #{stats.movies_updated} movies, " <>
            "#{stats.venues_updated} venues, #{stats.performers_updated} performers updated"
        )

        {:ok, stats}

      {:error, reason} ->
        Logger.error("PostHog popularity sync failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run the sync for all entity types manually with options.

  ## Options

  - `:days` - Number of days to look back (default: 7)
  - `:dry_run` - If true, don't update database (default: false)

  ## Examples

      iex> PostHogPopularitySyncWorker.sync_all_view_counts(7)
      {:ok, %{events_updated: 150, movies_updated: 45, venues_updated: 30, performers_updated: 60}}

      iex> PostHogPopularitySyncWorker.sync_all_view_counts(30, dry_run: true)
      {:ok, %{events_updated: 0, movies_updated: 0, ..., dry_run: true}}

  """
  @spec sync_all_view_counts(integer(), keyword()) :: {:ok, map()} | {:error, any()}
  def sync_all_view_counts(days \\ 7, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, view_counts} <- ViewCountQuery.get_all_view_counts(days) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Process and sync each entity type
      event_stats = sync_entity_type(view_counts, :event, PublicEvent, dry_run, now)
      movie_stats = sync_entity_type(view_counts, :movie, Movie, dry_run, now)
      venue_stats = sync_entity_type(view_counts, :venue, Venue, dry_run, now)
      performer_stats = sync_entity_type(view_counts, :performer, Performer, dry_run, now)

      stats = %{
        events_updated: event_stats.updated,
        events_total_views: event_stats.total_views,
        movies_updated: movie_stats.updated,
        movies_total_views: movie_stats.total_views,
        venues_updated: venue_stats.updated,
        venues_total_views: venue_stats.total_views,
        performers_updated: performer_stats.updated,
        performers_total_views: performer_stats.total_views,
        dry_run: dry_run
      }

      {:ok, stats}
    end
  end

  @doc """
  Run the sync for events only (backward compatible).

  ## Options

  - `:days` - Number of days to look back (default: 7)
  - `:dry_run` - If true, don't update database (default: false)

  """
  @spec sync_view_counts(integer(), keyword()) :: {:ok, map()} | {:error, any()}
  def sync_view_counts(days \\ 7, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, view_counts} <- ViewCountQuery.get_event_view_counts(days) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      stats = sync_entity_type(view_counts, :event, PublicEvent, dry_run, now)

      {:ok, %{
        events_updated: stats.updated,
        total_views: stats.total_views,
        dry_run: dry_run
      }}
    end
  end

  # Sync a single entity type
  defp sync_entity_type(view_counts, entity_type, schema, dry_run, now) do
    filter_fn = get_filter_fn(entity_type)
    slug_counts = view_counts |> filter_fn.() |> PathParser.aggregate_by_slug()

    total_views = slug_counts |> Map.values() |> Enum.sum()

    if dry_run || map_size(slug_counts) == 0 do
      %{updated: 0, total_views: total_views, would_update: map_size(slug_counts)}
    else
      updated = update_entity_view_counts(slug_counts, schema, now)
      %{updated: updated, total_views: total_views}
    end
  end

  # Get the appropriate filter function for each entity type
  defp get_filter_fn(:event), do: &PathParser.filter_events/1
  defp get_filter_fn(:movie), do: &PathParser.filter_movies/1
  defp get_filter_fn(:venue), do: &PathParser.filter_venues/1
  defp get_filter_fn(:performer), do: &PathParser.filter_performers/1

  # Update view counts for a schema
  defp update_entity_view_counts(slug_counts, schema, now) do
    chunk_size = 100

    slug_counts
    |> Map.keys()
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(fn chunk_slugs ->
      update_chunk(chunk_slugs, slug_counts, schema, now)
    end)
    |> Enum.sum()
  end

  defp update_chunk(slugs, slug_counts, schema, now) do
    Enum.reduce(slugs, 0, fn slug, count ->
      view_count = Map.get(slug_counts, slug, 0)

      case update_by_slug(schema, slug, view_count, now) do
        {:ok, updated_count} ->
          count + updated_count

        {:error, reason} ->
          Logger.warning("Failed to update view count for #{inspect(schema)} slug '#{slug}': #{inspect(reason)}")
          count
      end
    end)
  end

  defp update_by_slug(schema, slug, view_count, now) do
    query =
      from(e in schema,
        where: e.slug == ^slug,
        update: [set: [posthog_view_count: ^view_count, posthog_synced_at: ^now]]
      )

    case Repo.update_all(query, []) do
      {count, _} when count >= 0 ->
        {:ok, count}

      error ->
        {:error, error}
    end
  end

  @doc """
  Get current view count statistics from the database.

  Returns a summary of popularity data:
  - Total events with view counts
  - Events by view count tier
  - Last sync time

  """
  @spec get_stats() :: map()
  def get_stats do
    total_with_views =
      Repo.one(
        from(e in PublicEvent,
          where: e.posthog_view_count > 0,
          select: count(e.id)
        )
      )

    total_views =
      Repo.one(
        from(e in PublicEvent,
          select: coalesce(sum(e.posthog_view_count), 0)
        )
      )

    last_sync =
      Repo.one(
        from(e in PublicEvent,
          where: not is_nil(e.posthog_synced_at),
          select: max(e.posthog_synced_at)
        )
      )

    # View count tiers
    tiers =
      Repo.all(
        from(e in PublicEvent,
          where: e.posthog_view_count > 0,
          select: %{
            tier:
              fragment(
                "CASE WHEN posthog_view_count >= 100 THEN 'high' WHEN posthog_view_count >= 10 THEN 'medium' ELSE 'low' END"
              ),
            count: count(e.id)
          },
          group_by:
            fragment(
              "CASE WHEN posthog_view_count >= 100 THEN 'high' WHEN posthog_view_count >= 10 THEN 'medium' ELSE 'low' END"
            )
        )
      )
      |> Enum.map(fn %{tier: tier, count: count} -> {tier, count} end)
      |> Map.new()

    %{
      total_events_with_views: total_with_views,
      total_views: total_views,
      last_sync: last_sync,
      tiers: tiers
    }
  end

  @doc """
  Get top events by view count.

  ## Parameters

  - `limit` - Number of events to return (default: 20)

  """
  @spec top_events(integer()) :: [map()]
  def top_events(limit \\ 20) do
    Repo.all(
      from(e in PublicEvent,
        where: e.posthog_view_count > 0,
        order_by: [desc: e.posthog_view_count],
        limit: ^limit,
        select: %{
          id: e.id,
          slug: e.slug,
          title: e.title,
          posthog_view_count: e.posthog_view_count,
          posthog_synced_at: e.posthog_synced_at
        }
      )
    )
  end
end
