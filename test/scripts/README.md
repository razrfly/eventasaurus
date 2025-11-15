# Test Utility Scripts Guide

## Purpose

This guide explains the distinction between **tests** and **utility scripts** in the test directory, and provides documentation for running, creating, and maintaining test-related utility scripts.

## Overview

### Scripts vs Tests

**Tests** are automated assertions that verify system behavior:
- Run automatically in CI/CD
- Use ExUnit framework
- Assert expected outcomes
- Fail when behavior is incorrect
- Filename pattern: `*_test.exs`

**Scripts** are utilities for development and maintenance:
- Run manually when needed
- Use plain Elixir code
- Perform audits, validations, or data operations
- Report findings but don't "fail"
- Filename pattern: `*.exs` (no `_test` suffix)

## Script Categories

### 1. Validation Scripts

**Location:** `test/scripts/validation/`

**Purpose:** Validate data integrity, configuration correctness, or system state without asserting.

**When to Use:**
- Checking production data quality
- Verifying configuration files
- Auditing database state
- Manual quality assurance

**Example: Social Card Validator**

Currently in `test/validation/social_card_validator.exs`, will be moved to `test/scripts/validation/social_card_validator.exs`.

```elixir
# test/scripts/validation/social_card_validator.exs
defmodule EventasaurusApp.SocialCardValidator do
  @moduledoc """
  Validates social card images for events.

  Usage:
    mix run test/scripts/validation/social_card_validator.exs
  """

  def validate_all do
    # Validation logic
    IO.puts("Checking social cards...")
    # Report findings
  end
end

# Run the validation
EventasaurusApp.SocialCardValidator.validate_all()
```

**Usage:**
```bash
# Run a validation script
mix run test/scripts/validation/social_card_validator.exs

# With custom options
mix run test/scripts/validation/social_card_validator.exs --env=production
```

### 2. Audit Scripts

**Location:** `test/scripts/audits/`

**Purpose:** One-off or periodic audits of system state, data quality, or technical debt.

**When to Use:**
- Investigating data anomalies
- Generating reports on system health
- Finding unused code or assets
- Analyzing test coverage gaps
- Checking for security issues

**Current Scripts (from test/one_off_scripts/):**

These 24 scripts will be moved to `test/scripts/audits/`:
- Data quality audits
- Coverage analysis
- Technical debt reports
- Performance benchmarks
- Security scans

**Example: Test Coverage Audit**

```elixir
# test/scripts/audits/test_coverage_audit.exs
defmodule EventasaurusApp.TestCoverageAudit do
  @moduledoc """
  Analyzes test coverage gaps and generates a report.

  Usage:
    mix run test/scripts/audits/test_coverage_audit.exs
  """

  def analyze do
    IO.puts("Analyzing test coverage...")

    # Find untested modules
    untested = find_untested_modules()

    # Generate report
    IO.puts("\n=== Coverage Gaps ===")
    Enum.each(untested, fn module ->
      IO.puts("❌ #{module} - No tests found")
    end)

    IO.puts("\nTotal untested modules: #{length(untested)}")
  end

  defp find_untested_modules do
    # Implementation
    []
  end
end

# Run the audit
EventasaurusApp.TestCoverageAudit.analyze()
```

**Usage:**
```bash
# Run an audit script
mix run test/scripts/audits/test_coverage_audit.exs

# Generate JSON output
mix run test/scripts/audits/test_coverage_audit.exs --format=json > coverage_report.json
```

### 3. Data Migration Scripts

**Location:** `test/scripts/migrations/`

**Purpose:** Test data migrations or transformations before applying to production.

**When to Use:**
- Testing complex database migrations
- Transforming test data
- Seeding test environments
- Data cleanup operations

**Example: Test Data Migration**

```elixir
# test/scripts/migrations/migrate_legacy_events.exs
defmodule EventasaurusApp.MigrateLegacyEvents do
  @moduledoc """
  Migrates legacy event format to new structure in test database.

  Usage:
    MIX_ENV=test mix run test/scripts/migrations/migrate_legacy_events.exs
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events

  def migrate do
    IO.puts("Starting legacy event migration...")

    # Run migration logic
    count = migrate_events()

    IO.puts("✅ Migrated #{count} events")
  end

  defp migrate_events do
    # Implementation
    0
  end
end

# Run the migration
EventasaurusApp.MigrateLegacyEvents.migrate()
```

