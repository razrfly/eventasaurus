# Test Suite Documentation

## Purpose

This directory contains the **comprehensive test suite** for Eventasaurus. Tests are organized by type and purpose to make it easy to find, run, and add tests.

**Organization Philosophy:** Tests are categorized by type first (unit, integration, e2e), then by application layer or domain. This structure makes it clear where new tests should go and enables efficient test execution.

## Quick Start

```bash
# Run all tests
mix test

# Run tests by type
mix test test/unit/              # Unit tests only (fast)
mix test test/integration/       # Integration tests
mix test test/web/               # Web layer tests
mix test --only wallaby          # E2E browser tests only

# Run tests by domain
mix test test/discovery/         # Discovery/scraping tests
mix test test/discovery/sources/bandsintown/  # Specific source

# Exclude slow tests
mix test --exclude wallaby       # Skip E2E tests
mix test --exclude external_api  # Skip tests requiring live APIs

# Run specific test file
mix test test/unit/contexts/events/event_test.exs

# Run with coverage
mix test --cover

# Run in watch mode (requires mix_test_watch)
mix test.watch
```

## Test Suite Overview

### By the Numbers
- **157 total test files** (as of reorganization start)
- **Target: <2 minutes** for core test suite (excluding E2E)
- **~17 seconds** for full suite with E2E tests
- **92% performance improvement** achieved through optimization

### Test Types

**Unit Tests** (`test/unit/`) - ⚡ Fast, isolated
- Business logic and context tests
- Schema/model validation
- Utility services
- **Run time:** <100ms per test typically

**Integration Tests** (`test/integration/`) - 🔗 Component interaction
- Multi-component workflows
- Feature integration (non-browser)
- Authentication flows
- **Run time:** <500ms per test typically

**Web Tests** (`test/web/`) - 🌐 Phoenix web layer
- Controller tests
- LiveView rendering and events
- Component tests
- JSON-LD schema validation
- **Run time:** <200ms per test typically

**E2E Tests** (`test/e2e/`) - 🎭 Full user journeys
- Browser automation with Wallaby
- Complete user workflows
- Smoke tests for critical paths
- **Run time:** 2-10 seconds per test

**Discovery Tests** (`test/discovery/`) - 🔍 Scraping system
- Source-specific scraper tests (14 sources)
- Geocoding and parsing
- Full pipeline integration
- **Run time:** Varies by source

**Performance Tests** (`test/performance/`) - ⚡ Benchmarking
- Load testing
- Stress testing
- Performance regression detection
- **Run time:** Minutes to hours

## Directory Structure

```
test/
├── README.md                    # This file - comprehensive test guide
├── BEST_PRACTICES.md           # Testing best practices and guidelines
├── test_helper.exs             # Test configuration and setup
├── performance_optimization_guide.md  # Performance optimization documentation
│
├── unit/                       # ⚡ Fast, isolated unit tests
│   ├── contexts/              # Business logic contexts
│   │   ├── auth/
│   │   ├── events/
│   │   ├── venues/
│   │   ├── groups/
│   │   ├── polls/
│   │   └── tickets/
│   ├── schemas/              # Schema/model tests
│   └── services/            # Utility services
│       ├── cdn/
│       ├── emails/
│       └── social_cards/
│
├── integration/               # 🔗 Multi-component integration tests
│   ├── auth/                # Authentication flows
│   ├── workflows/          # Multi-step business processes
│   │   └── city_management/
│   └── features/          # Feature integration (non-E2E)
│
├── web/                      # 🌐 Phoenix web layer tests
│   ├── controllers/
│   ├── live/              # LiveView tests
│   │   ├── event_live/
│   │   ├── components/
│   │   └── admin/
│   ├── components/       # Standalone components
│   ├── json_ld/         # Structured data/schema tests
│   ├── helpers/
│   └── services/
│
├── e2e/                     # 🎭 End-to-end tests (Wallaby)
│   ├── smoke/            # Quick sanity checks
│   ├── journeys/        # Full user journeys
│   │   ├── admin/
│   │   └── public/
│   └── features/       # Feature-specific E2E
│
├── discovery/             # 🔍 Event discovery/scraping system
│   ├── unit/           # Unit tests for discovery components
│   │   ├── geocoding/
│   │   ├── parsers/
│   │   ├── helpers/
│   │   └── utils/
│   ├── sources/       # Per-source scraper tests
│   │   ├── bandsintown/
│   │   ├── quizmeisters/
│   │   ├── sortiraparis/
│   │   └── README.md  # Source testing guide
│   ├── integration/  # Full pipeline integration
│   └── admin/       # Discovery admin features
│
├── performance/        # ⚡ Performance & stress tests
│   └── README.md      # Performance testing guide
│
├── support/           # 🛠️ Test support files
│   ├── cases/
│   │   ├── conn_case.ex
│   │   ├── data_case.ex
│   │   └── feature_case.ex
│   ├── factories/
│   │   └── factory.ex
│   ├── fixtures/
│   └── helpers/
│       └── performance_helpers.ex
│
├── scripts/          # 📝 Non-test utility scripts
│   ├── README.md    # Script documentation
│   ├── validation/  # Validation scripts
│   └── audit/      # Audit and debugging scripts
│
└── archived/        # 🗄️ Deprecated tests to review/delete
    └── README.md   # Archival policy
```

