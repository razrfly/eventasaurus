# Week.pl Quality Assessment Script
# Run with: mix run lib/eventasaurus_discovery/sources/week_pl/quality_assessment.exs

alias EventasaurusDiscovery.Sources.WeekPl.{
  Source,
  Config,
  DeploymentConfig,
  Transformer,
  Helpers.TimeConverter
}

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Sources.Source, as: SourceModel
alias EventasaurusDiscovery.Categories.CategoryMapper

IO.puts("\n" <> IO.ANSI.blue() <> "🔍 Week.pl Quality Assessment" <> IO.ANSI.reset())
IO.puts(String.duplicate("=", 60))

# Track assessment results
results = %{
  passed: [],
  failed: [],
  warnings: []
}

# Helper functions
defmodule AssessmentHelper do
  def check(name, passed, results) do
    if passed do
      IO.puts("  " <> IO.ANSI.green() <> "✅ #{name}" <> IO.ANSI.reset())
      %{results | passed: [name | results.passed]}
    else
      IO.puts("  " <> IO.ANSI.red() <> "❌ #{name}" <> IO.ANSI.reset())
      %{results | failed: [name | results.failed]}
    end
  end

  def warn(name, message, results) do
    IO.puts("  " <> IO.ANSI.yellow() <> "⚠️  #{name}: #{message}" <> IO.ANSI.reset())
    %{results | warnings: [name | results.warnings]}
  end

  def section(title) do
    IO.puts("\n" <> IO.ANSI.cyan() <> "#{title}" <> IO.ANSI.reset())
  end
end

# ============================================================================
# 1. Module Configuration Assessment
# ============================================================================
AssessmentHelper.section("1️⃣ Module Configuration")

results = AssessmentHelper.check("Source module loaded", Code.ensure_loaded?(Source), results)
results = AssessmentHelper.check("Config module loaded", Code.ensure_loaded?(Config), results)
results = AssessmentHelper.check("DeploymentConfig module loaded", Code.ensure_loaded?(DeploymentConfig), results)
results = AssessmentHelper.check("Transformer module loaded", Code.ensure_loaded?(Transformer), results)
results = AssessmentHelper.check("TimeConverter module loaded", Code.ensure_loaded?(TimeConverter), results)

# Check source metadata
results = AssessmentHelper.check("Source name is 'Restaurant Week'", Source.name() == "Restaurant Week", results)
results = AssessmentHelper.check("Source key is 'week_pl'", Source.key() == "week_pl", results)
results = AssessmentHelper.check("13 cities configured", length(Source.supported_cities()) == 13, results)
results = AssessmentHelper.check("3+ festivals configured", length(Source.active_festivals()) >= 3, results)

# ============================================================================
# 2. Deployment Configuration Assessment
# ============================================================================
AssessmentHelper.section("2️⃣ Deployment Configuration")

deployment_status = DeploymentConfig.status()
IO.puts("  📊 Current Phase: #{deployment_status.phase}")
IO.puts("  🌍 Active Cities: #{deployment_status.active_cities} (#{deployment_status.city_names})")

phase = DeploymentConfig.deployment_phase()
results = AssessmentHelper.check(
  "Deployment phase valid",
  phase in [:pilot, :expansion, :full, :disabled],
  results
)

if phase == :disabled do
  results = AssessmentHelper.warn(
    "Source disabled",
    "Set WEEK_PL_DEPLOYMENT_PHASE environment variable to enable",
    results
  )
end

results = AssessmentHelper.check(
  "Active cities configured correctly",
  length(DeploymentConfig.active_cities()) > 0 or phase == :disabled,
  results
)

# ============================================================================
# 3. Category Mapping Assessment
# ============================================================================
AssessmentHelper.section("3️⃣ Category Mapping")

priv_dir = :code.priv_dir(:eventasaurus)
mapping_file = Path.join([priv_dir, "category_mappings", "week_pl.yml"])

results = AssessmentHelper.check("Mapping file exists", File.exists?(mapping_file), results)

