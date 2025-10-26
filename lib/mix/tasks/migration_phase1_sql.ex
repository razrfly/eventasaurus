defmodule Mix.Tasks.Migration.Phase1Sql do
  @moduledoc """
  TEMPORARY - Phase 1 Development Testing for Trivia Advisor image migration (RAW SQL VERSION)
  Delete after Phase 2 completion

  This phase migrates venue images WITHOUT uploading to ImageKit.
  Images are stored as external Tigris S3 URLs with upload_status: "external"

  Uses RAW SQL via Postgrex to bypass Ecto type conversion issues.

  Usage:
    mix migration.phase1_sql              # Migrate all matched venues
    mix migration.phase1_sql --limit=10   # Migrate first 10 venues (testing)
    mix migration.phase1_sql --dry-run    # Preview changes without committing
  """

  use Mix.Task
  require Logger

  @shortdoc "Run Phase 1 with raw SQL (Tigris URLs only, no ImageKit)"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      switches: [limit: :integer, dry_run: :boolean],
      aliases: [l: :limit, d: :dry_run]
    )

    limit = Keyword.get(opts, :limit)
    dry_run = Keyword.get(opts, :dry_run, false)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TRIVIA ADVISOR → EVENTASAURUS IMAGE MIGRATION")
    IO.puts("Phase 1: Development Testing (RAW SQL - Tigris URLs)")
    if dry_run, do: IO.puts("DRY RUN MODE - No changes will be committed")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Get trivia_advisor database connection
    ta_db_url = System.get_env("TRVIA_ADVISOR_DATABASE_URL")

    unless ta_db_url do
      IO.puts("❌ ERROR: TRVIA_ADVISOR_DATABASE_URL not set in environment")
      System.halt(1)
    end

    # Get eventasaurus database connection
    ea_db_config = get_ea_database_config()

    ta_db_config = parse_database_url(ta_db_url)
    {:ok, ta_conn} = Postgrex.start_link(ta_db_config)
    {:ok, ea_conn} = Postgrex.start_link(ea_db_config)

    # Load matching results
    IO.puts("📊 Step 1: Loading Matching Results")
    IO.puts(String.duplicate("-", 80))

    matches = load_matches("temp/migration_recon/matching_report.csv", limit)
    IO.puts("✓ Loaded #{length(matches)} matched venues\n")

    # Migrate images
    IO.puts("📊 Step 2: Migrating Images (Raw SQL)")
    IO.puts(String.duplicate("-", 80))

    results = Enum.map(matches, fn match ->
      migrate_venue_images(ta_conn, ea_conn, match, dry_run)
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

      rollback_path = "temp/migration_recon/phase1_rollback_sql.json"
      write_rollback_data(results, rollback_path)
      IO.puts("✓ Rollback data written to: #{rollback_path}\n")
    end

    # Generate migration report
    IO.puts("📊 Step 4: Generating Migration Report")
    IO.puts(String.duplicate("-", 80))

    report_path = "temp/migration_recon/phase1_report_sql.txt"
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
      IO.puts("\nTo rollback: Create rollback task using phase1_rollback_sql.json")
    end

    IO.puts("\n")

    GenServer.stop(ta_conn)
    GenServer.stop(ea_conn)
  end

  # Helper functions

  defp get_ea_database_config do
    # Get config from runtime.exs / config
    [
      hostname: "127.0.0.1",
      port: 54322,
      database: "postgres",
      username: "postgres",
      password: "postgres"
    ]
  end

  defp parse_database_url(url) do
    uri = URI.parse(url)

    [username, password] =
      case String.split(uri.userinfo || ":", ":") do
        [u, p] -> [u, p]
        [u] -> [u, ""]
        _ -> ["", ""]
      end

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
    |> Stream.drop(1)  # Skip header
    |> Stream.map(&parse_csv_line/1)
    |> Stream.filter(fn match -> match.confidence > 0 end)
    |> then(fn stream ->
      if limit, do: Enum.take(stream, limit), else: Enum.to_list(stream)
    end)
  end

  defp parse_csv_line(line) do
    # Proper CSV parsing with quoted field support
    fields = parse_csv_fields(String.trim(line))

    [ta_id, ta_slug, ta_name, ea_id, ea_slug, ea_name, match_type, confidence, distance_m, name_distance, images_count] = fields

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

  defp migrate_venue_images(ta_conn, ea_conn, match, dry_run) do
    IO.puts("\nVenue: #{match.ta_name} → #{match.ea_name}")
    IO.puts("  Match type: #{match.match_type} (#{Float.round(match.confidence * 100, 1)}%)")

    # Fetch trivia_advisor images using Postgrex
    {:ok, ta_result} = Postgrex.query(ta_conn, """
      SELECT google_place_images
      FROM venues
      WHERE id = $1
    """, [match.ta_id])

    ta_images =
      case ta_result.rows do
        [[images]] when is_list(images) -> images
        [[nil]] -> []
        [] -> []
        _ -> []
      end

    if ta_images != [] && length(ta_images) > 0 do
      IO.puts("  Found #{length(ta_images)} images from trivia_advisor")

      # Fetch current eventasaurus venue images using RAW SQL
      {:ok, ea_result} = Postgrex.query(ea_conn, """
        SELECT venue_images
        FROM venues
        WHERE id = $1
      """, [match.ea_id])

      original_images =
        case ea_result.rows do
          [[images]] when is_list(images) -> images
          [[nil]] -> []
          [] -> []
          _ -> []
        end

      IO.puts("  Current eventasaurus images: #{length(original_images)}")

      # Transform images to eventasaurus format
      new_images = Enum.map(ta_images, &transform_image/1)

      # Merge with existing images (avoid duplicates)
      merged_images = merge_images(original_images, new_images)
      added_count = max(length(merged_images) - length(original_images), 0)

      IO.puts("  After merge: #{length(merged_images)} total images (+#{added_count} new)")

      if !dry_run do
        # Update venue using RAW SQL with JSONB
        # Postgrex automatically encodes Elixir maps/lists to jsonb
        # DO NOT use Jason.encode! - that creates a string scalar

        case Postgrex.query(ea_conn, """
          UPDATE venues
          SET venue_images = $1,
              updated_at = NOW()
          WHERE id = $2
        """, [merged_images, match.ea_id]) do
          {:ok, %{num_rows: 1}} ->
            IO.puts("  ✓ Updated successfully (SQL)")

            # Verify the update persisted
            {:ok, verify_result} = Postgrex.query(ea_conn, """
              SELECT jsonb_array_length(venue_images) as count
              FROM venues
              WHERE id = $1
            """, [match.ea_id])

            case verify_result.rows do
              [[count]] when count == length(merged_images) ->
                IO.puts("  ✓ Verified: #{count} images in database")
              [[count]] ->
                IO.puts("  ⚠️  Warning: Expected #{length(merged_images)} images, found #{count}")
              _ ->
                IO.puts("  ⚠️  Warning: Could not verify image count")
            end

            %{
              success: true,
              ea_id: match.ea_id,
              ea_slug: match.ea_slug,
              images_migrated: added_count,
              original_images: original_images,
              error: nil
            }

          {:ok, %{num_rows: 0}} ->
            IO.puts("  ✗ Update failed: No rows affected")

            %{
              success: false,
              ea_id: match.ea_id,
              ea_slug: match.ea_slug,
              images_migrated: 0,
              original_images: original_images,
              error: "No rows affected"
            }

          {:error, error} ->
            IO.puts("  ✗ Update failed: #{inspect(error)}")

            %{
              success: false,
              ea_id: match.ea_id,
              ea_slug: match.ea_slug,
              images_migrated: 0,
              original_images: original_images,
              error: inspect(error)
            }
        end
      else
        IO.puts("  [DRY RUN] Would update with #{added_count} new images")

        %{
          success: true,
          ea_id: match.ea_id,
          ea_slug: match.ea_slug,
          images_migrated: added_count,
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
      "upload_status" => "external",  # Mark as external (not ImageKit)
      "width" => ta_image["width"],
      "height" => ta_image["height"],
      "source" => "trivia_advisor_migration",
      "migrated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp merge_images(original_images, new_images) do
    # Merge new images with existing, avoiding duplicates by URL
    existing_urls =
      original_images
      |> Enum.map(& &1["url"])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    unique_new_images = Enum.reject(new_images, fn img ->
      MapSet.member?(existing_urls, img["url"])
    end)

    original_images ++ unique_new_images
  end

  defp write_rollback_data(results, path) do
    rollback_data = Enum.filter(results, fn r -> r.success end)
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
    Phase 1: Development Testing Report (RAW SQL)
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
      "#{status} ID #{r.ea_id} (#{r.ea_slug}): #{r.images_migrated} images" <>
      if r.error, do: " - ERROR: #{r.error}", else: ""
    end)}

    ================================================================================
    TECHNICAL DETAILS
    ================================================================================

    Migration Method: RAW SQL via Postgrex (bypasses Ecto)

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
      "This was a DRY RUN. To execute the migration:\n  mix migration.phase1_sql"
    else
      "1. Verify images display correctly in eventasaurus UI\n" <>
      "2. Test image loading performance\n" <>
      "3. Check image metadata accuracy\n" <>
      "4. Proceed to Phase 2 (ImageKit migration) when ready\n\n" <>
      "Rollback available: temp/migration_recon/phase1_rollback_sql.json"
    end}

    ================================================================================
    """

    File.write!(path, content)
  end
end
