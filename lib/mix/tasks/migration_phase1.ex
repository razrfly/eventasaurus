defmodule Mix.Tasks.Migration.Phase1 do
  @moduledoc """
  TEMPORARY - Phase 1 Development Testing for Trivia Advisor image migration
  Delete after Phase 2 completion

  This phase migrates venue images WITHOUT uploading to ImageKit.
  Images are stored as external Tigris S3 URLs with upload_status: "external"

  Usage:
    mix migration.phase1              # Migrate all matched venues
    mix migration.phase1 --limit=10   # Migrate first 10 venues (testing)
    mix migration.phase1 --dry-run    # Preview changes without committing
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue

  @shortdoc "Run Phase 1 development testing (Tigris URLs only, no ImageKit)"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [limit: :integer, dry_run: :boolean],
        aliases: [l: :limit, d: :dry_run]
      )

    limit = Keyword.get(opts, :limit)
    dry_run = Keyword.get(opts, :dry_run, false)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TRIVIA ADVISOR → EVENTASAURUS IMAGE MIGRATION")
    IO.puts("Phase 1: Development Testing (Tigris URLs)")
    if dry_run, do: IO.puts("DRY RUN MODE - No changes will be committed")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Get trivia_advisor database connection
    ta_db_url = System.get_env("TRVIA_ADVISOR_DATABASE_URL")

    unless ta_db_url do
      IO.puts("❌ ERROR: TRVIA_ADVISOR_DATABASE_URL not set in environment")
      System.halt(1)
    end

    ta_db_config = parse_database_url(ta_db_url)
    {:ok, ta_conn} = Postgrex.start_link(ta_db_config)

    # Load matching results
    IO.puts("📊 Step 1: Loading Matching Results")
    IO.puts(String.duplicate("-", 80))

    matches = load_matches("temp/migration_recon/matching_report.csv", limit)
    IO.puts("✓ Loaded #{length(matches)} matched venues\n")

    # Migrate images
    IO.puts("📊 Step 2: Migrating Images")
    IO.puts(String.duplicate("-", 80))

    results =
      Enum.map(matches, fn match ->
        migrate_venue_images(ta_conn, match, dry_run)
      end)

    # Calculate statistics
    successful = Enum.count(results, fn r -> r.success end)
    failed = Enum.count(results, fn r -> !r.success end)
    total_images = Enum.reduce(results, 0, fn r, acc -> acc + r.images_migrated end)

    IO.puts("\n✓ Migration complete!")
    IO.puts("\nStatistics:")
    IO.puts("  Venues processed: #{length(results)}")
    IO.puts("  Successful: #{successful}")
    IO.puts("  Failed: #{failed}")
    IO.puts("  Total images migrated: #{total_images}\n")

    # Generate rollback file
    if !dry_run && successful > 0 do
      IO.puts("📊 Step 3: Generating Rollback Data")
      IO.puts(String.duplicate("-", 80))

      rollback_path = "temp/migration_recon/phase1_rollback.json"
      write_rollback_data(results, rollback_path)
      IO.puts("✓ Rollback data written to: #{rollback_path}\n")
    end

    # Generate migration report
    IO.puts("📊 Step 4: Generating Migration Report")
    IO.puts(String.duplicate("-", 80))

    report_path = "temp/migration_recon/phase1_report.txt"
    write_migration_report(results, report_path, dry_run)
    IO.puts("✓ Migration report written to: #{report_path}\n")

    IO.puts(String.duplicate("=", 80))
    IO.puts("✓ Phase 1 Complete!")
    IO.puts(String.duplicate("=", 80))

    if dry_run do
      IO.puts("\nThis was a DRY RUN - no changes were made to the database")
    else
      IO.puts("\nNext Steps:")
      IO.puts("  1. Verify images in eventasaurus UI")
      IO.puts("  2. Test image loading and display")
      IO.puts("  3. Proceed to Phase 2 (ImageKit migration)")
      IO.puts("\nTo rollback: Create rollback task using phase1_rollback.json")
    end

    IO.puts("\n")

    GenServer.stop(ta_conn)
  end

  # Helper functions

  defp parse_database_url(url) do
    uri = URI.parse(url)
    [username, password] = String.split(uri.userinfo || ":", ":")

    [
      hostname: uri.host,
      port: uri.port || 5432,
      database: String.trim_leading(uri.path || "", "/"),
      username: username,
      password: password
    ]
  end

  defp load_matches(csv_path, limit) do
    File.stream!(csv_path)
    # Skip header
    |> Stream.drop(1)
    |> Stream.map(&parse_csv_line/1)
    |> Stream.filter(fn match -> match.confidence > 0 end)
    |> then(fn stream ->
      if limit, do: Enum.take(stream, limit), else: Enum.to_list(stream)
    end)
  end

  defp parse_csv_line(line) do
    # Proper CSV parsing with quoted field support
    fields = parse_csv_fields(String.trim(line))

    [
      ta_id,
      ta_slug,
      ta_name,
      ea_id,
      ea_slug,
      ea_name,
      match_type,
      confidence,
      distance_m,
      name_distance,
      images_count
    ] = fields

    %{
      ta_id: String.to_integer(ta_id),
      ta_slug: ta_slug,
      ta_name: ta_name,
      ea_id: if(ea_id == "", do: nil, else: String.to_integer(ea_id)),
      ea_slug: ea_slug,
      ea_name: ea_name,
      match_type: match_type,
      confidence: String.to_float(confidence),
      distance_m: if(distance_m == "", do: nil, else: String.to_float(distance_m)),
      name_distance: if(name_distance == "", do: nil, else: String.to_integer(name_distance)),
      images_count: String.to_integer(images_count)
    }
  end

  defp parse_csv_fields(line) do
    # Simple CSV parser that handles quoted fields
    line
    |> String.split(~r/,(?=(?:[^"]*"[^"]*")*[^"]*$)/)
    |> Enum.map(fn field ->
      field
      |> String.trim()
      |> String.trim("\"")
    end)
  end

  defp migrate_venue_images(ta_conn, match, dry_run) do
    IO.puts("\nVenue: #{match.ta_name} → #{match.ea_name}")
    IO.puts("  Match type: #{match.match_type} (#{Float.round(match.confidence * 100, 1)}%)")

    # Fetch trivia_advisor images
    {:ok, result} =
      Postgrex.query(
        ta_conn,
        """
          SELECT google_place_images
          FROM venues
          WHERE id = $1
        """,
        [match.ta_id]
      )

    ta_images = result.rows |> List.first() |> List.first()

    if ta_images && length(ta_images) > 0 do
      IO.puts("  Found #{length(ta_images)} images from trivia_advisor")

      # Get current eventasaurus venue
      ea_venue = Repo.get!(Venue, match.ea_id)
      original_images = ea_venue.venue_images || []

      IO.puts("  Current eventasaurus images: #{length(original_images)}")

      # Transform images to eventasaurus format
      new_images = Enum.map(ta_images, &transform_image/1)

      # Merge with existing images (avoid duplicates)
      merged_images = merge_images(original_images, new_images)

      IO.puts("  After merge: #{length(merged_images)} total images")

      if !dry_run do
        # Update venue
        case Repo.update(Ecto.Changeset.change(ea_venue, venue_images: merged_images)) do
          {:ok, _updated_venue} ->
            IO.puts("  ✓ Updated successfully")

            %{
              success: true,
              ea_id: match.ea_id,
              ea_slug: match.ea_slug,
              images_migrated: length(new_images),
              original_images: original_images,
              error: nil
            }

          {:error, changeset} ->
            IO.puts("  ✗ Update failed: #{inspect(changeset.errors)}")

            %{
              success: false,
              ea_id: match.ea_id,
              ea_slug: match.ea_slug,
              images_migrated: 0,
              original_images: original_images,
              error: inspect(changeset.errors)
            }
        end
      else
        IO.puts("  [DRY RUN] Would update with #{length(new_images)} new images")

        %{
          success: true,
          ea_id: match.ea_id,
          ea_slug: match.ea_slug,
          images_migrated: length(new_images),
          original_images: original_images,
          error: nil
        }
      end
    else
      IO.puts("  ⚠️  No images found in trivia_advisor")

      %{
        success: false,
        ea_id: match.ea_id,
        ea_slug: match.ea_slug,
        images_migrated: 0,
        original_images: [],
        error: "No images in trivia_advisor"
      }
    end
  end

  defp transform_image(ta_image) do
    # Transform trivia_advisor format to eventasaurus format
    # trivia_advisor: {"local_path": "/uploads/...", "width": 800, "height": 600}
    # eventasaurus: {"url": "https://cdn...", "upload_status": "external", ...}

    local_path = ta_image["local_path"]
    tigris_url = "https://cdn.quizadvisor.com#{local_path}"

    %{
      "url" => tigris_url,
      # Mark as external (not ImageKit)
      "upload_status" => "external",
      "width" => ta_image["width"],
      "height" => ta_image["height"],
      "source" => "trivia_advisor_migration",
      "migrated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp merge_images(original_images, new_images) do
    # Merge new images with existing, avoiding duplicates by URL
    existing_urls = MapSet.new(original_images, fn img -> img["url"] end)

    unique_new_images =
      Enum.reject(new_images, fn img ->
        MapSet.member?(existing_urls, img["url"])
      end)

    original_images ++ unique_new_images
  end

  defp write_rollback_data(results, path) do
    rollback_data =
      Enum.filter(results, fn r -> r.success end)
      |> Enum.map(fn r ->
        %{
          ea_id: r.ea_id,
          ea_slug: r.ea_slug,
          original_images: r.original_images
        }
      end)

    json = Jason.encode!(rollback_data, pretty: true)
    File.write!(path, json)
  end

  defp write_migration_report(results, path, dry_run) do
    successful = Enum.count(results, fn r -> r.success end)
    failed = Enum.count(results, fn r -> !r.success end)
    total_images = Enum.reduce(results, 0, fn r, acc -> acc + r.images_migrated end)

    content = """
    TRIVIA ADVISOR → EVENTASAURUS IMAGE MIGRATION
    Phase 1: Development Testing Report
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}
    #{if dry_run, do: "MODE: DRY RUN (no changes committed)\n", else: ""}
    ================================================================================
    MIGRATION SUMMARY
    ================================================================================

    Total venues processed: #{length(results)}
    Successful migrations: #{successful}
    Failed migrations: #{failed}
    Total images migrated: #{total_images}
    Average images per venue: #{if successful > 0, do: Float.round(total_images / successful, 1), else: 0}

    ================================================================================
    MIGRATION DETAILS
    ================================================================================

    #{Enum.map_join(results, "\n", fn r ->
      status = if r.success, do: "✓", else: "✗"
      "#{status} ID #{r.ea_id} (#{r.ea_slug}): #{r.images_migrated} images" <> if r.error, do: " - ERROR: #{r.error}", else: ""
    end)}

    ================================================================================
    TECHNICAL DETAILS
    ================================================================================

    Image Format:
    - URL: Tigris S3 direct URLs (https://cdn.quizadvisor.com/...)
    - Upload Status: "external" (not uploaded to ImageKit)
    - Source: "trivia_advisor_migration"
    - Metadata: width, height, migrated_at timestamp

    Merge Strategy:
    - Existing images preserved
    - Duplicates filtered by URL
    - New images appended to venue_images array

    ================================================================================
    NEXT STEPS
    ================================================================================

    #{if dry_run do
      "This was a DRY RUN. To execute the migration:\n  mix migration.phase1"
    else
      "1. Verify images display correctly in eventasaurus UI\n" <> "2. Test image loading performance\n" <> "3. Check image metadata accuracy\n" <> "4. Proceed to Phase 2 (ImageKit migration) when ready\n\n" <> "Rollback available: temp/migration_recon/phase1_rollback.json"
    end}

    ================================================================================
    """

    File.write!(path, content)
  end
end