if File.exists?(mapping_file) do
  case YamlElixir.read_from_file(mapping_file) do
    {:ok, data} ->
      results = AssessmentHelper.check("YAML file valid", true, results)

      mappings = Map.get(data, "mappings", %{})
      results = AssessmentHelper.check("Mappings defined", map_size(mappings) > 0, results)

      # Check key cuisine types are mapped
      key_cuisines = ["italian", "polish", "french", "japanese", "restaurant"]
      mapped_count = Enum.count(key_cuisines, fn cuisine -> Map.has_key?(mappings, cuisine) end)
      results = AssessmentHelper.check(
        "Key cuisines mapped (#{mapped_count}/#{length(key_cuisines)})",
        mapped_count >= 4,
        results
      )

      # Check all map to food-drink
      food_drink_count = Enum.count(mappings, fn {_, category} -> category == "food-drink" end)
      results = AssessmentHelper.check(
        "Most cuisines map to food-drink (#{food_drink_count}/#{map_size(mappings)})",
        food_drink_count >= div(map_size(mappings), 2),
        results
      )

    {:error, reason} ->
      results = AssessmentHelper.check("YAML file valid", false, results)
      IO.puts("    Error: #{inspect(reason)}")
  end
end

# ============================================================================
# 4. Transformer & TimeConverter Assessment
# ============================================================================
AssessmentHelper.section("4️⃣ Data Transformation")

# Test time conversion
test_date = ~D[2025-11-20]
test_slot = 1140  # 7:00 PM

case TimeConverter.convert_minutes_to_time(test_slot, test_date, "Europe/Warsaw") do
  {:ok, datetime} ->
    results = AssessmentHelper.check("Time conversion works", true, results)
    results = AssessmentHelper.check("Result is UTC DateTime", datetime.time_zone == "Etc/UTC", results)
  {:error, _} ->
    results = AssessmentHelper.check("Time conversion works", false, results)
end

results = AssessmentHelper.check("Time formatting works", TimeConverter.format_time(1140) == "7:00 PM", results)

# Test transformer
test_restaurant = %{
  "id" => "1373",
  "name" => "Test Restaurant",
  "slug" => "test-restaurant",
  "address" => "ul. Test 1",
  "city" => "Kraków",
  "cuisine" => "Italian",
  "location" => %{"lat" => 50.0, "lng" => 19.9}
}

test_festival = %{
  name: "RestaurantWeek Test",
  code: "RWT",
  starts_at: ~D[2026-03-04],
  ends_at: ~D[2026-04-22],
  price: 63.0
}

event = Transformer.transform_restaurant_slot(test_restaurant, test_slot, "2025-11-20", test_festival)

results = AssessmentHelper.check("Event external_id format correct", String.starts_with?(event.external_id, "week_pl_"), results)
results = AssessmentHelper.check("Event has consolidation key", Map.has_key?(event.metadata, :restaurant_date_id), results)
results = AssessmentHelper.check("Consolidation key format correct", event.metadata.restaurant_date_id == "1373_2025-11-20", results)
results = AssessmentHelper.check("Event has venue data", Map.has_key?(event, :venue_attributes), results)
results = AssessmentHelper.check("Event occurrence type is explicit", event.occurrence_type == :explicit, results)
results = AssessmentHelper.check("Event has starts_at", %DateTime{} = event.starts_at, results)
results = AssessmentHelper.check("Event has ends_at", %DateTime{} = event.ends_at, results)

# Check event duration is 2 hours
duration = DateTime.diff(event.ends_at, event.starts_at, :second)
results = AssessmentHelper.check("Event duration is 2 hours", duration == 7200, results)

# ============================================================================
# 5. Database & Source Registration Assessment
# ============================================================================
AssessmentHelper.section("5️⃣ Database & Source Registration")

case Repo.get_by(SourceModel, slug: "week_pl") do
  nil ->
    results = AssessmentHelper.warn(
      "Source not registered",
      "Run migration or seed to register week_pl source in database",
      results
    )

  source ->
    results = AssessmentHelper.check("Source registered in database", true, results)
    results = AssessmentHelper.check("Source has ID", source.id != nil, results)
    IO.puts("  📊 Source ID: #{source.id}")
end

# ============================================================================
# 6. Build ID Cache Assessment
# ============================================================================
AssessmentHelper.section("6️⃣ Build ID Cache")