**Usage:**
```bash
# Run in test environment
MIX_ENV=test mix run test/scripts/migrations/migrate_legacy_events.exs

# Dry run mode
MIX_ENV=test mix run test/scripts/migrations/migrate_legacy_events.exs --dry-run
```

### 4. Performance Benchmarks

**Location:** `test/scripts/benchmarks/`

**Purpose:** Run performance benchmarks outside of the normal test suite.

**When to Use:**
- Comparing algorithm performance
- Measuring query optimization improvements
- Profiling memory usage
- Load testing specific components

**Example: Query Performance Benchmark**

```elixir
# test/scripts/benchmarks/event_query_benchmark.exs
defmodule EventasaurusApp.EventQueryBenchmark do
  @moduledoc """
  Benchmarks event query performance.

  Usage:
    mix run test/scripts/benchmarks/event_query_benchmark.exs
  """

  def run do
    IO.puts("Running event query benchmarks...")

    # Setup test data
    setup_test_data()

    # Run benchmarks
    Benchee.run(%{
      "simple query" => fn -> Events.list_events() end,
      "filtered query" => fn -> Events.list_events(filters: %{status: "published"}) end,
      "complex query" => fn -> Events.list_events_with_associations() end
    })
  end

  defp setup_test_data do
    # Create test events
  end
end

# Run the benchmark
EventasaurusApp.EventQueryBenchmark.run()
```

**Usage:**
```bash
# Run benchmark
mix run test/scripts/benchmarks/event_query_benchmark.exs

# Save results to file
mix run test/scripts/benchmarks/event_query_benchmark.exs > benchmark_results.txt
```

## Script Structure Template

### Basic Script Template

```elixir
# test/scripts/category/my_script.exs
defmodule EventasaurusApp.MyScript do
  @moduledoc """
  [Brief description of what this script does]

  Usage:
    mix run test/scripts/category/my_script.exs

  Options:
    --option1=value  Description of option1
    --option2        Description of option2
  """

  # If you need the application started:
  # Application.ensure_all_started(:eventasaurus)

  def run(opts \\ []) do
    IO.puts("Starting #{__MODULE__}...")

    # Script logic here

    IO.puts("✅ Completed")
  end

  # Helper functions
  defp helper_function do
    # Implementation
  end
end

# Parse command line args if needed
opts = System.argv()
  |> OptionParser.parse(switches: [option1: :string, option2: :boolean])
  |> elem(0)

# Run the script
EventasaurusApp.MyScript.run(opts)
```

### Advanced Script with Ecto

```elixir
# test/scripts/category/advanced_script.exs
defmodule EventasaurusApp.AdvancedScript do
  @moduledoc """
  [Description]

  Usage:
    MIX_ENV=test mix run test/scripts/category/advanced_script.exs
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.{Events, Users}

  def run do
    # Ensure app is started
    Application.ensure_all_started(:eventasaurus)

    # Start Ecto sandbox for test environment
    if Mix.env() == :test do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
      {:ok, _} = Ecto.Adapters.SQL.Sandbox.start_owner(Repo, shared: true)
    end

    IO.puts("Running script...")

    # Use Repo and queries
    process_data()

    IO.puts("✅ Done")
  end

  defp process_data do
    Events.list_events()
    |> Enum.each(&process_event/1)
  end

  defp process_event(event) do
    # Process each event
  end
end

# Run the script
EventasaurusApp.AdvancedScript.run()
```

## Script Naming Conventions

### File Naming

```
✅ Good:
- test/scripts/validation/social_card_validator.exs
- test/scripts/audits/test_coverage_audit.exs
- test/scripts/migrations/migrate_legacy_events.exs
- test/scripts/benchmarks/event_query_benchmark.exs

❌ Bad:
- test/scripts/validator.exs (not specific enough)
- test/scripts/script1.exs (meaningless name)
- test/scripts/temp_fix.exs (unclear purpose)
- test/scripts/test_something_test.exs (confusing - is it a test?)
```

### Module Naming

