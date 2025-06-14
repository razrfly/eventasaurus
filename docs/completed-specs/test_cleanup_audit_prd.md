# Test Suite Cleanup & Refactoring PRD
## Eventasaurus Test Quality Improvement Initiative v2.0

### Executive Summary
The Eventasaurus test suite has grown to 496 tests across 37 files, with significant technical debt and organizational challenges. This PRD outlines a comprehensive strategy to reduce the test suite by ~50%, improve execution speed by 70%, and establish sustainable testing practices.

### Current State Analysis

#### Test Distribution
- **Total**: 496 tests across 37 files
- **Heavy Files**: 
  - `new_test.exs` (37 tests)
  - `events_test.exs` (37 tests)
  - `public_event_live_test.exs` (32 tests)
  - Multiple files with 20+ tests indicating potential duplication

#### Problem Areas Identified

1. **Chrome/Chromedriver Issues**
   - All Wallaby feature tests are conditionally skipped
   - Version mismatch prevents browser-based testing
   - ~30 tests affected across feature test files

2. **Test Duplication Patterns**
   - Registration flow tested in 8+ different files
   - Authentication helpers called 50+ times
   - Similar event creation scenarios repeated across contexts
   - Social card functionality tested in 3 separate files

3. **Organizational Issues**
   - Mixed unit/integration tests in same files
   - No clear separation between fast/slow tests
   - Inconsistent test naming conventions
   - Missing test categories/tags

4. **Technical Debt**
   - SVG converter tests depend on system binaries
   - External service dependencies not properly mocked
   - Database-heavy tests without proper isolation
   - No parallel execution strategy

### Proposed Test Architecture

```
test/
├── unit/                          # Target: < 10ms per test
│   ├── schemas/                   # Ecto changeset validations
│   │   ├── event_test.exs
│   │   ├── user_test.exs
│   │   └── venue_test.exs
│   ├── services/                  # Pure business logic
│   │   ├── date_poll_test.exs
│   │   ├── notification_test.exs
│   │   └── timezone_test.exs
│   └── helpers/                   # Utility functions
│       ├── sanitizer_test.exs
│       └── hash_generator_test.exs
│
├── integration/                   # Target: < 100ms per test
│   ├── contexts/                  # Context integration
│   │   ├── events_context_test.exs
│   │   └── accounts_context_test.exs
│   ├── live_components/           # LiveComponent tests
│   │   ├── calendar_component_test.exs
│   │   └── date_picker_test.exs
│   └── controllers/               # Controller integration
│       ├── event_controller_test.exs
│       └── auth_controller_test.exs
│
├── features/                      # Target: < 500ms per test
│   ├── journeys/                  # End-to-end flows
│   │   ├── event_creation_test.exs
│   │   ├── registration_flow_test.exs
│   │   └── public_event_discovery_test.exs
│   └── smoke/                     # Critical path tests
│       └── core_functionality_test.exs
│
└── support/                       # Test infrastructure
    ├── factories/
    ├── fixtures/
    ├── helpers/
    └── mocks/
```

### Specific Refactoring Actions

#### 1. Test Consolidation Plan

**Registration Flow Tests** (Reduce from 50+ to 5 tests)
- Keep: 1 unit test for registration logic
- Keep: 1 integration test for registration context
- Keep: 1 feature test for full registration flow
- Remove: Duplicate registration checks in multiple files
- Remove: Redundant authentication helper tests

**Event Management Tests** (Reduce from 74 to 25 tests)
- Merge: `new_test.exs` and `events_test.exs` overlap
- Keep: Core CRUD operations (5 tests)
- Keep: State transitions (3 tests)
- Keep: Date polling functionality (5 tests)
- Keep: Permission checks (3 tests)
- Remove: Duplicate validation tests
- Remove: UI-specific tests better covered by components

**Social Card Tests** (Reduce from 50+ to 10 tests)
- Merge: 3 separate test files into 1
- Mock: System dependencies (rsvg-convert)
- Keep: Core generation logic
- Keep: Caching behavior
- Remove: Duplicate sanitization tests

#### 2. Performance Optimization Strategy

**Database Optimization**
```elixir
# Before: Each test creates full object graph
setup do
  user = insert(:user)
  venue = insert(:venue)
  event = insert(:event, organizer: user, venue: venue)
  # ... more setup
end

# After: Shared fixtures with minimal data
setup :register_and_log_in_user
setup :create_minimal_event
```