## Test Categorization Rules

Use this decision tree to determine where a new test should go:

### Decision Tree

```
Is it testing a web component (controller, LiveView, HTML)?
├─ YES → test/web/
│   ├─ Controller? → test/web/controllers/
│   ├─ LiveView? → test/web/live/
│   ├─ Component? → test/web/components/
│   └─ JSON-LD? → test/web/json_ld/
└─ NO → Continue...

Does it use Wallaby for browser automation?
├─ YES → test/e2e/
│   ├─ Quick sanity check? → test/e2e/smoke/
│   ├─ Full user journey? → test/e2e/journeys/
│   └─ Feature-specific? → test/e2e/features/
└─ NO → Continue...

Does it test multiple components working together?
├─ YES → test/integration/
│   ├─ Auth flow? → test/integration/auth/
│   ├─ Multi-step workflow? → test/integration/workflows/
│   └─ Feature integration? → test/integration/features/
└─ NO → Continue...

Is it part of the discovery/scraping system?
├─ YES → test/discovery/
│   ├─ Source-specific? → test/discovery/sources/<source>/
│   ├─ Full pipeline? → test/discovery/integration/
│   ├─ Admin feature? → test/discovery/admin/
│   └─ Unit component? → test/discovery/unit/
└─ NO → Continue...

Is it a performance or stress test?
├─ YES → test/performance/
└─ NO → test/unit/
    ├─ Context logic? → test/unit/contexts/<context>/
    ├─ Schema/model? → test/unit/schemas/
    └─ Service/utility? → test/unit/services/<service>/
```

### Test Type Characteristics

**Unit Tests** (`test/unit/`)
- ✅ Fast (< 100ms typically)
- ✅ Isolated (no external dependencies)
- ✅ Tests single function/module
- ✅ May use database for data setup
- ✅ `async: true` when possible
- ✅ Tag: None (run by default)

**Integration Tests** (`test/integration/`)
- ✅ Tests multiple components together
- ✅ May use database
- ✅ Tests component interactions
- ❌ No browser automation
- ✅ `async: false` if shared state
- ✅ Tag: `:integration` (optional, for clarity)

**E2E Tests** (`test/e2e/`)
- ✅ Full user workflows
- ✅ Uses Wallaby for browser automation
- ✅ Tests complete features end-to-end
- ⚠️ Slower than other tests
- ✅ `async: false` (browser sessions)
- ✅ Tag: `:wallaby` (required)

**Web Tests** (`test/web/`)
- ✅ Tests web layer (controllers, LiveView, components)
- ✅ Uses ConnCase or LiveViewTest
- ❌ Not full E2E (no browser)
- ✅ May test rendering, events, forms
- ✅ `async: true` when possible
- ✅ Tag: None (run by default)

**Discovery Tests** (`test/discovery/`)
- ✅ Tests scraping/discovery system
- ✅ Source tests in `sources/<source>/`
- ✅ Unit components in `unit/`
- ✅ Full pipeline in `integration/`
- ✅ Tag: `:external_api` for live API tests

## Running Tests

### By Type

```bash
# Fast tests only (exclude E2E)
mix test --exclude wallaby

# Unit tests only
mix test test/unit/

# Integration tests
mix test test/integration/

# Web layer tests
mix test test/web/

# E2E tests only
mix test --only wallaby

# Discovery tests
mix test test/discovery/

# Performance tests
mix test test/performance/
```

### By Tag

```bash
# Only Wallaby E2E tests
mix test --only wallaby

# Exclude external API tests (don't make real API calls)
mix test --exclude external_api

# Only integration tests
mix test --only integration

# Exclude stress tests
mix test --exclude stress
```

### By Domain

```bash
# Event-related tests
mix test test/unit/contexts/events/
mix test test/web/live/event_live/

# Auth tests
mix test test/unit/contexts/auth/
mix test test/integration/auth/

# Specific discovery source
mix test test/discovery/sources/bandsintown/
```

### Development Workflows

