defmodule Mix.Tasks.Migration.Recon do
  @moduledoc """
  TEMPORARY - Phase 0 Reconnaissance for Trivia Advisor image migration
  Delete after Phase 2 completion

  Usage:
    mix migration.recon
  """

  use Mix.Task
  require Logger

  @shortdoc "Run Phase 0 reconnaissance for image migration"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TRIVIA ADVISOR → EVENTASAURUS IMAGE MIGRATION")
    IO.puts("Phase 0: Reconnaissance")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Get database URLs
    ta_db_url = System.get_env("TRVIA_ADVISOR_DATABASE_URL")

    unless ta_db_url do
      IO.puts("❌ ERROR: TRVIA_ADVISOR_DATABASE_URL not set in environment")
      IO.puts("   Please add it to your .env file")
      System.halt(1)
    end

    IO.puts("📊 Step 1: Database Connections")
    IO.puts(String.duplicate("-", 80))

    # Parse Trivia Advisor database URL
    ta_db_config = parse_database_url(ta_db_url)

    IO.puts(
      "✓ Trivia Advisor DB: #{ta_db_config[:hostname]}:#{ta_db_config[:port]}/#{ta_db_config[:database]}"
    )

    IO.puts("✓ Eventasaurus DB: Using existing Repo connection")

    # Connect to Trivia Advisor database
    {:ok, ta_conn} = Postgrex.start_link(ta_db_config)
    IO.puts("✓ Database connections established\n")

    # Query Trivia Advisor
    IO.puts("📊 Step 2: Trivia Advisor Analysis")
    IO.puts(String.duplicate("-", 80))

    ta_stats = query_trivia_advisor_stats(ta_conn)
    IO.puts("Venues with images: #{ta_stats.venues_with_images}")
    IO.puts("Total images: #{ta_stats.total_images}")
    IO.puts("Avg images per venue: #{Float.round(ta_stats.avg_images_per_venue, 1)}")
    IO.puts("Venues with slugs: #{ta_stats.venues_with_slug} (#{ta_stats.slug_coverage_pct}%)")

    IO.puts(
      "Venues with place_id: #{ta_stats.venues_with_place_id} (#{ta_stats.place_id_coverage_pct}%)\n"
    )

    # Query Eventasaurus
    IO.puts("📊 Step 3: Eventasaurus Analysis")
    IO.puts(String.duplicate("-", 80))

    ea_stats = query_eventasaurus_stats()
    IO.puts("Total venues: #{ea_stats.total_venues}")
    IO.puts("Venues with slugs: #{ea_stats.venues_with_slug} (#{ea_stats.slug_coverage_pct}%)")

    IO.puts(
      "Venues with Google Place ID: #{ea_stats.venues_with_google_id} (#{ea_stats.google_id_coverage_pct}%)\n"
    )

    # Load venues for matching
    IO.puts("📊 Step 4: Venue Matching Analysis")
    IO.puts(String.duplicate("-", 80))
    IO.puts("Loading venues for matching...")

    ta_venues = load_ta_venues_with_images(ta_conn)
    ea_venues = load_ea_venues()

    IO.puts("✓ Loaded #{length(ta_venues)} trivia_advisor venues")
    IO.puts("✓ Loaded #{length(ea_venues)} eventasaurus venues\n")

    IO.puts("Finding matches...")

    matches =
      Enum.map(ta_venues, fn ta_venue ->
        case find_match(ta_venue, ea_venues) do
          {ea_venue, match_type, confidence, distance, name_distance} ->
            %{
              ta_id: ta_venue.id,
              ta_slug: ta_venue.slug,
              ta_name: ta_venue.name,
              ea_id: ea_venue.id,
              ea_slug: ea_venue.slug,
              ea_name: ea_venue.name,
              match_type: match_type,
              confidence: confidence,
              distance_m: Float.round(distance, 1),
              name_distance: name_distance,
              images_count: length(ta_venue.google_place_images)
            }

          nil ->
            %{
              ta_id: ta_venue.id,
              ta_slug: ta_venue.slug,
              ta_name: ta_venue.name,
              ea_id: nil,
              ea_slug: nil,
              ea_name: nil,
              match_type: "no_match",
              confidence: 0.0,
              distance_m: nil,
              name_distance: nil,
              images_count: length(ta_venue.google_place_images)
            }
        end
      end)

    # Calculate match statistics
    matched = Enum.filter(matches, fn m -> m.confidence > 0 end)
    unmatched = Enum.filter(matches, fn m -> m.confidence == 0 end)

    tier1 = Enum.filter(matched, fn m -> m.match_type == "slug_geo" end)
    tier2 = Enum.filter(matched, fn m -> m.match_type == "place_id" end)
    tier3 = Enum.filter(matched, fn m -> m.match_type in ["slug_only", "geo_name"] end)

    IO.puts("\n✓ Matching complete!")
    IO.puts("\nMatch Statistics:")

    IO.puts(
      "  Total matched: #{length(matched)} (#{Float.round(length(matched) / length(ta_venues) * 100, 1)}%)"
    )

    IO.puts("  - Tier 1 (slug + geo): #{length(tier1)}")
    IO.puts("  - Tier 2 (place_id): #{length(tier2)}")
    IO.puts("  - Tier 3 (fuzzy): #{length(tier3)}")

    IO.puts(
      "  Unmatched: #{length(unmatched)} (#{Float.round(length(unmatched) / length(ta_venues) * 100, 1)}%)\n"
    )

    # Calculate total images to migrate
    total_images_to_migrate = Enum.reduce(matched, 0, fn m, acc -> acc + m.images_count end)
    IO.puts("Total images to migrate: #{total_images_to_migrate}\n")

    # Sample URL testing
    IO.puts("📊 Step 5: Sample Image URL Testing")
    IO.puts(String.duplicate("-", 80))

    sample_venues = Enum.take(ta_venues, 5)

    Enum.each(sample_venues, fn venue ->
      IO.puts("\nVenue: #{venue.name} (#{venue.slug})")

      images = venue.google_place_images || []
      sample_image = List.first(images)

      if sample_image do
        local_path = sample_image["local_path"]
        url = construct_tigris_url(local_path)

        IO.puts("  Testing URL: #{String.slice(url, 0..60)}...")

        case test_url_accessibility(url) do
          :ok ->
            IO.puts("  ✓ Image accessible")

          {:error, reason} ->
            IO.puts("  ✗ Image not accessible: #{inspect(reason)}")
        end
      else
        IO.puts("  No images found")
      end
    end)

    # Write CSV report
    IO.puts("\n📊 Step 6: Generating Reports")
    IO.puts(String.duplicate("-", 80))

    File.mkdir_p!("temp/migration_recon")

    csv_path = "temp/migration_recon/matching_report.csv"
    write_csv_report(matches, csv_path)
    IO.puts("✓ Match report written to: #{csv_path}")

    # Write summary report
    summary_path = "temp/migration_recon/reconnaissance_summary.txt"
    write_summary_report(ta_stats, ea_stats, matches, summary_path)
    IO.puts("✓ Summary report written to: #{summary_path}")

    # Write sample venues
    sample_path = "temp/migration_recon/sample_venues.json"
    write_sample_venues(Enum.take(matches, 10), sample_path)
    IO.puts("✓ Sample venues written to: #{sample_path}")

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("✓ Reconnaissance Complete!")
    IO.puts(String.duplicate("=", 80))
    IO.puts("\nNext Steps:")
    IO.puts("  1. Review matching_report.csv for venue matches")
    IO.puts("  2. Review reconnaissance_summary.txt for overall statistics")
    IO.puts("  3. Proceed to Phase 1 (Development Testing)")
    IO.puts("\n")

    # Close connection
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

  defp query_trivia_advisor_stats(conn) do
    # Venues with images
    {:ok, result} =
      Postgrex.query(
        conn,
        """
          SELECT COUNT(*) as count
          FROM venues
          WHERE google_place_images IS NOT NULL
          AND jsonb_typeof(google_place_images) = 'array'
          AND jsonb_array_length(google_place_images) > 0
        """,
        []
      )

    venues_with_images = result.rows |> List.first() |> List.first()

    # Total images
    {:ok, result} =
      Postgrex.query(
        conn,
        """
          SELECT COALESCE(SUM(jsonb_array_length(google_place_images)), 0) as total
          FROM venues
          WHERE google_place_images IS NOT NULL
          AND jsonb_typeof(google_place_images) = 'array'
        """,
        []
      )

    total_images = result.rows |> List.first() |> List.first() || 0

    # Slug coverage
    {:ok, result} =
      Postgrex.query(
        conn,
        """
          SELECT
            COUNT(*) as total,
            COUNT(slug) as with_slug
          FROM venues
          WHERE google_place_images IS NOT NULL
          AND jsonb_typeof(google_place_images) = 'array'
          AND jsonb_array_length(google_place_images) > 0
        """,
        []
      )

    [total, with_slug] = result.rows |> List.first()
    slug_coverage_pct = if total > 0, do: Float.round(with_slug / total * 100, 1), else: 0.0

    # place_id coverage
    {:ok, result} =
      Postgrex.query(
        conn,
        """
          SELECT COUNT(place_id) as with_place_id
          FROM venues
          WHERE google_place_images IS NOT NULL
          AND jsonb_typeof(google_place_images) = 'array'
          AND jsonb_array_length(google_place_images) > 0
          AND place_id IS NOT NULL
        """,
        []
      )

    with_place_id = result.rows |> List.first() |> List.first()

    place_id_coverage_pct =
      if total > 0, do: Float.round(with_place_id / total * 100, 1), else: 0.0

    avg_images = if venues_with_images > 0, do: total_images / venues_with_images, else: 0.0

    %{
      venues_with_images: venues_with_images,
      total_images: total_images,
      avg_images_per_venue: avg_images,
      venues_with_slug: with_slug,
      slug_coverage_pct: slug_coverage_pct,
      venues_with_place_id: with_place_id,
      place_id_coverage_pct: place_id_coverage_pct
    }
  end

  defp query_eventasaurus_stats do
    import Ecto.Query
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Venues.Venue

    # Total venues
    total_venues = Repo.aggregate(Venue, :count)

    # Slug coverage
    with_slug = from(v in Venue, where: not is_nil(v.slug)) |> Repo.aggregate(:count)

    slug_coverage_pct =
      if total_venues > 0, do: Float.round(with_slug / total_venues * 100, 1), else: 0.0

    # Google Place ID coverage
    with_google_id =
      from(v in Venue, where: fragment("? \\? ?", v.provider_ids, "google_places"))
      |> Repo.aggregate(:count)

    google_id_coverage_pct =
      if total_venues > 0, do: Float.round(with_google_id / total_venues * 100, 1), else: 0.0

    %{
      total_venues: total_venues,
      venues_with_slug: with_slug,
      slug_coverage_pct: slug_coverage_pct,
      venues_with_google_id: with_google_id,
      google_id_coverage_pct: google_id_coverage_pct
    }
  end

  defp load_ta_venues_with_images(conn) do
    {:ok, result} =
      Postgrex.query(
        conn,
        """
          SELECT id, slug, name, place_id, latitude, longitude, google_place_images
          FROM venues
          WHERE google_place_images IS NOT NULL
          AND jsonb_typeof(google_place_images) = 'array'
          AND jsonb_array_length(google_place_images) > 0
          ORDER BY id
        """,
        []
      )

    Enum.map(result.rows, fn [id, slug, name, place_id, lat, lng, images] ->
      %{
        id: id,
        slug: slug,
        name: name,
        place_id: place_id,
        latitude: lat,
        longitude: lng,
        google_place_images: images
      }
    end)
  end

  defp load_ea_venues do
    import Ecto.Query
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Venues.Venue

    from(v in Venue,
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      select: %{
        id: v.id,
        slug: v.slug,
        name: v.name,
        latitude: v.latitude,
        longitude: v.longitude,
        provider_ids: v.provider_ids
      }
    )
    |> Repo.all()
  end

  defp find_match(ta_venue, ea_venues) do
    ta_slug = ta_venue.slug
    ta_lat = Decimal.to_float(ta_venue.latitude)
    ta_lng = Decimal.to_float(ta_venue.longitude)
    ta_name = normalize_name(ta_venue.name)
    ta_place_id = ta_venue.place_id

    # Optimized matching with early termination
    result =
      Enum.reduce_while(ea_venues, nil, fn ea_venue, best_match ->
        ea_slug = ea_venue.slug
        ea_place_id = Map.get(ea_venue.provider_ids || %{}, "google_places")

        cond do
          # Tier 1: Slug + Geo (proof positive) - CHECK FIRST
          ta_slug == ea_slug ->
            ea_lat = ea_venue.latitude
            ea_lng = ea_venue.longitude
            distance = haversine_distance(ta_lat, ta_lng, ea_lat, ea_lng)

            if distance < 50 do
              # Perfect match - stop searching
              {:halt, {ea_venue, "slug_geo", 1.00, distance, 0}}
            else
              # Slug match but too far - Tier 3a
              new_match = {ea_venue, "slug_only", 0.85, distance, 0}
              {:cont, better_match(best_match, new_match)}
            end

          # Tier 2: place_id match
          ta_place_id && ea_place_id && ta_place_id == ea_place_id ->
            ea_lat = ea_venue.latitude
            ea_lng = ea_venue.longitude
            distance = haversine_distance(ta_lat, ta_lng, ea_lat, ea_lng)
            new_match = {ea_venue, "place_id", 0.95, distance, 0}
            {:cont, better_match(best_match, new_match)}

          # Tier 3b: Geo + name similarity - only check if no better match yet
          best_match == nil || elem(best_match, 2) < 0.85 ->
            ea_lat = ea_venue.latitude
            ea_lng = ea_venue.longitude
            distance = haversine_distance(ta_lat, ta_lng, ea_lat, ea_lng)

            if distance < 50 do
              ea_name = normalize_name(ea_venue.name)
              name_distance = levenshtein_distance(ta_name, ea_name)

              if name_distance <= 3 do
                new_match = {ea_venue, "geo_name", 0.85, distance, name_distance}
                {:cont, better_match(best_match, new_match)}
              else
                {:cont, best_match}
              end
            else
              {:cont, best_match}
            end

          # Skip if we already have a good match
          true ->
            {:cont, best_match}
        end
      end)

    result
  end

  defp better_match(nil, new_match), do: new_match

  defp better_match(best, new_match) do
    {_, _, best_conf, best_dist, _} = best
    {_, _, new_conf, new_dist, _} = new_match

    if new_conf > best_conf || (new_conf == best_conf && new_dist < best_dist) do
      new_match
    else
      best
    end
  end

  defp haversine_distance(lat1, lon1, lat2, lon2) do
    # Convert to radians
    lat1_rad = lat1 * :math.pi() / 180
    lon1_rad = lon1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    lon2_rad = lon2 * :math.pi() / 180

    # Haversine formula
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    # Earth radius in meters
    6_371_000 * c
  end

  defp levenshtein_distance(s1, s2) do
    s1 = String.downcase(s1)
    s2 = String.downcase(s2)

    l1 = String.length(s1)
    l2 = String.length(s2)

    matrix =
      Enum.reduce(0..l1, %{}, fn i, acc ->
        Map.put(acc, {i, 0}, i)
      end)

    matrix =
      Enum.reduce(0..l2, matrix, fn j, acc ->
        Map.put(acc, {0, j}, j)
      end)

    matrix =
      Enum.reduce(1..l1, matrix, fn i, acc ->
        Enum.reduce(1..l2, acc, fn j, acc2 ->
          cost = if String.at(s1, i - 1) == String.at(s2, j - 1), do: 0, else: 1

          Map.put(
            acc2,
            {i, j},
            min(
              Map.get(acc2, {i - 1, j}) + 1,
              min(
                Map.get(acc2, {i, j - 1}) + 1,
                Map.get(acc2, {i - 1, j - 1}) + cost
              )
            )
          )
        end)
      end)

    Map.get(matrix, {l1, l2})
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.trim()
  end

  defp normalize_name(_), do: ""

  defp construct_tigris_url(local_path) do
    "https://cdn.quizadvisor.com#{local_path}"
  end

  defp test_url_accessibility(url) do
    case Req.get(url, receive_timeout: 5000) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_csv_report(matches, path) do
    csv_content =
      [
        "ta_id,ta_slug,ta_name,ea_id,ea_slug,ea_name,match_type,confidence,distance_m,name_distance,images_count"
        | Enum.map(matches, fn m ->
            [
              m.ta_id,
              escape_csv(m.ta_slug),
              escape_csv(m.ta_name),
              m.ea_id || "",
              escape_csv(m.ea_slug),
              escape_csv(m.ea_name),
              m.match_type,
              m.confidence,
              m.distance_m || "",
              m.name_distance || "",
              m.images_count
            ]
            |> Enum.join(",")
          end)
      ]
      |> Enum.join("\n")

    File.write!(path, csv_content)
  end

  defp escape_csv(nil), do: ""

  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end

  defp write_summary_report(ta_stats, ea_stats, matches, path) do
    matched = Enum.filter(matches, fn m -> m.confidence > 0 end)
    unmatched = Enum.filter(matches, fn m -> m.confidence == 0 end)

    tier1 = Enum.filter(matched, fn m -> m.match_type == "slug_geo" end)
    tier2 = Enum.filter(matched, fn m -> m.match_type == "place_id" end)
    tier3 = Enum.filter(matched, fn m -> m.match_type in ["slug_only", "geo_name"] end)

    total_images = Enum.reduce(matched, 0, fn m, acc -> acc + m.images_count end)

    content = """
    TRIVIA ADVISOR → EVENTASAURUS IMAGE MIGRATION
    Phase 0: Reconnaissance Summary
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}

    ================================================================================
    TRIVIA ADVISOR STATISTICS
    ================================================================================

    Venues with images: #{ta_stats.venues_with_images}
    Total images available: #{ta_stats.total_images}
    Average images per venue: #{Float.round(ta_stats.avg_images_per_venue, 1)}

    Venues with slugs: #{ta_stats.venues_with_slug} (#{ta_stats.slug_coverage_pct}%)
    Venues with place_id: #{ta_stats.venues_with_place_id} (#{ta_stats.place_id_coverage_pct}%)

    ================================================================================
    EVENTASAURUS STATISTICS
    ================================================================================

    Total venues: #{ea_stats.total_venues}
    Venues with slugs: #{ea_stats.venues_with_slug} (#{ea_stats.slug_coverage_pct}%)
    Venues with Google Place ID: #{ea_stats.venues_with_google_id} (#{ea_stats.google_id_coverage_pct}%)

    ================================================================================
    MATCHING ANALYSIS
    ================================================================================

    Total trivia_advisor venues analyzed: #{length(matches)}

    Matched venues: #{length(matched)} (#{Float.round(length(matched) / max(length(matches), 1) * 100, 1)}%)
      - Tier 1 (slug + geo): #{length(tier1)} (#{Float.round(length(tier1) / max(length(matched), 1) * 100, 1)}% of matched)
      - Tier 2 (place_id): #{length(tier2)} (#{Float.round(length(tier2) / max(length(matched), 1) * 100, 1)}% of matched)
      - Tier 3 (fuzzy): #{length(tier3)} (#{Float.round(length(tier3) / max(length(matched), 1) * 100, 1)}% of matched)

    Unmatched venues: #{length(unmatched)} (#{Float.round(length(unmatched) / max(length(matches), 1) * 100, 1)}%)

    ================================================================================
    MIGRATION ESTIMATE
    ================================================================================

    Total images to migrate: #{total_images}
    Estimated ImageKit storage: #{Float.round(total_images * 0.4 / 1024, 1)} GB (assuming 400KB avg)
    Estimated migration time: #{Float.round(total_images * 0.5 / 60, 1)} minutes (500ms per image)

    ================================================================================
    RECOMMENDATIONS
    ================================================================================

    Match rate: #{Float.round(length(matched) / max(length(matches), 1) * 100, 1)}%
    Status: #{if length(matches) > 0 and length(matched) / length(matches) >= 0.70, do: "✓ GOOD - Proceed to Phase 1", else: "⚠️ REVIEW REQUIRED"}

    All confidence tiers are acceptable for migration.

    Next steps:
    1. Review matching_report.csv for detailed match information
    2. Verify sample venues in sample_venues.json
    3. Proceed to Phase 1 (Development Testing)

    ================================================================================
    """

    File.write!(path, content)
  end

  defp write_sample_venues(matches, path) do
    json = Jason.encode!(matches, pretty: true)
    File.write!(path, json)
  end
end