**Async Execution Plan**
```elixir
# Tag all unit tests for parallel execution
use ExUnit.Case, async: true

# Group related tests to prevent conflicts
@moduletag :event_management
```

**Mock External Services**
```elixir
# Before: Actual HTTP calls or system binaries
test "generates social card" do
  {:ok, png} = SvgConverter.convert_to_png(svg)
end

# After: Mocked responses
test "generates social card" do
  expect(MockSvgConverter, :convert_to_png, fn _ -> 
    {:ok, <<PNG_MAGIC_BYTES>>} 
  end)
end
```

#### 3. Test Quality Standards

**Naming Convention**
```elixir
# Pattern: test "WHEN <condition> THEN <outcome>"
test "when user is not authenticated then redirects to login"
test "when event is full then shows waitlist option"
```

**Test Structure**
```elixir
describe "Context.function_name/arity" do
  setup [:common_setup]
  
  test "happy path scenario" do
    # Arrange
    # Act  
    # Assert
  end
  
  test "error scenario" do
    # Arrange
    # Act
    # Assert
  end
end
```

**Assertion Guidelines**
- One logical assertion per test
- Use pattern matching over multiple assertions
- Prefer `assert` over `refute` when possible

### Implementation Phases

#### Phase 1: Infrastructure Setup (Week 1)
- [ ] Fix Chrome/chromedriver version mismatch
- [ ] Set up proper test categorization with tags
- [ ] Create shared test helpers and fixtures
- [ ] Implement mock modules for external services
- [ ] Configure parallel test execution

#### Phase 2: Unit Test Extraction (Week 2)
- [ ] Extract pure unit tests from mixed files
- [ ] Remove database dependencies from unit tests
- [ ] Consolidate duplicate schema validations
- [ ] Target: 200 unit tests @ <10ms each

#### Phase 3: Integration Test Refactoring (Week 3)
- [ ] Consolidate overlapping integration tests
- [ ] Optimize database setup/teardown
- [ ] Group related tests for better isolation
- [ ] Target: 50 integration tests @ <100ms each

#### Phase 4: Feature Test Optimization (Week 4)
- [ ] Fix Wallaby configuration issues
- [ ] Create reusable page objects
- [ ] Focus on critical user journeys only
- [ ] Target: 20 feature tests @ <500ms each

#### Phase 5: Cleanup & Documentation (Week 5)
- [ ] Remove identified redundant tests
- [ ] Update test documentation
- [ ] Create testing guidelines
- [ ] Set up CI performance monitoring

### Success Metrics

**Quantitative Goals**
- Test count: 496 → 250 tests (50% reduction)
- Execution time: <30s unit, <2m integration, <5m features
- Failure rate: 0% (from current conditional skips)
- Coverage: Maintain >85% with fewer tests

**Qualitative Goals**
- Clear test organization and discoverability
- Fast feedback loops for developers
- Reliable CI/CD pipeline
- Easy to add new tests following patterns

### Risk Mitigation

1. **Coverage Gaps**
   - Run coverage analysis before removing tests
   - Maintain critical path test scenarios
   - Document removed test rationale

2. **Breaking Changes**
   - Implement changes incrementally
   - Keep original tests during transition
   - Validate against production scenarios

3. **Team Adoption**
   - Provide clear migration guides
   - Conduct team training sessions
   - Create test writing templates

### Technical Requirements

**Testing Stack**
- ExUnit with async: true optimization
- Wallaby with proper Chrome setup
- Mox for external service mocking
- ExMachina for factory management

**CI/CD Integration**
```yaml
test:
  parallel:
    matrix:
      - TEST_SUITE: unit
      - TEST_SUITE: integration  
      - TEST_SUITE: features
  script:
    - mix test --only $TEST_SUITE
```

### Maintenance Strategy

**Weekly Test Health Checks**
- Monitor test execution times
- Review new test additions
- Identify flaky tests
- Update test documentation

**Monthly Test Audits**
- Analyze test coverage gaps
- Review test duplication
- Optimize slow tests
- Update test categories

### Conclusion

This refactoring initiative will transform the Eventasaurus test suite from a maintenance burden into a development accelerator. By reducing test count while maintaining coverage, optimizing execution speed, and establishing clear patterns, we'll create a sustainable testing culture that supports rapid feature development.