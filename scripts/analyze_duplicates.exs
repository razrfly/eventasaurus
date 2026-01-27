# Script to analyze duplicate detection thresholds
krakow = EventasaurusApp.Repo.get_by(EventasaurusDiscovery.Locations.City, slug: "krakow")
IO.puts("Kraków city_id: #{krakow.id}")

# Analyze pairs by distance band
query = """
WITH venue_pairs AS (
  SELECT
    ST_Distance(
      ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
      ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography
    ) as distance,
    similarity(v1.name, v2.name) as name_similarity
  FROM venues v1
  INNER JOIN venues v2 ON v1.id < v2.id
  WHERE v1.city_id = $1
    AND v2.city_id = $1
    AND v1.latitude IS NOT NULL
    AND v1.longitude IS NOT NULL
    AND v2.latitude IS NOT NULL
    AND v2.longitude IS NOT NULL
    AND NOT (v1.latitude = v2.latitude AND v1.longitude = v2.longitude)
    AND ST_DWithin(
      ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
      ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
      500
    )
)
SELECT
  CASE
    WHEN distance < 50 THEN '< 50m'
    WHEN distance < 100 THEN '50-100m'
    WHEN distance < 200 THEN '100-200m'
    ELSE '200-500m'
  END as distance_band,
  COUNT(*) as total_pairs,
  COUNT(*) FILTER (WHERE name_similarity >= 0.5) as high_sim,
  COUNT(*) FILTER (WHERE name_similarity >= 0.3 AND name_similarity < 0.5) as medium_sim,
  COUNT(*) FILTER (WHERE name_similarity < 0.3) as low_sim,
  ROUND((AVG(name_similarity) * 100)::numeric, 1) as avg_sim_pct
FROM venue_pairs
GROUP BY 1
ORDER BY 1
"""

{:ok, result} = EventasaurusApp.Repo.query(query, [krakow.id])

IO.puts("")
IO.puts("========================================")
IO.puts("PAIRS BY DISTANCE BAND (Kraków)")
IO.puts("========================================")
IO.puts("")
IO.puts("Distance Band | Total | High Sim (≥50%) | Med (30-50%) | Low (<30%) | Avg Sim")
IO.puts("--------------|-------|-----------------|--------------|------------|--------")

Enum.each(result.rows, fn [band, total, high, med, low, avg] ->
  IO.puts("#{String.pad_trailing(band, 13)} | #{String.pad_leading(to_string(total), 5)} | #{String.pad_leading(to_string(high), 15)} | #{String.pad_leading(to_string(med), 12)} | #{String.pad_leading(to_string(low), 10)} | #{avg || 0}%")
end)

# Also check what percentage currently meets thresholds
query2 = """
WITH venue_pairs AS (
  SELECT
    ST_Distance(
      ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
      ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography
    ) as distance,
    similarity(v1.name, v2.name) as name_similarity
  FROM venues v1
  INNER JOIN venues v2 ON v1.id < v2.id
  WHERE v1.city_id = $1
    AND v2.city_id = $1
    AND v1.latitude IS NOT NULL
    AND v1.longitude IS NOT NULL
    AND v2.latitude IS NOT NULL
    AND v2.longitude IS NOT NULL
    AND NOT (v1.latitude = v2.latitude AND v1.longitude = v2.longitude)
    AND ST_DWithin(
      ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
      ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
      500
    )
)
SELECT
  COUNT(*) as total_proximity_pairs,
  COUNT(*) FILTER (WHERE
    CASE
      WHEN distance < 50 THEN name_similarity >= 0.0
      WHEN distance < 100 THEN name_similarity >= 0.4
      WHEN distance < 200 THEN name_similarity >= 0.5
      ELSE name_similarity >= 0.4
    END
  ) as current_flagged,
  COUNT(*) FILTER (WHERE name_similarity >= 0.5) as if_50pct_threshold,
  COUNT(*) FILTER (WHERE name_similarity >= 0.4) as if_40pct_threshold,
  COUNT(*) FILTER (WHERE name_similarity >= 0.3) as if_30pct_threshold
FROM venue_pairs
"""

{:ok, result2} = EventasaurusApp.Repo.query(query2, [krakow.id])
[[total, flagged, t50, t40, t30]] = result2.rows

IO.puts("")
IO.puts("========================================")
IO.puts("THRESHOLD COMPARISON")
IO.puts("========================================")
IO.puts("Total proximity pairs (<500m): #{total}")
IO.puts("Currently flagged (distance-based): #{flagged} (#{Float.round(flagged / total * 100, 1)}%)")
IO.puts("")
IO.puts("If we required minimum similarity regardless of distance:")
IO.puts("  ≥50% similarity: #{t50} pairs (#{Float.round(t50 / total * 100, 1)}%)")
IO.puts("  ≥40% similarity: #{t40} pairs (#{Float.round(t40 / total * 100, 1)}%)")
IO.puts("  ≥30% similarity: #{t30} pairs (#{Float.round(t30 / total * 100, 1)}%)")