```bash
# Fast feedback loop (exclude E2E)
mix test --exclude wallaby

# Full test suite (CI equivalent)
mix test

# Watch mode for TDD
mix test.watch test/unit/contexts/events/

# With coverage report
mix test --cover
open cover/excoveralls.html

# Specific test with line number
mix test test/unit/contexts/events/event_test.exs:42

# Re-run with specific seed (for debugging flaky tests)
mix test --seed 123456
```

## Test Configuration

### test_helper.exs

The test helper configures:
- ExUnit settings (parallelization, timeouts)
- Database sandbox mode
- Tag exclusions (`:external_api` by default)
- Performance monitoring

See `test/test_helper.exs` for current configuration.

### Performance Optimization

The test suite is optimized for fast execution:
- **Parallelization:** 20 concurrent test cases (2x CPU cores)
- **Database pool:** 40 connections (4x CPU cores)
- **Async tests:** Run concurrently when safe
- **Sandbox mode:** Isolated database transactions

See [performance_optimization_guide.md](./performance_optimization_guide.md) for details.

## Test Support Files

### Test Cases (`test/support/cases/`)

**conn_case.ex** - Controller and plug tests
- Sets up `%Plug.Conn{}`
- Provides routing helpers
- Use: `use EventasaurusWeb.ConnCase`

**data_case.ex** - Database and context tests
- Sets up Ecto sandbox
- Provides database helpers
- Use: `use EventasaurusApp.DataCase`

**feature_case.ex** - E2E browser tests
- Sets up Wallaby
- Configures browser driver
- Use: `use EventasaurusWeb.FeatureCase`

### Factories (`test/support/factories/`)

**factory.ex** - ExMachina factory definitions
- Provides `insert/2`, `build/2`, etc.
- Realistic test data generation
- Use: `import EventasaurusApp.Factory`

Example:
```elixir
# Create test data
user = insert(:user, email: "test@example.com")
event = insert(:event, creator: user)
```

### Fixtures (`test/support/fixtures/`)

Static test data files:
- HTML fixtures for scraper tests
- JSON response fixtures
- Image files for upload tests

### Helpers (`test/support/helpers/`)

**performance_helpers.ex** - Performance measurement
- `measure_time/1` - Measure execution time
- Batch entity creation
- Performance statistics

## Common Test Patterns

### Unit Test Pattern

```elixir
defmodule EventasaurusApp.Events.EventTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Events

  describe "create_event/1" do
    test "creates event with valid attributes" do
      user = insert(:user)
      attrs = %{title: "Test Event", creator_id: user.id}

      assert {:ok, event} = Events.create_event(attrs)
      assert event.title == "Test Event"
    end

    test "returns error with invalid attributes" do
      assert {:error, changeset} = Events.create_event(%{})
      assert "can't be blank" in errors_on(changeset).title
    end
  end
end
```

### Integration Test Pattern

```elixir
defmodule EventasaurusApp.Integration.TicketingFlowTest do
  use EventasaurusApp.DataCase

  @moduletag :integration

  describe "complete ticketing flow" do
    test "user can purchase ticket and receive confirmation" do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)

      # Purchase ticket
      assert {:ok, order} = Ticketing.purchase_ticket(user, event)

      # Verify order created
      assert order.user_id == user.id

      # Verify email sent
      assert_email_sent(to: user.email, subject: ~r/Ticket Confirmation/)
    end
  end
end
```

### Web Test Pattern

```elixir
defmodule EventasaurusWeb.EventLive.ShowTest do
  use EventasaurusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "event show page" do
    test "displays event details", %{conn: conn} do
      event = insert(:event, title: "Test Event")

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      assert html =~ "Test Event"
      assert has_element?(view, "h1", "Test Event")
    end
  end
end
```

### E2E Test Pattern

```elixir
defmodule EventasaurusWeb.E2E.UserJourneyTest do
  use EventasaurusWeb.FeatureCase

  @moduletag :wallaby

  describe "public user journey" do
    test "user can browse and view event", %{session: session} do
      event = insert(:event, title: "Concert")

      session
      |> visit("/")
      |> assert_has(Query.text("Concert"))
      |> click(Query.link("Concert"))
      |> assert_has(Query.css("h1", text: "Concert"))
    end
  end
end
```

### Discovery Source Test Pattern

```elixir
defmodule EventasaurusDiscovery.Sources.Bandsintown.TransformerTest do
  use EventasaurusApp.DataCase, async: true

  describe "transform/1" do
    test "transforms API response to event attributes" do
      fixture = read_fixture("bandsintown_event.json")

      assert {:ok, attrs} = Transformer.transform(fixture)
      assert attrs.title == "Concert Name"
      assert attrs.venue_name == "Venue Name"
    end
  end
end
```

## Troubleshooting

### Tests Are Slow

**Problem:** Test suite takes >2 minutes

