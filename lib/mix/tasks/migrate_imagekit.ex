defmodule Mix.Tasks.MigrateImagekit do
  @moduledoc """
  Migrates venue images from ImageKit to Cloudflare R2 storage.

  This task queues venues for image migration from the `venue_images` JSONB
  column to the new `cached_images` table backed by R2.

  ## Usage

      # Show current migration status
      mix migrate_imagekit --status

      # Dry run - show what would be migrated without doing anything
      mix migrate_imagekit --dry-run

      # Migrate a specific venue (for testing)
      mix migrate_imagekit --venue-id 123

      # Migrate all venues with images (in batches)
      mix migrate_imagekit --all

      # Migrate with custom batch size and limit
      mix migrate_imagekit --all --limit 500 --batch-size 20

      # Show venues pending migration
      mix migrate_imagekit --pending

  ## Options

      --status       Show migration statistics
      --dry-run      Show what would be migrated without queueing jobs
      --venue-id     Migrate a specific venue by ID
      --all          Migrate all venues with images
      --limit        Maximum venues to process (default: 100)
      --batch-size   Venues per batch (default: 10)
      --pending      Show list of venues pending migration
      --priority     Oban job priority 1-3 (default: 2)

  ## Safety

  This task only queues migration jobs. The actual migration is performed
  by background workers. The original `venue_images` JSONB is never modified.
  """

  use Mix.Task

  @shortdoc "Migrate venue images from ImageKit to R2"

  @switches [
    status: :boolean,
    dry_run: :boolean,
    venue_id: :integer,
    all: :boolean,
    limit: :integer,
    batch_size: :integer,
    pending: :boolean,
    priority: :integer
  ]

  @aliases [
    s: :status,
    n: :dry_run,
    v: :venue_id,
    a: :all,
    l: :limit,
    b: :batch_size,
    p: :pending
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _remaining, _invalid} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    # Start the application
    Mix.Task.run("app.start")

    cond do
      opts[:status] ->
        show_status()

      opts[:pending] ->
        show_pending(opts)

      opts[:venue_id] ->
        migrate_single_venue(opts[:venue_id], opts)

      opts[:all] || opts[:dry_run] ->
        migrate_all(opts)

      true ->
        show_help()
    end
  end

  defp show_status do
    alias EventasaurusApp.Images.VenueImageMigrator

    IO.puts("\n📊 ImageKit to R2 Migration Status")
    IO.puts("=" |> String.duplicate(50))

    stats = VenueImageMigrator.status()

    IO.puts("\n📁 Source Data (venue_images JSONB):")
    IO.puts("   Venues with images: #{stats.total_venues_with_images}")
    IO.puts("   Total images: #{stats.total_images_in_jsonb}")

    IO.puts("\n📦 Cached Images (R2):")
    IO.puts("   Pending:     #{stats.cached_images.pending}")
    IO.puts("   Downloading: #{stats.cached_images.downloading}")
    IO.puts("   Cached:      #{stats.cached_images.cached}")
    IO.puts("   Failed:      #{stats.cached_images.failed}")
    IO.puts("   Total:       #{stats.cached_images.total}")

    IO.puts("\n📈 Progress:")
    IO.puts("   Venues touched: #{stats.venues_with_cached_images}")
    IO.puts("   Venues fully migrated: #{stats.venues_fully_migrated}")
    IO.puts("   Migration percentage: #{stats.migration_percentage}%")

    progress_bar = build_progress_bar(stats.migration_percentage)
    IO.puts("   [#{progress_bar}]")

    IO.puts("")
  end

  defp show_pending(opts) do
    alias EventasaurusApp.Images.VenueImageMigrator

    limit = opts[:limit] || 50
    venues = VenueImageMigrator.pending_venues(limit: limit)

    IO.puts("\n📋 Venues Pending Migration (showing #{length(venues)} of max #{limit})")
    IO.puts("=" |> String.duplicate(70))

    if Enum.empty?(venues) do
      IO.puts("\n✅ No venues pending migration!")
    else
      IO.puts("")
      IO.puts("ID      | Slug                                  | Total | Cached | Pending")
      IO.puts("-" |> String.duplicate(70))

      Enum.each(venues, fn v ->
        slug = String.pad_trailing(v.slug || "(no slug)", 37)
        id = String.pad_leading(Integer.to_string(v.id), 7)
        total = String.pad_leading(Integer.to_string(v.image_count), 5)
        cached = String.pad_leading(Integer.to_string(v.cached_count), 6)
        pending = String.pad_leading(Integer.to_string(v.pending_count), 7)
        IO.puts("#{id} | #{slug} | #{total} | #{cached} | #{pending}")
      end)
    end

    IO.puts("")
  end

  defp migrate_single_venue(venue_id, opts) do
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Venues.Venue
    alias EventasaurusApp.Images.VenueImageMigrator

    dry_run = opts[:dry_run] || false
    priority = opts[:priority] || 2

    IO.puts("\n🔍 Migrating venue #{venue_id}#{if dry_run, do: " (DRY RUN)", else: ""}")
    IO.puts("=" |> String.duplicate(50))

    case Repo.get(Venue, venue_id) do
      nil ->
        IO.puts("\n❌ Venue not found: #{venue_id}")

      venue ->
        IO.puts("\nVenue: #{venue.name}")
        IO.puts("Slug: #{venue.slug}")
        IO.puts("Images in JSONB: #{length(venue.venue_images || [])}")

        {:ok, stats} = VenueImageMigrator.migrate_venue(venue, dry_run: dry_run, priority: priority)

        IO.puts("\n✅ Migration #{if dry_run, do: "would queue", else: "queued"}:")
        IO.puts("   Queued: #{stats.queued}")
        IO.puts("   Skipped (already exists): #{stats.skipped}")
        IO.puts("   Errors: #{stats.errors}")
    end

    IO.puts("")
  end

  defp migrate_all(opts) do
    alias EventasaurusApp.Images.VenueImageMigrator

    dry_run = opts[:dry_run] || false
    limit = opts[:limit] || 100
    batch_size = opts[:batch_size] || 10
    priority = opts[:priority] || 2

    IO.puts(
      "\n🚀 Queueing venue migration#{if dry_run, do: " (DRY RUN)", else: ""}"
    )
    IO.puts("=" |> String.duplicate(50))
    IO.puts("\nOptions:")
    IO.puts("   Limit: #{limit} venues")
    IO.puts("   Batch size: #{batch_size}")
    IO.puts("   Priority: #{priority}")

    {:ok, stats} =
      VenueImageMigrator.queue_migration(
        dry_run: dry_run,
        limit: limit,
        batch_size: batch_size,
        priority: priority
      )

    IO.puts("\n✅ Result:")
    IO.puts("   Venues found: #{stats.venues_found}")
    IO.puts("   Jobs queued: #{stats.jobs_queued}")

    if dry_run do
      IO.puts("\n💡 This was a dry run. Run without --dry-run to actually queue jobs.")
    else
      IO.puts(
        "\n💡 Jobs are now queued. Monitor progress with: mix migrate_imagekit --status"
      )
    end

    IO.puts("")
  end

  defp show_help do
    IO.puts(@moduledoc)
  end

  defp build_progress_bar(percentage) do
    filled = round(percentage / 5)
    empty = 20 - filled
    String.duplicate("█", filled) <> String.duplicate("░", empty)
  end
end