```elixir
# Match the file path
# test/scripts/validation/social_card_validator.exs
defmodule EventasaurusApp.SocialCardValidator
  # Name should clearly indicate purpose
end

# test/scripts/audits/test_coverage_audit.exs
defmodule EventasaurusApp.TestCoverageAudit
  # Include category if helpful for organization
end
```

## Running Scripts

### Basic Execution

```bash
# Run a script
mix run test/scripts/category/script_name.exs

# Run in specific environment
MIX_ENV=test mix run test/scripts/category/script_name.exs
MIX_ENV=dev mix run test/scripts/category/script_name.exs
```

### With Options

```bash
# Pass command line arguments
mix run test/scripts/validation/validator.exs --env=production --verbose

# With environment variables
DATABASE_URL=postgres://... mix run test/scripts/migrations/migrate.exs
```

### With IEx (Interactive)

```bash
# Start IEx with the script loaded
iex -S mix run test/scripts/category/script_name.exs

# Then in IEx:
iex> EventasaurusApp.MyScript.run()
```

## Creating a New Script

### Step 1: Choose Category

Decide which category fits your script:
- **validation/** - Validating data or configuration
- **audits/** - One-off analysis or reporting
- **migrations/** - Data transformation or migration testing
- **benchmarks/** - Performance measurement

### Step 2: Create the File

```bash
# Create the script file
touch test/scripts/category/my_new_script.exs

# Make it executable (optional)
chmod +x test/scripts/category/my_new_script.exs
```

### Step 3: Add Documentation

Use the script template above and include:
- Clear module documentation
- Usage examples
- Description of options
- Expected output

### Step 4: Test the Script

```bash
# Run your script
mix run test/scripts/category/my_new_script.exs

# Verify output
# Check for errors
```

### Step 5: Document Purpose

Add to this README under the appropriate category:
- What the script does
- When to run it
- What output to expect

## Script Best Practices

### DO ✅

- **Use descriptive names** that explain what the script does
- **Include @moduledoc** with usage examples
- **Print progress** for long-running scripts
- **Handle errors gracefully** with clear error messages
- **Document options** and expected behavior
- **Use OptionParser** for command line arguments
- **Test in dev/test** before running in production
- **Include dry-run mode** for destructive operations
- **Log results** for auditing purposes
- **Make scripts idempotent** when possible

**Example: Good Script with All Best Practices**

```elixir
# test/scripts/audits/unused_images_audit.exs
defmodule EventasaurusApp.UnusedImagesAudit do
  @moduledoc """
  Finds unused images in the uploads directory.

  Usage:
    mix run test/scripts/audits/unused_images_audit.exs [options]

  Options:
    --path=PATH      Directory to scan (default: priv/static/uploads)
    --dry-run        Don't delete, just report
    --format=FORMAT  Output format: text|json|csv (default: text)

  Examples:
    # Scan default directory
    mix run test/scripts/audits/unused_images_audit.exs

    # Scan custom directory with JSON output
    mix run test/scripts/audits/unused_images_audit.exs --path=/tmp/uploads --format=json
  """

  require Logger

  def run(opts \\ []) do
    path = Keyword.get(opts, :path, "priv/static/uploads")
    dry_run = Keyword.get(opts, :dry_run, true)
    format = Keyword.get(opts, :format, "text")

    Logger.info("Starting unused images audit...")
    Logger.info("Scanning: #{path}")
    Logger.info("Dry run: #{dry_run}")

    # Find unused images
    unused = find_unused_images(path)

    # Output results
    output_results(unused, format)

    # Cleanup if not dry run
    if not dry_run do
      cleanup_unused(unused)
    end

    Logger.info("✅ Audit complete")
  rescue
    e ->
      Logger.error("❌ Error: #{Exception.message(e)}")
      reraise e, __STACKTRACE__
  end

  defp find_unused_images(path) do
    Logger.info("Scanning for unused images...")
    # Implementation
    []
  end

  defp output_results(unused, "json") do
    Jason.encode!(unused) |> IO.puts()
  end

  defp output_results(unused, "csv") do
    # CSV output
  end

  defp output_results(unused, "text") do
    IO.puts("\n=== Unused Images ===")
    Enum.each(unused, fn image ->
      IO.puts("❌ #{image}")
    end)
    IO.puts("\nTotal: #{length(unused)}")
  end

  defp cleanup_unused(unused) do
    Logger.info("Cleaning up #{length(unused)} unused images...")
    # Cleanup logic
  end
end

# Parse options
{opts, _, _} = OptionParser.parse(
  System.argv(),
  switches: [
    path: :string,
    dry_run: :boolean,
    format: :string
  ]
)

# Run the script
EventasaurusApp.UnusedImagesAudit.run(opts)
```

### DON'T ❌

- **Don't mix tests and scripts** - Keep them separate
- **Don't hardcode credentials** - Use environment variables
- **Don't leave debug code** - Clean up before committing
- **Don't run destructive operations** without confirmation
- **Don't assume application is started** - Start it in the script
- **Don't ignore errors silently** - Log and handle properly
- **Don't forget to document** - Scripts without docs are useless
- **Don't put secrets in scripts** - Use environment variables
- **Don't leave temporary files** - Clean up after execution
- **Don't modify production data** without backups

## Common Patterns

### Pattern 1: Database Query Script

```elixir
# test/scripts/audits/orphaned_records_audit.exs
defmodule EventasaurusApp.OrphanedRecordsAudit do
  @moduledoc """
  Finds orphaned records in the database.
  """

  alias EventasaurusApp.Repo
  import Ecto.Query

  def run do
    Application.ensure_all_started(:eventasaurus)

    IO.puts("Finding orphaned records...")

    orphaned_events = find_orphaned_events()
    orphaned_tickets = find_orphaned_tickets()

    IO.puts("\n=== Results ===")
    IO.puts("Orphaned events: #{length(orphaned_events)}")
    IO.puts("Orphaned tickets: #{length(orphaned_tickets)}")
  end

  defp find_orphaned_events do
    from(e in "events",
      left_join: u in "users",
      on: e.owner_id == u.id,
      where: is_nil(u.id),
      select: e.id
    )
    |> Repo.all()
  end

  defp find_orphaned_tickets do
    # Similar query
    []
  end
end

EventasaurusApp.OrphanedRecordsAudit.run()
```

### Pattern 2: File System Script

```elixir
# test/scripts/audits/large_files_audit.exs
defmodule EventasaurusApp.LargeFilesAudit do
  @moduledoc """
  Finds large files in the project.
  """

  def run(min_size_mb \\ 10) do
    IO.puts("Finding files larger than #{min_size_mb}MB...")

    large_files = find_large_files(min_size_mb)

    IO.puts("\n=== Large Files ===")
    Enum.each(large_files, fn {path, size_mb} ->
      IO.puts("#{size_mb}MB - #{path}")
    end)

    IO.puts("\nTotal: #{length(large_files)}")
  end

  defp find_large_files(min_size_mb) do
    min_bytes = min_size_mb * 1024 * 1024

    "**/*"
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(fn path ->
      {path, File.stat!(path).size}
    end)
    |> Enum.filter(fn {_path, size} -> size > min_bytes end)
    |> Enum.map(fn {path, size} ->
      {path, Float.round(size / 1024 / 1024, 2)}
    end)
    |> Enum.sort_by(fn {_path, size} -> size end, :desc)
  end