**Solutions:**
1. Exclude E2E tests: `mix test --exclude wallaby`
2. Run specific test subset: `mix test test/unit/`
3. Check database pool size in `config/test.exs`
4. Profile with `mix profile.eprof`
5. See [performance_optimization_guide.md](./performance_optimization_guide.md)

### Flaky Tests

**Problem:** Tests fail randomly

**Solutions:**
1. Identify the seed: `mix test --seed XXXXX`
2. Check for async issues (use `async: false`)
3. Look for timing-dependent code
4. Check for shared database state
5. Review Wallaby waits (use `assert_has` not `find`)

### Database Connection Errors

**Problem:** "connection not available" errors

**Solutions:**
1. Increase pool size in `config/test.exs`
2. Ensure proper sandbox usage
3. Check for connection leaks
4. Reduce `max_cases` in `test_helper.exs`

### Wallaby/Browser Errors

**Problem:** Wallaby tests fail with browser errors

**Solutions:**
1. Verify Chrome/chromedriver installed
2. Check version compatibility
3. Increase timeout: `@moduletag timeout: 120_000`
4. Use headless mode in CI
5. Check for JavaScript errors in browser console

## Adding New Tests

### Quick Guidelines

1. **Determine test type** - Use decision tree above
2. **Find appropriate directory** - Follow structure
3. **Use appropriate test case** - ConnCase, DataCase, or FeatureCase
4. **Add tags if needed** - `:wallaby`, `:external_api`, `:integration`
5. **Follow naming conventions** - `*_test.exs`
6. **Use factories for data** - Don't hardcode IDs
7. **Write descriptive test names** - Clear intent
8. **Keep tests focused** - One assertion per test when possible

### Where Should My Test Go?

See [BEST_PRACTICES.md](./BEST_PRACTICES.md) for comprehensive guidelines.

**Quick reference:**
- Testing a context function? → `test/unit/contexts/<context>/`
- Testing a LiveView? → `test/web/live/<live_view>/`
- Testing user workflow with browser? → `test/e2e/journeys/`
- Testing a scraper? → `test/discovery/sources/<source>/`
- Testing multiple components together? → `test/integration/`

## CI/CD Integration

### GitHub Actions

Tests run automatically on:
- Every push to branches
- Pull requests
- Daily scheduled runs

Test workflow includes:
- Full test suite execution
- Coverage reporting
- Performance monitoring
- Slack notifications on failure

### Coverage Requirements

Target coverage thresholds:
- **Overall:** >80%
- **Contexts:** >90%
- **Web layer:** >75%
- **Discovery:** >70%

## Performance Benchmarks

**Current Performance (as of reorganization):**
- **Core test suite:** 1.4 seconds (excluding E2E)
- **Full suite with E2E:** ~17 seconds
- **92% improvement** from original 16.7 seconds

**Target Performance:**
- Core suite: <2 minutes ✅ Achieved
- Full suite: <5 minutes ✅ Achieved
- Individual unit tests: <100ms
- Individual integration tests: <500ms
- Individual E2E tests: <10 seconds

## Documentation

**Essential Guides:**
- **[BEST_PRACTICES.md](./BEST_PRACTICES.md)** - Testing best practices and patterns
- **[performance_optimization_guide.md](./performance_optimization_guide.md)** - Performance optimization
- **[test/discovery/sources/README.md](./discovery/sources/README.md)** - Discovery source testing
- **[test/scripts/README.md](./scripts/README.md)** - Utility scripts documentation

**External Resources:**
- [Phoenix Testing Guide](https://hexdocs.pm/phoenix/testing.html)
- [Phoenix LiveView Testing](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit/ExUnit.html)
- [Wallaby Documentation](https://hexdocs.pm/wallaby/readme.html)

## Contributing

When adding tests:
1. ✅ Follow the directory structure
2. ✅ Use appropriate test case
3. ✅ Add proper tags
4. ✅ Write clear test names
5. ✅ Use factories for data
6. ✅ Keep tests focused and fast
7. ✅ Update documentation if adding new patterns

## Questions?

**Where should I add my test?**
- See decision tree above or [BEST_PRACTICES.md](./BEST_PRACTICES.md)

**How do I test with external APIs?**
- Tag with `:external_api` and see discovery source examples

**How do I make tests faster?**
- Use `async: true`, optimize database queries, see [performance_optimization_guide.md](./performance_optimization_guide.md)

**How do I test browser interactions?**
- Use Wallaby in `test/e2e/`, see [BEST_PRACTICES.md](./BEST_PRACTICES.md)

Need more help? Check the team wiki or ask in #engineering.

---

_Test suite reorganized following the successful seed reorganization pattern from [Issue #2239](https://github.com/razrfly/eventasaurus/issues/2239). See [Issue #2245](https://github.com/razrfly/eventasaurus/issues/2245) for reorganization details._
