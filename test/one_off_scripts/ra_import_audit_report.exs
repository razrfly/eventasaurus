# RA Import Audit Report
# Run: mix run test/one_off_scripts/ra_import_audit_report.exs

alias EventasaurusApp.Repo
import Ecto.Query

IO.puts("\n" <> IO.ANSI.cyan() <> "🔍 Resident Advisor Import Audit Report" <> IO.ANSI.reset())
IO.puts(String.duplicate("=", 80))

# Query for comprehensive stats
stats_query = """
SELECT
  'Total RA Events' as metric,
  COUNT(*) as count
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Resident Advisor'
UNION ALL
SELECT
  'RA Events with performers',
  COUNT(DISTINCT pe.id)
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
JOIN public_event_performers pep ON pep.event_id = pe.id
WHERE s.name = 'Resident Advisor'
UNION ALL
SELECT
  'RA Events without performers',
  COUNT(*)
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
LEFT JOIN public_event_performers pep ON pep.event_id = pe.id
WHERE s.name = 'Resident Advisor' AND pep.event_id IS NULL
UNION ALL
SELECT
  'Total event-performer links',
  COUNT(*)
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
JOIN public_event_performers pep ON pep.event_id = pe.id
WHERE s.name = 'Resident Advisor'
UNION ALL
SELECT
  'Total unique RA performers',
  COUNT(DISTINCT p.id)
FROM performers p
WHERE p.metadata->>'source' = 'resident_advisor'
UNION ALL
SELECT
  'Performers with images',
  COUNT(*)
FROM performers p
WHERE p.metadata->>'source' = 'resident_advisor' AND p.image_url IS NOT NULL
UNION ALL
SELECT
  'Performers with RA URLs',
  COUNT(*)
FROM performers p
WHERE p.metadata->>'ra_artist_url' IS NOT NULL
UNION ALL
SELECT
  'Performers with country data',
  COUNT(*)
FROM performers p
WHERE p.metadata->>'country' IS NOT NULL
UNION ALL
SELECT
  'RA Containers',
  COUNT(*)
FROM public_event_containers
WHERE source_id = (SELECT id FROM sources WHERE name = 'Resident Advisor')
UNION ALL
SELECT
  'Container memberships',
  COUNT(*)
FROM public_event_container_memberships m
JOIN public_event_containers c ON c.id = m.container_id
WHERE c.source_id = (SELECT id FROM sources WHERE name = 'Resident Advisor');
"""

{:ok, result} = Repo.query(stats_query)

IO.puts("\n" <> IO.ANSI.yellow() <> "📊 Overall Statistics" <> IO.ANSI.reset())
Enum.each(result.rows, fn [metric, count] ->
  IO.puts("  #{metric}: #{IO.ANSI.green()}#{count}#{IO.ANSI.reset()}")
end)

# Multi-artist events
multi_artist_query = """
SELECT
  pe.id,
  pe.title,
  COUNT(pep.performer_id) as performer_count
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
JOIN public_event_performers pep ON pep.event_id = pe.id
WHERE s.name = 'Resident Advisor'
GROUP BY pe.id, pe.title
HAVING COUNT(pep.performer_id) > 1
ORDER BY COUNT(pep.performer_id) DESC
LIMIT 5;
"""

{:ok, multi_result} = Repo.query(multi_artist_query)

IO.puts("\n" <> IO.ANSI.yellow() <> "🎭 Top Multi-Artist Events" <> IO.ANSI.reset())
Enum.each(multi_result.rows, fn [id, title, count] ->
  title_display = if String.length(title) > 70, do: String.slice(title, 0, 67) <> "...", else: title
  IO.puts("  [#{id}] #{count} performers: #{title_display}")
end)

# Sample performer data
sample_query = """
SELECT
  p.id,
  p.name,
  CASE
    WHEN p.image_url IS NOT NULL THEN '✓'
    ELSE '✗'
  END as has_image,
  p.metadata->>'country' as country
FROM performers p
WHERE p.metadata->>'source' = 'resident_advisor'
ORDER BY p.id
LIMIT 5;
"""

{:ok, sample_result} = Repo.query(sample_query)

IO.puts("\n" <> IO.ANSI.yellow() <> "👤 Sample Performers" <> IO.ANSI.reset())
Enum.each(sample_result.rows, fn [id, name, has_image, country] ->
  IO.puts("  [#{id}] #{name} | Image: #{has_image} | Country: #{country || "none"}")
end)

# Container analysis
container_query = """
SELECT
  c.id,
  c.title,
  c.container_type,
  COUNT(DISTINCT m.event_id) as child_events,
  COUNT(DISTINCT pep.performer_id) as aggregated_performers
FROM public_event_containers c
LEFT JOIN public_event_container_memberships m ON m.container_id = c.id
LEFT JOIN public_event_performers pep ON pep.event_id = m.event_id
WHERE c.source_id = (SELECT id FROM sources WHERE name = 'Resident Advisor')
GROUP BY c.id, c.title, c.container_type;
"""

