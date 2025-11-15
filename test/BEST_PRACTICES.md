# Test Suite Best Practices

## Purpose

This guide provides comprehensive best practices for writing, organizing, and maintaining tests in the Eventasaurus test suite. Follow these guidelines to ensure consistent, maintainable, and effective tests.

**Goal:** Write tests that are fast, reliable, maintainable, and provide confidence in the codebase.

## Table of Contents

- [When to Write Each Type of Test](#when-to-write-each-type-of-test)
- [Test Naming Conventions](#test-naming-conventions)
- [Test Structure and Organization](#test-structure-and-organization)
- [Factory and Fixture Usage](#factory-and-fixture-usage)
- [Tagging Strategy](#tagging-strategy)
- [Performance Best Practices](#performance-best-practices)
- [Common Patterns](#common-patterns)
- [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
- [Test Data Management](#test-data-management)
- [Async vs Sync Tests](#async-vs-sync-tests)

---

## When to Write Each Type of Test

### Unit Tests (`test/unit/`)

**When to write:**
- Testing a single function or module in isolation
- Testing business logic in contexts
- Testing schema validations
- Testing utility services
- Testing data transformations

**Characteristics:**
- ✅ Fast (< 100ms typically)
- ✅ No external dependencies
- ✅ May use database for test data setup
- ✅ Tests one thing
- ✅ Easy to debug

**Example:**
```elixir
defmodule EventasaurusApp.Events.EventTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Events

  describe "create_event/1" do
    test "creates event with valid attributes" do
      user = insert(:user)
      attrs = %{
        title: "Test Event",
        creator_id: user.id,
        start_time: ~U[2024-06-01 18:00:00Z]
      }

      assert {:ok, event} = Events.create_event(attrs)
      assert event.title == "Test Event"
      assert event.creator_id == user.id
    end

    test "returns error with invalid attributes" do
      assert {:error, changeset} = Events.create_event(%{})
      assert "can't be blank" in errors_on(changeset).title
    end

    test "validates start_time is in future" do
      user = insert(:user)
      past_time = DateTime.add(DateTime.utc_now(), -1, :day)

      attrs = %{
        title: "Event",
        creator_id: user.id,
        start_time: past_time
      }

      assert {:error, changeset} = Events.create_event(attrs)
      assert "must be in the future" in errors_on(changeset).start_time
    end
  end
end
```

**When NOT to write unit tests:**
- Testing complete user workflows (use E2E)
- Testing multiple components together (use integration)
- Testing UI rendering (use web or E2E)

---

### Integration Tests (`test/integration/`)

**When to write:**
- Testing multiple components working together
- Testing workflows that span multiple contexts
- Testing feature integration (non-browser)
- Testing external service integration (with mocks)

**Characteristics:**
- ✅ Tests component interactions
- ✅ May involve multiple contexts
- ✅ Uses database
- ❌ No browser automation
- ⚠️ Slower than unit tests

**Example:**
```elixir
defmodule EventasaurusApp.Integration.TicketingFlowTest do
  use EventasaurusApp.DataCase

  @moduletag :integration

  alias EventasaurusApp.{Events, Tickets, Notifications}

  describe "complete ticketing flow" do
    test "user can purchase ticket and receive confirmation" do
      # Setup
      event = insert(:event, is_ticketed: true, ticket_price: 25.00)
      user = insert(:user, email: "test@example.com")

      # Act - Purchase ticket
      assert {:ok, order} = Tickets.purchase_ticket(user, event)

      # Assert - Order created
      assert order.user_id == user.id
      assert order.event_id == event.id
      assert Decimal.eq?(order.total_amount, Decimal.new("25.00"))

      # Assert - Inventory updated
      assert Events.get_available_ticket_count(event) ==
               event.ticket_capacity - 1

      # Assert - Confirmation email queued
      assert [email] = Notifications.get_queued_emails()
      assert email.to == user.email
      assert email.subject =~ "Ticket Confirmation"
    end

    test "handles concurrent purchases correctly" do
      event = insert(:event, ticket_capacity: 1)
      user1 = insert(:user)
      user2 = insert(:user)

      # Simulate concurrent purchases
      tasks = [
        Task.async(fn -> Tickets.purchase_ticket(user1, event) end),
        Task.async(fn -> Tickets.purchase_ticket(user2, event) end)
      ]

      results = Task.await_many(tasks)

      # Only one should succeed
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, _}, &1)) == 1
    end
  end
end
```

**When NOT to write integration tests:**
- Testing single functions (use unit)
- Testing complete user workflows with UI (use E2E)
- Testing simple CRUD operations (use unit)

---

### Web Tests (`test/web/`)

**When to write:**
- Testing controllers and HTTP endpoints
- Testing LiveView rendering and events
- Testing UI components
- Testing HTML generation
- Testing JSON API responses
- Testing JSON-LD structured data

**Characteristics:**
- ✅ Tests web layer specifically
- ✅ Uses ConnCase or LiveViewTest
- ❌ No browser automation
- ✅ Fast rendering tests
- ✅ Can test interactive LiveView events

**Controller Example:**
```elixir
defmodule EventasaurusWeb.EventControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  describe "GET /api/events/:id" do
    test "returns event JSON", %{conn: conn} do
      event = insert(:event, title: "Test Event")

      conn = get(conn, ~p"/api/events/#{event.id}")

      assert json = json_response(conn, 200)
      assert json["title"] == "Test Event"
      assert json["id"] == event.id
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      conn = get(conn, ~p"/api/events/99999")
      assert json_response(conn, 404)
    end
  end
end
```

**LiveView Example:**
```elixir
defmodule EventasaurusWeb.EventLive.ShowTest do
  use EventasaurusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "event show page" do
    test "displays event details", %{conn: conn} do
      event = insert(:event, title: "Concert", description: "Rock show")

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Test initial render
      assert html =~ "Concert"
      assert html =~ "Rock show"

      # Test LiveView elements
      assert has_element?(view, "h1", "Concert")
      assert has_element?(view, "[data-role='event-description']")
    end

    test "handles attend button click", %{conn: conn} do
      event = insert(:event)
      user = insert(:user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Click attend button
      view
      |> element("button", "Attend")
      |> render_click()

      # Verify participant added
      assert has_element?(view, "[data-role='attendance-confirmed']")
    end
  end
end
```

**When NOT to write web tests:**
- Testing business logic (use unit)
- Testing complete user journeys (use E2E)
- Testing browser-specific behavior (use E2E)

---

### E2E Tests (`test/e2e/`)

**When to write:**
- Testing complete user workflows
- Testing critical user journeys
- Testing browser-specific functionality
- Testing cross-page interactions
- Testing JavaScript interactions
- Smoke testing critical paths

**Characteristics:**
- ✅ Tests complete features
- ✅ Uses Wallaby for browser automation
- ✅ Catches integration issues
- ⚠️ Slowest tests (2-10 seconds each)
- ⚠️ More fragile than unit tests
- ✅ Highest confidence in features

**Example:**
```elixir
defmodule EventasaurusWeb.E2E.EventCreationJourneyTest do
  use EventasaurusWeb.FeatureCase

  @moduletag :wallaby

  import Wallaby.Query

  describe "event creator journey" do
    test "user can create and publish event", %{session: session} do
      user = insert(:user, email: "creator@example.com")

      session
      # 1. Login
      |> visit("/auth/login")
      |> fill_in(text_field("Email"), with: user.email)
      |> fill_in(text_field("Password"), with: "testpass123")
      |> click(button("Sign in"))
      |> assert_has(text("Dashboard"))

      # 2. Navigate to create event
      |> click(link("Create Event"))
      |> assert_has(css("h1", text: "Create New Event"))

      # 3. Fill in event form
      |> fill_in(text_field("Title"), with: "Summer Concert")
      |> fill_in(text_field("Description"), with: "Outdoor music event")
      |> click(button("Create Event"))

      # 4. Verify event created
      |> assert_has(text("Event created successfully"))
      |> assert_has(css("h1", text: "Summer Concert"))

      # 5. Publish event
      |> click(button("Publish Event"))
      |> assert_has(text("Event published"))
      |> assert_has(css("[data-status='published']"))
    end

    test "validation errors are shown", %{session: session} do
      user = insert(:user)

      session
      |> login_as(user)
      |> visit("/events/new")
      |> click(button("Create Event"))

      # Assert validation errors shown
      |> assert_has(text("Title can't be blank"))
      |> assert_has(css(".error", text: "can't be blank"))
    end
  end
end
```

**Smoke Test Example:**
```elixir
defmodule EventasaurusWeb.E2E.CriticalPathsSmokeTest do
  use EventasaurusWeb.FeatureCase

  @moduletag :wallaby

  describe "critical paths smoke tests" do
    test "homepage loads", %{session: session} do
      session
      |> visit("/")
      |> assert_has(css("body"))
      |> assert_has(link("Discover Events"))
    end

    test "event detail page loads", %{session: session} do
      event = insert(:event, title: "Test Event")

      session
      |> visit("/#{event.slug}")
      |> assert_has(text("Test Event"))
    end
  end
end
```

**When NOT to write E2E tests:**
- Testing business logic (use unit)
- Testing every edge case (use unit)
- Testing implementation details (use unit)

---

### Discovery Tests (`test/discovery/`)

**When to write:**
- Testing event source scrapers
- Testing data transformers
- Testing geocoding
- Testing parsing utilities
- Testing discovery pipeline

**See [test/discovery/sources/README.md](./discovery/sources/README.md) for comprehensive discovery testing guide.**

---

## Test Naming Conventions

### File Naming

**Pattern:** `<module_name>_test.exs`

```
✅ Good:
- event_test.exs
- ticket_purchase_flow_test.exs
- bandsintown_transformer_test.exs

❌ Bad:
- test_event.exs
- events.exs
- EventTest.exs
```

### Module Naming

**Pattern:** Match the module being tested

```elixir
# Testing EventasaurusApp.Events.Event
defmodule EventasaurusApp.Events.EventTest do
  # ...
end

# Testing EventasaurusWeb.EventLive.Show
defmodule EventasaurusWeb.EventLive.ShowTest do
  # ...
end
```

### Test Description Naming

**Use clear, descriptive names that explain behavior:**

```elixir
✅ Good:
test "creates event with valid attributes"
test "returns error when title is blank"
test "sends confirmation email after ticket purchase"
test "redirects to login when not authenticated"

❌ Bad:
test "it works"
test "test create"
test "success case"
test "error"
```

**Describe blocks for grouping:**

```elixir
describe "create_event/1" do
  test "creates event with valid attributes"
  test "returns error with invalid attributes"
  test "validates start_time is in future"
end

describe "update_event/2" do
  test "updates event with valid attributes"
  test "returns error when event not found"
end
```

---

## Test Structure and Organization

### Test File Structure

```elixir
defmodule EventasaurusApp.Events.EventTest do
  use EventasaurusApp.DataCase, async: true

  # Aliases at top
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event

  # Imports after aliases
  import EventasaurusApp.Factory

  # Module attributes if needed
  @valid_attrs %{title: "Event", start_time: ~U[2024-06-01 18:00:00Z]}
  @invalid_attrs %{title: nil}

  # Setup blocks
  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  # Describe blocks for grouping
  describe "create_event/1" do
    test "creates event with valid attributes", %{user: user} do
      # Arrange
      attrs = Map.put(@valid_attrs, :creator_id, user.id)

      # Act
      assert {:ok, event} = Events.create_event(attrs)

      # Assert
      assert event.title == "Event"
      assert event.creator_id == user.id
    end
  end
end
```

### Arrange-Act-Assert Pattern

**Follow AAA pattern for clarity:**

```elixir
test "creates event successfully" do
  # Arrange - Set up test data
  user = insert(:user)
  attrs = %{title: "Event", creator_id: user.id}

  # Act - Perform the action
  assert {:ok, event} = Events.create_event(attrs)

  # Assert - Verify the results
  assert event.title == "Event"
  assert event.creator_id == user.id
end
```

### One Assertion Per Test (when reasonable)

```elixir
✅ Good - Focused tests:
test "creates event successfully" do
  assert {:ok, event} = Events.create_event(@valid_attrs)
  assert event.title == "Event"
end

test "sets creator_id from attributes" do
  user = insert(:user)
  {:ok, event} = Events.create_event(Map.put(@valid_attrs, :creator_id, user.id))
  assert event.creator_id == user.id
end

⚠️ Acceptable - Related assertions:
test "creates event with all attributes" do
  user = insert(:user)
  attrs = %{title: "Event", description: "Desc", creator_id: user.id}

  assert {:ok, event} = Events.create_event(attrs)
  assert event.title == "Event"
  assert event.description == "Desc"
  assert event.creator_id == user.id
end

❌ Bad - Testing multiple behaviors:
test "event operations work" do
  # Creates
  assert {:ok, event} = Events.create_event(@valid_attrs)

  # Updates
  assert {:ok, updated} = Events.update_event(event, %{title: "New"})

  # Deletes
  assert {:ok, _} = Events.delete_event(event)
end
```

---

## Factory and Fixture Usage

### When to Use Factories

**Use factories (ExMachina) for:**
- Creating test database records
- Generating realistic test data
- Building associations
- Customizing specific attributes

```elixir
# Basic usage
user = insert(:user)
event = insert(:event, creator: user)

# Custom attributes
event = insert(:event, title: "Custom Title", is_ticketed: true)

# Building without inserting
attrs = build(:event) |> Map.from_struct()

# Build list
users = insert_list(5, :user)
```

### When to Use Fixtures

**Use fixtures for:**
- Static test data (HTML, JSON, images)
- Large response payloads
- Scraper test HTML
- Binary data (images, PDFs)

```elixir
# Read HTML fixture
defp read_fixture(filename) do
  Path.join([__DIR__, "fixtures", filename])
  |> File.read!()
end

test "parses event from HTML" do
  html = read_fixture("bandsintown_event.html")
  assert {:ok, event} = Parser.parse(html)
end
```

### Factory Best Practices

```elixir
✅ Good:
# Use factories for database records
user = insert(:user)
event = insert(:event, creator: user)

# Use build for attributes
attrs = build(:event_attrs)

# Use insert_list for multiple records
users = insert_list(5, :user)

❌ Bad:
# Don't hardcode attributes
event = insert(:event, %{
  title: "Event",
  description: "Desc",
  start_time: DateTime.utc_now()
})

# Don't create unnecessary records
users = Enum.map(1..100, fn i ->
  insert(:user, email: "user#{i}@example.com")
end)
```

---

## Tagging Strategy

### Test Tags

**Standard Tags:**

```elixir
# Wallaby E2E tests (REQUIRED for browser tests)
@moduletag :wallaby

# External API tests (excluded by default)
@moduletag :external_api

# Integration tests (optional, for clarity)
@moduletag :integration

# Stress/performance tests
@moduletag :stress

# Slow tests that can be skipped
@tag :slow

# Skip in CI
@moduletag :skip_ci
```

### Tag Usage Examples

```elixir
# E2E test - Always tag with :wallaby
defmodule EventasaurusWeb.E2E.UserJourneyTest do
  use EventasaurusWeb.FeatureCase

  @moduletag :wallaby

  test "user can browse events", %{session: session} do
    # ...
  end
end

# External API test - Tag to exclude by default
defmodule EventasaurusDiscovery.BandsintownAPITest do
  use EventasaurusApp.DataCase

  @moduletag :external_api

  test "fetches events from API" do
    # Makes real API call
  end
end

# Individual test tag
test "slow operation", %{session: session} do
  @tag :slow
  # ...
end
```

### Running Tagged Tests

```bash
# Run only Wallaby tests
mix test --only wallaby

# Exclude external API tests (default)
mix test --exclude external_api

# Run external API tests
mix test --only external_api

# Exclude multiple tags
mix test --exclude wallaby --exclude external_api
```

---

## Performance Best Practices

### Use Async Tests

```elixir
✅ Good - Async when possible:
defmodule EventasaurusApp.Events.EventTest do
  use EventasaurusApp.DataCase, async: true
  # Tests run in parallel
end

❌ Bad - Unnecessary sync:
defmodule EventasaurusApp.Events.EventTest do
  use EventasaurusApp.DataCase
  # Runs serially, slower
end
```

**When to use `async: false`:**
- Tests that use shared state (ETS, Agent, etc.)
- Tests that mock modules globally
- Wallaby/E2E tests
- Tests with timing dependencies

### Minimize Database Operations

```elixir
✅ Good - Single setup:
setup do
  user = insert(:user)
  event = insert(:event, creator: user)
  {:ok, user: user, event: event}
end

test "uses setup data", %{event: event} do
  assert event.title
end

❌ Bad - Repeated setup:
test "test 1" do
  user = insert(:user)
  event = insert(:event, creator: user)
  # ...
end

test "test 2" do
  user = insert(:user)  # Duplicate!
  event = insert(:event, creator: user)
  # ...
end
```

### Use `insert_all` for Bulk Data

```elixir
✅ Good - Bulk insert:
# Insert 100 records efficiently
Repo.insert_all(User, Enum.map(1..100, fn i ->
  %{email: "user#{i}@example.com", inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
end))

❌ Bad - Individual inserts:
Enum.each(1..100, fn i ->
  insert(:user, email: "user#{i}@example.com")
end)
```

### Avoid Unnecessary Assertions

```elixir
✅ Good - Essential assertions:
test "creates event" do
  assert {:ok, event} = Events.create_event(@valid_attrs)
  assert event.title == "Event"
end

❌ Bad - Over-testing:
test "creates event" do
  assert {:ok, event} = Events.create_event(@valid_attrs)
  assert event.title == "Event"
  assert event.inserted_at
  assert event.updated_at
  assert event.id
  assert is_binary(event.slug)
  # Testing too many implementation details
end
```

---

## Common Patterns

### Testing Changesets

```elixir
test "validates required fields" do
  changeset = Event.changeset(%Event{}, %{})

  refute changeset.valid?
  assert "can't be blank" in errors_on(changeset).title
  assert "can't be blank" in errors_on(changeset).start_time
end

test "validates start_time is in future" do
  past_time = DateTime.add(DateTime.utc_now(), -1, :day)
  changeset = Event.changeset(%Event{}, %{start_time: past_time})

  refute changeset.valid?
  assert "must be in the future" in errors_on(changeset).start_time
end
```

### Testing Associations

```elixir
test "loads event creator" do
  user = insert(:user, name: "John")
  event = insert(:event, creator: user)

  event = Events.get_event!(event.id) |> Repo.preload(:creator)

  assert event.creator.name == "John"
end

test "creates event with participants" do
  event = insert(:event)
  users = insert_list(3, :user)

  Enum.each(users, fn user ->
    Events.add_participant(event, user)
  end)

  participants = Events.list_participants(event)
  assert length(participants) == 3
end
```

### Testing Emails

```elixir
test "sends confirmation email" do
  user = insert(:user, email: "test@example.com")
  event = insert(:event)

  Events.send_confirmation(user, event)

  assert_email_sent(
    to: "test@example.com",
    subject: ~r/Event Confirmation/
  )
end
```

### Testing Background Jobs

```elixir
test "enqueues sync job" do
  assert {:ok, _job} = Scrapers.enqueue_sync("bandsintown")

  assert_enqueued(worker: BandsintownSyncWorker)
end
```

### Testing LiveView Events

```elixir
test "handles form submission", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/events/new")

  view
  |> form("#event-form", event: @valid_attrs)
  |> render_submit()

  assert_redirected(view, ~p"/events/#{event.slug}")
end

test "shows validation errors on change", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/events/new")

  html = view
  |> form("#event-form", event: %{title: ""})
  |> render_change()

  assert html =~ "can&#39;t be blank"
end
```

---

## Anti-Patterns to Avoid

### Don't Test Implementation Details

```elixir
❌ Bad - Testing internals:
test "calls private function" do
  assert Events.some_private_function() == :ok
end

✅ Good - Testing behavior:
test "creates event successfully" do
  assert {:ok, event} = Events.create_event(@valid_attrs)
end
```

### Don't Use Sleep

```elixir
❌ Bad - Using sleep:
test "async operation completes" do
  start_async_operation()
  :timer.sleep(1000)
  assert operation_complete?()
end

✅ Good - Polling with timeout:
test "async operation completes" do
  start_async_operation()

  assert eventually(fn ->
    operation_complete?()
  end)
end
```

### Don't Create Brittle Selectors

```elixir
❌ Bad - Fragile CSS selectors:
assert has_element?(view, ".flex.items-center.justify-between.p-4.bg-white")

✅ Good - Semantic attributes:
assert has_element?(view, "[data-role='event-card']")
assert has_element?(view, "h1", "Event Title")
```

### Don't Mock What You Don't Own

```elixir
❌ Bad - Mocking Ecto:
test "creates event" do
  expect(Repo, :insert, fn _ -> {:ok, %Event{}} end)
  Events.create_event(@valid_attrs)
end

✅ Good - Test with real database:
test "creates event" do
  assert {:ok, event} = Events.create_event(@valid_attrs)
  assert Repo.get(Event, event.id)
end
```

### Don't Share State Between Tests

```elixir
❌ Bad - Shared module attribute modified:
@shared_data %{}

test "modifies shared data" do
  @shared_data = Map.put(@shared_data, :key, :value)
end

✅ Good - Independent test data:
test "uses independent data" do
  data = %{key: :value}
  assert data.key == :value
end
```

---

## Test Data Management

### Keep Test Data Minimal

```elixir
✅ Good - Only necessary data:
test "calculates total price" do
  order = %{items: [%{price: 10}, %{price: 20}]}
  assert Order.calculate_total(order) == 30
end

❌ Bad - Excessive data:
test "calculates total price" do
  user = insert(:user, name: "John", email: "john@example.com")
  event = insert(:event, title: "Event", creator: user)
  order = insert(:order, user: user, event: event, items: [...])
  assert Order.calculate_total(order) == 30
end
```

### Use Descriptive Factory Traits

```elixir
# In factory.ex
def event_factory do
  %Event{
    title: sequence(:title, &"Event #{&1}"),
    creator: build(:user)
  }
end

def ticketed_event_factory do
  struct!(
    event_factory(),
    %{
      is_ticketed: true,
      ticket_price: Decimal.new("25.00"),
      ticket_capacity: 100
    }
  )
end

# In tests
test "purchases ticket for ticketed event" do
  event = insert(:ticketed_event)
  # ...
end
```

---

## Async vs Sync Tests

### Use Async by Default

```elixir
✅ Default - Use async:
defmodule EventasaurusApp.Events.EventTest do
  use EventasaurusApp.DataCase, async: true
  # Runs in parallel, faster
end
```

### Use Sync When Necessary

```elixir
# Sync for Wallaby tests
defmodule EventasaurusWeb.E2E.UserJourneyTest do
  use EventasaurusWeb.FeatureCase
  # async: false by default in FeatureCase

  @moduletag :wallaby
end

# Sync for shared state
defmodule EventasaurusApp.CacheTest do
  use EventasaurusApp.DataCase  # async: false

  # Tests use shared ETS table
end

# Sync for global mocks
defmodule EventasaurusApp.ExternalAPITest do
  use EventasaurusApp.DataCase  # async: false

  # Mocks external HTTP client globally
end
```

---

## Summary Checklist

When writing a test, ask yourself:

- [ ] Is this test in the right directory?
- [ ] Does the test name clearly describe what it tests?
- [ ] Is the test using the appropriate test case?
- [ ] Are tags added if needed (`:wallaby`, `:external_api`, etc.)?
- [ ] Is the test using `async: true` if possible?
- [ ] Am I using factories for test data?
- [ ] Is the test focused on one behavior?
- [ ] Are assertions clear and specific?
- [ ] Will this test be fast (<100ms for unit)?
- [ ] Is the test independent (no shared state)?
- [ ] Will this test be reliable (not flaky)?

**Remember:** Good tests are fast, focused, independent, and reliable. They test behavior, not implementation.

---

_For more details, see [README.md](./README.md) and [performance_optimization_guide.md](./performance_optimization_guide.md)._
