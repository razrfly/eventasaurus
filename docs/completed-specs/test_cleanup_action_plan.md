# Test Cleanup Action Plan - Immediate Steps

## Quick Wins (Week 1)

### 1. Fix Chrome/Chromedriver Issues
```bash
# Update test_helper.exs to handle version mismatch gracefully
# Current: Tests are skipped with manual IO.puts
# Solution: Add proper tags and configuration

# In test_helper.exs
if System.get_env("CI") || ChromedriverHelper.versions_match?() do
  ExUnit.configure(exclude: [:skip_browser])
else
  ExUnit.configure(exclude: [:browser])
end
```

### 2. Remove Duplicate Registration Tests
**Current**: Registration tested in 8+ files
**Action**: Consolidate to 3 core tests

```elixir
# KEEP: test/eventasaurus_web/auth_helpers_test.exs
# - Core authentication helper functionality

# KEEP: test/eventasaurus_app/events_test.exs
# - Business logic for event registration

# KEEP: test/eventasaurus_web/features/public_user_journey_test.exs  
# - End-to-end registration flow

# REMOVE: Registration tests from:
# - liveview_interaction_test.exs (11 instances)
# - user_feedback_test.exs (8 instances)
# - form_validation_test.exs (6 instances)
```

### 3. Consolidate Social Card Tests
**Current**: 3 separate files with overlapping tests
**Action**: Merge into single comprehensive test

```elixir
# MERGE INTO: test/unit/services/social_card_service_test.exs
# FROM:
# - test/eventasaurus_web/views/social_card_view_test.exs (25 tests)
# - test/eventasaurus/services/social_card_hash_test.exs (12 tests)
# - test/eventasaurus/social_cards/hash_generator_test.exs (20 tests)

# Mock system dependencies:
defmodule MockSvgConverter do
  def convert_to_png(_svg), do: {:ok, <<137, 80, 78, 71, 13, 10, 26, 10>>}
end
```

## Test Organization Examples

### Before: Mixed Concerns
```elixir
# test/eventasaurus_web/live/event_live/new_test.exs
defmodule EventasaurusWeb.EventLive.NewTest do
  # Contains:
  # - UI rendering tests
  # - Form validation tests  
  # - Business logic tests
  # - Database integration tests
  # Total: 37 tests in one file!
end
```

### After: Separated by Type
```elixir
# test/unit/schemas/event_test.exs
defmodule Eventasaurus.Schemas.EventTest do
  use ExUnit.Case, async: true
  # Only changeset validations, no DB
end

# test/integration/contexts/events_test.exs  
defmodule Eventasaurus.EventsTest do
  use Eventasaurus.DataCase
  # Context functions with DB
end

# test/features/event_creation_test.exs
defmodule Eventasaurus.Features.EventCreationTest do
  use EventasaurusWeb.FeatureCase
  @tag :browser
  # Full user journey
end
```

## Specific Files to Refactor

### High Priority (Most Duplication)
1. **events_test.exs** (37 tests)
   - Extract: 15 pure validation tests → unit/schemas/
   - Keep: 10 context integration tests
   - Remove: 12 duplicate UI tests

2. **new_test.exs** (37 tests)  
   - Extract: 20 LiveView component tests → integration/live_components/
   - Keep: 10 form interaction tests
   - Remove: 7 duplicate validation tests

3. **public_event_live_test.exs** (32 tests)
   - Extract: 15 view rendering tests → unit tests with mocks
   - Keep: 10 core public event scenarios
   - Remove: 7 duplicate permission tests

### Test Helpers to Create

```elixir
# test/support/test_helpers/event_helpers.ex
defmodule EventasaurusWeb.EventHelpers do
  def create_minimal_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(Map.merge(%{
      title: "Test Event",
      start_at: DateTime.utc_now(),
      timezone: "UTC"
    }, attrs))
    |> Repo.insert!()
  end
  
  def with_polling_dates(event, dates) do
    # Helper to set up date polling
  end
end

# test/support/test_helpers/auth_helpers.ex  
defmodule EventasaurusWeb.AuthHelpers do
  def login_as(conn, user) do
    # Simplified auth helper
  end
end
```

## Migration Checklist

### For Each Test File:
- [ ] Count total tests
- [ ] Identify test types (unit/integration/feature)
- [ ] Check for duplicate scenarios
- [ ] Extract pure functions to unit tests
- [ ] Add proper tags (@tag :unit, @tag :integration)
- [ ] Enable async where possible
- [ ] Mock external dependencies
- [ ] Document why tests were removed

### Example Migration:

```elixir
# BEFORE: test/eventasaurus_app/events_test.exs
test "one_click_register/2 creates registration for unregistered user" do
  user = insert(:user)
  event = insert(:event)
  
  assert {:ok, participant} = Events.one_click_register(event, user)
  assert participant.user_id == user.id
  assert participant.event_id == event.id
  assert participant.status == :pending
  assert participant.source == "one_click_registration"
end

# AFTER: test/unit/contexts/events_test.exs
describe "one_click_register/2" do
  @tag :unit
  
  test "creates registration for new user" do
    # Use mocks instead of database
    expect(Repo, :get_by, fn _, _ -> nil end)
    expect(Repo, :insert, fn changeset -> 
      {:ok, struct(EventUser, changeset.changes)}
    end)
    
    assert {:ok, _} = Events.one_click_register(%Event{id: 1}, %User{id: 1})
  end
end
```

## Metrics to Track

```elixir
# Create test/test_metrics.exs
defmodule TestMetrics do
  def generate_report do
    %{
      total_tests: count_tests(),
      by_type: %{
        unit: count_by_tag(:unit),
        integration: count_by_tag(:integration),
        feature: count_by_tag(:feature)
      },
      execution_time: measure_execution_time(),
      slowest_tests: find_slowest_tests(10)
    }
  end
end
```

## Next Steps

1. **Today**: Fix Chrome/chromedriver setup
2. **Tomorrow**: Tag all existing tests
3. **This Week**: Extract first 100 unit tests
4. **Next Week**: Consolidate duplicate scenarios
5. **Week 3**: Optimize database fixtures
6. **Week 4**: Implement parallel execution
7. **Week 5**: Documentation and training