cache_pid = Process.whereis(EventasaurusDiscovery.Sources.WeekPl.Helpers.BuildIdCache)
results = AssessmentHelper.check("BuildIdCache GenServer running", cache_pid != nil, results)

if cache_pid do
  IO.puts("  📊 BuildIdCache PID: #{inspect(cache_pid)}")
end

# ============================================================================
# 7. Festival Status Assessment
# ============================================================================
AssessmentHelper.section("7️⃣ Festival Status")

festival_active = Source.festival_active?()
IO.puts("  📅 Festival Active: #{festival_active}")

if festival_active do
  results = AssessmentHelper.check("Festival currently active", true, results)

  festivals = Source.active_festivals()
  today = Date.utc_today()

  active_festival = Enum.find(festivals, fn f ->
    Date.compare(today, f.starts_at) in [:eq, :gt] and
      Date.compare(today, f.ends_at) in [:eq, :lt]
  end)

  if active_festival do
    IO.puts("  🎉 Active Festival: #{active_festival.name} (#{active_festival.code})")
    IO.puts("  📅 Period: #{active_festival.starts_at} to #{active_festival.ends_at}")
    IO.puts("  💰 Price: #{active_festival.price} PLN")
  end
else
  results = AssessmentHelper.warn(
    "No active festival",
    "Sync will be skipped outside festival periods",
    results
  )

  # Show next festival
  festivals = Source.active_festivals()
  today = Date.utc_today()

  next_festival = festivals
  |> Enum.filter(fn f -> Date.compare(today, f.starts_at) == :lt end)
  |> Enum.sort_by(& &1.starts_at, Date)
  |> List.first()

  if next_festival do
    IO.puts("  📅 Next Festival: #{next_festival.name}")
    IO.puts("  📅 Starts: #{next_festival.starts_at}")
  end
end

# ============================================================================
# 8. Configuration Values Assessment
# ============================================================================
AssessmentHelper.section("8️⃣ Configuration Values")

results = AssessmentHelper.check("Base URL configured", Config.base_url() == "https://week.pl", results)
results = AssessmentHelper.check("Request delay configured", Config.request_delay_ms() == 2_000, results)
results = AssessmentHelper.check("Cache TTL configured", Config.build_id_cache_ttl_ms() == 3_600_000, results)
results = AssessmentHelper.check("Headers configured", is_list(Config.default_headers()), results)

# ============================================================================
# Final Summary
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts(IO.ANSI.blue() <> "📊 Assessment Summary" <> IO.ANSI.reset())

passed_count = length(results.passed)
failed_count = length(results.failed)
warning_count = length(results.warnings)
total = passed_count + failed_count

IO.puts("\n  " <> IO.ANSI.green() <> "✅ Passed: #{passed_count}/#{total}" <> IO.ANSI.reset())
if failed_count > 0 do
  IO.puts("  " <> IO.ANSI.red() <> "❌ Failed: #{failed_count}/#{total}" <> IO.ANSI.reset())
end
if warning_count > 0 do
  IO.puts("  " <> IO.ANSI.yellow() <> "⚠️  Warnings: #{warning_count}" <> IO.ANSI.reset())
end

if failed_count == 0 do
  IO.puts("\n" <> IO.ANSI.green() <> "✅ Quality assessment PASSED" <> IO.ANSI.reset())
  IO.puts("Ready for deployment to next phase.")
else
  IO.puts("\n" <> IO.ANSI.red() <> "❌ Quality assessment FAILED" <> IO.ANSI.reset())
  IO.puts("Fix failing checks before deployment.")
  IO.puts("\nFailed checks:")
  Enum.each(Enum.reverse(results.failed), fn check ->
    IO.puts("  - #{check}")
  end)
end

if warning_count > 0 do
  IO.puts("\n" <> IO.ANSI.yellow() <> "⚠️  Warnings (review but non-blocking):" <> IO.ANSI.reset())
  Enum.each(Enum.reverse(results.warnings), fn warning ->
    IO.puts("  - #{warning}")
  end)
end

IO.puts("\n" <> String.duplicate("=", 60) <> "\n")

# Exit with appropriate code
if failed_count > 0 do
  System.halt(1)
end