end

EventasaurusApp.LargeFilesAudit.run()
```

### Pattern 3: External API Script

```elixir
# test/scripts/validation/api_endpoints_validator.exs
defmodule EventasaurusApp.ApiEndpointsValidator do
  @moduledoc """
  Validates external API endpoints are responding.
  """

  def run do
    IO.puts("Validating API endpoints...")

    endpoints = [
      {"Bandsintown", "https://api.bandsintown.com/health"},
      {"Geocoding", "https://maps.googleapis.com/maps/api/geocode/json"},
      # More endpoints
    ]

    results = Enum.map(endpoints, &check_endpoint/1)

    IO.puts("\n=== Results ===")
    Enum.each(results, fn {name, status} ->
      icon = if status == :ok, do: "✅", else: "❌"
      IO.puts("#{icon} #{name}")
    end)
  end

  defp check_endpoint({name, url}) do
    case HTTPoison.get(url, [], timeout: 5000) do
      {:ok, %{status_code: code}} when code in 200..299 ->
        {name, :ok}
      _ ->
        {name, :error}
    end
  rescue
    _ -> {name, :error}
  end
end

EventasaurusApp.ApiEndpointsValidator.run()
```

### Pattern 4: CSV Export Script

```elixir
# test/scripts/audits/user_activity_export.exs
defmodule EventasaurusApp.UserActivityExport do
  @moduledoc """
  Exports user activity to CSV.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Users

  def run(output_path \\ "user_activity.csv") do
    Application.ensure_all_started(:eventasaurus)

    IO.puts("Exporting user activity to #{output_path}...")

    users = Users.list_users()
    csv_data = generate_csv(users)

    File.write!(output_path, csv_data)

    IO.puts("✅ Exported #{length(users)} users")
  end

  defp generate_csv(users) do
    header = "ID,Email,Events Created,Last Login\n"

    rows = Enum.map(users, fn user ->
      "#{user.id},#{user.email},#{count_events(user)},#{format_date(user.last_login_at)}\n"
    end)

    header <> Enum.join(rows)
  end

  defp count_events(user) do
    # Count logic
    0
  end

  defp format_date(nil), do: "Never"
  defp format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")
end

[output_path | _] = System.argv() ++ ["user_activity.csv"]
EventasaurusApp.UserActivityExport.run(output_path)
```

## Troubleshooting

### Script Won't Run

**Problem:** `mix run` fails with "module not found"

**Solutions:**
```bash
# Make sure you're in the project root
cd /path/to/eventasaurus

# Compile the project first
mix compile

# Then run the script
mix run test/scripts/category/script.exs
```

### Database Connection Errors

**Problem:** Script can't connect to database

**Solutions:**
```bash
# Ensure application is started in script
Application.ensure_all_started(:eventasaurus)

# Run with specific environment
MIX_ENV=test mix run test/scripts/category/script.exs

# Check database configuration
mix ecto.setup  # If database doesn't exist
```

### Ecto Sandbox Errors

**Problem:** "cannot run query outside of sandbox"

**Solutions:**
```elixir
# In your script, add:
if Mix.env() == :test do
  Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
  {:ok, _} = Ecto.Adapters.SQL.Sandbox.start_owner(Repo, shared: true)
end
```

### Timeout Errors

**Problem:** Script times out on long operations

**Solutions:**
```elixir
# Increase timeout for HTTP requests
HTTPoison.get(url, [], timeout: 60_000, recv_timeout: 60_000)

# Process data in batches
Stream.chunk_every(large_list, 100)
|> Stream.each(&process_batch/1)
|> Stream.run()
```

## Script Checklist

When creating a new script:

- [ ] Choose appropriate category (validation/audits/migrations/benchmarks)
- [ ] Use descriptive filename and module name
- [ ] Add @moduledoc with usage examples
- [ ] Include command line option handling
- [ ] Add progress indicators for long operations
- [ ] Handle errors with clear messages
- [ ] Include dry-run mode for destructive operations
- [ ] Test in dev/test environment first
- [ ] Document in this README
- [ ] Commit with clear description

## Migration Plan

### Phase 5: Scripts Organization (Week 5)

As part of the test suite reorganization (see `test/README.md`), scripts will be moved:

**From:**
```
test/
├── validation/
│   └── social_card_validator.exs
└── one_off_scripts/
    └── [24 files]
```

**To:**
```
test/scripts/
├── validation/
│   └── social_card_validator.exs
├── audits/
│   └── [24 files from one_off_scripts/]
├── migrations/
└── benchmarks/
```

**Migration Tasks:**
1. Create category directories
2. Review each script in one_off_scripts/
3. Categorize as validation, audit, migration, or benchmark
4. Move and update documentation
5. Update any references in documentation
6. Delete old directories

**Success Criteria:**
- All scripts organized by category
- Each script has clear documentation
- No scripts in old locations
- Scripts run successfully from new locations

## Related Documentation

- **[test/README.md](../README.md)** - Main test suite documentation
- **[test/BEST_PRACTICES.md](../BEST_PRACTICES.md)** - Testing best practices
- **[test/discovery/sources/README.md](../discovery/sources/README.md)** - Discovery source testing

---

_For questions about test utility scripts, consult this guide or ask in #engineering._