{:ok, container_result} = Repo.query(container_query)

IO.puts("\n" <> IO.ANSI.yellow() <> "📦 Container Analysis" <> IO.ANSI.reset())
Enum.each(container_result.rows, fn [id, title, type, children, performers] ->
  IO.puts("  [#{id}] #{title}")
  IO.puts("       Type: #{type} | Child events: #{children} | Performers (aggregated): #{performers}")
end)

# Phase I validation
IO.puts("\n" <> IO.ANSI.yellow() <> "✅ Phase I Validation (Multi-Artist Support)" <> IO.ANSI.reset())

{:ok, %{rows: [[total_events]]}} = Repo.query("SELECT COUNT(*) FROM public_events pe JOIN public_event_sources pes ON pes.event_id = pe.id JOIN sources s ON s.id = pes.source_id WHERE s.name = 'Resident Advisor'")
{:ok, %{rows: [[events_with_performers]]}} = Repo.query("SELECT COUNT(DISTINCT pe.id) FROM public_events pe JOIN public_event_sources pes ON pes.event_id = pe.id JOIN sources s ON s.id = pes.source_id JOIN public_event_performers pep ON pep.event_id = pe.id WHERE s.name = 'Resident Advisor'")
{:ok, %{rows: [[total_links]]}} = Repo.query("SELECT COUNT(*) FROM public_events pe JOIN public_event_sources pes ON pes.event_id = pe.id JOIN sources s ON s.id = pes.source_id JOIN public_event_performers pep ON pep.event_id = pe.id WHERE s.name = 'Resident Advisor'")

avg_performers = if events_with_performers > 0, do: Float.round(total_links / events_with_performers, 2), else: 0

IO.puts("  Total events: #{total_events}")
IO.puts("  Events with performers: #{events_with_performers} (#{Float.round(events_with_performers/total_events*100, 1)}%)")
IO.puts("  Average performers per event: #{avg_performers}")
IO.puts("  #{if avg_performers > 1, do: IO.ANSI.green() <> "✓", else: IO.ANSI.yellow() <> "⚠"} Multi-artist support working#{IO.ANSI.reset()}")

# Phase II validation
IO.puts("\n" <> IO.ANSI.yellow() <> "✅ Phase II Validation (Data Enrichment)" <> IO.ANSI.reset())

{:ok, %{rows: [[total_performers]]}} = Repo.query("SELECT COUNT(*) FROM performers WHERE metadata->>'source' = 'resident_advisor'")
{:ok, %{rows: [[with_images]]}} = Repo.query("SELECT COUNT(*) FROM performers WHERE metadata->>'source' = 'resident_advisor' AND image_url IS NOT NULL")
{:ok, %{rows: [[with_urls]]}} = Repo.query("SELECT COUNT(*) FROM performers WHERE metadata->>'ra_artist_url' IS NOT NULL")
{:ok, %{rows: [[with_country]]}} = Repo.query("SELECT COUNT(*) FROM performers WHERE metadata->>'country' IS NOT NULL")

image_pct = if total_performers > 0, do: Float.round(with_images/total_performers*100, 1), else: 0
url_pct = if total_performers > 0, do: Float.round(with_urls/total_performers*100, 1), else: 0
country_pct = if total_performers > 0, do: Float.round(with_country/total_performers*100, 1), else: 0

IO.puts("  Total RA performers: #{total_performers}")
IO.puts("  With images: #{with_images} (#{image_pct}%)")
IO.puts("  With RA URLs: #{with_urls} (#{url_pct}%)")
IO.puts("  With country: #{with_country} (#{country_pct}%)")
IO.puts("  #{if image_pct > 90, do: IO.ANSI.green() <> "✓", else: IO.ANSI.yellow() <> "⚠"} Enrichment working#{IO.ANSI.reset()}")

# Container validation
IO.puts("\n" <> IO.ANSI.yellow() <> "✅ Container Validation" <> IO.ANSI.reset())

{:ok, %{rows: [[container_direct]]}} = Repo.query("SELECT COUNT(*) FROM public_event_performers WHERE event_id IN (SELECT source_event_id FROM public_event_containers WHERE source_id = (SELECT id FROM sources WHERE name = 'Resident Advisor'))")
{:ok, %{rows: [[container_aggregated]]}} = Repo.query("SELECT COUNT(DISTINCT pep.performer_id) FROM public_event_container_memberships m JOIN public_event_containers c ON c.id = m.container_id JOIN public_event_performers pep ON pep.event_id = m.event_id WHERE c.source_id = (SELECT id FROM sources WHERE name = 'Resident Advisor')")

IO.puts("  Container direct performers: #{container_direct}")
IO.puts("  Container aggregated performers: #{container_aggregated}")
IO.puts("  #{if container_direct == 0 && container_aggregated > 0, do: IO.ANSI.green() <> "✓", else: IO.ANSI.yellow() <> "⚠"} Container architecture correct#{IO.ANSI.reset()}")

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts(IO.ANSI.green() <> "✅ Audit Complete!\n" <> IO.ANSI.reset())
