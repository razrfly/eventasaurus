# Archived Tests Guide

## Purpose

This guide explains the archival policy for tests that are no longer actively maintained or run, but may have historical value or could be useful for future reference.

## Overview

**Archiving vs Deleting:**
- **Archive** - Test is preserved but not run, documented reason for archival
- **Delete** - Test is permanently removed, no historical value

**Archival Philosophy:**
- Tests are expensive to write and maintain
- Historical context is valuable
- Some tests become temporarily irrelevant but may be useful later
- Documentation prevents duplicate work
- Archival is a middle ground between active and deleted

## When to Archive Tests

### Archive These Tests ✅

1. **Feature Removed from Application**
   - Feature was removed but may return
   - Test documents how feature worked
   - Useful reference for similar future features

2. **Temporarily Disabled Functionality**
   - Feature is paused but planned to return
   - Third-party integration is temporarily unavailable
   - Waiting on external dependencies

3. **Platform/Version-Specific Tests**
   - Tests for old platform versions we may support again
   - Browser-specific tests for browsers we dropped
   - Device-specific tests for devices we don't support currently

4. **Performance Baseline Tests**
   - Historical performance benchmarks
   - Comparison tests for old implementations
   - Load tests for deprecated endpoints

5. **Migration Tests**
   - One-time data migration tests
   - Schema migration verification tests
   - Import/export tests for completed migrations

6. **Experimental Feature Tests**
   - A/B test verification tests
   - Feature flag tests for disabled features
   - Proof-of-concept implementation tests

### Delete These Tests ❌

1. **Duplicate Tests**
   - Test is redundant with existing coverage
   - Same functionality tested elsewhere
   - No unique test cases

2. **Obsolete Tests**
   - Tests for code that will never return
   - Tests for permanently deprecated features
   - Tests with no historical value

3. **Broken/Incomplete Tests**
   - Test was never completed
   - Test never worked correctly
   - Test has no clear purpose

4. **Trivial Tests**
   - Test provides no meaningful coverage
   - Test is too simple to be useful
   - Test duplicates framework behavior

## Archival Process

### Step 1: Identify Test for Archival

**Questions to Ask:**
- Why is this test no longer needed?
- Could this test be useful in the future?
- Does this test document important behavior?
- Is there unique knowledge in this test?

**Decision Tree:**
```
Is the test still passing?
├─ No → Is it testing removed functionality?
│        ├─ Yes → Archive with detailed documentation
│        └─ No → Fix or delete
└─ Yes → Why archive?
         ├─ Feature temporarily disabled → Archive
         ├─ No longer relevant → Review for deletion
         └─ Performance/historical → Archive
```

### Step 2: Document the Archival

Create an archival metadata file alongside the test:

```elixir
# test/archived/feature_name_test.exs.archived
%{
  original_path: "test/eventasaurus_web/features/feature_name_test.exs",
  archived_date: "2024-01-15",
  archived_by: "developer@example.com",
  reason: "Feature temporarily disabled pending redesign",
  original_coverage: ["EventController", "FeatureView"],
  test_count: 12,
  last_passing: "2024-01-10",
  return_conditions: [
    "Feature redesign completed",
    "New UX approved by stakeholders"
  ],
  related_issues: ["#123", "#456"],
  notes: """
  This test suite covers the original implementation of the feature.
  When feature returns, review these tests against new implementation.
  Some test cases may still be relevant.
  """
}
```

### Step 3: Move to Archive

```bash
# Move test file
mv test/path/to/test_file_test.exs test/archived/

# Create metadata file
touch test/archived/test_file_test.exs.archived

# Edit metadata file with archival information
```

### Step 4: Update Test Inventory

Add entry to `test/archived/INVENTORY.md`:

```markdown
## Feature Name Test (2024-01-15)

- **Original Path:** test/eventasaurus_web/features/feature_name_test.exs
- **Reason:** Feature temporarily disabled pending redesign
- **Test Count:** 12 tests
- **Return Conditions:** Feature redesign completed, new UX approved
- **Related Issues:** #123, #456
- **Review Date:** 2024-07-15 (6 months)
```

### Step 5: Remove from CI

Ensure archived tests don't run in CI:
- Tests in `test/archived/` are automatically excluded
- Remove any explicit references in CI configuration
- Update coverage reports to exclude archived tests

## Archive Directory Structure

```
test/archived/
├── README.md                           # This file
├── INVENTORY.md                        # Catalog of all archived tests
├── feature_tests/                      # Archived feature tests
│   ├── old_feature_test.exs
│   └── old_feature_test.exs.archived
├── integration_tests/                  # Archived integration tests
│   ├── legacy_integration_test.exs
│   └── legacy_integration_test.exs.archived
├── performance_tests/                  # Archived performance tests
│   ├── old_benchmark_test.exs
│   └── old_benchmark_test.exs.archived
└── migration_tests/                    # Archived migration tests
    ├── data_migration_test.exs
    └── data_migration_test.exs.archived
```

## Archival Metadata Format

### Required Fields

```elixir
%{
  # When and by whom
  archived_date: "2024-01-15",           # ISO 8601 date
  archived_by: "developer@example.com",  # Email or username

  # What was archived
  original_path: "test/...",             # Original test location
  test_count: 12,                        # Number of test cases

  # Why archived
  reason: "...",                         # Brief explanation

  # How to restore
  return_conditions: ["..."],            # What needs to happen
}
```

### Optional Fields

```elixir
%{
  # Additional context
  original_coverage: ["Module1", "Module2"],  # Modules tested
  last_passing: "2024-01-10",                 # Last successful run
  related_issues: ["#123"],                   # GitHub issues
  related_prs: ["#456"],                      # Pull requests
  notes: "...",                               # Detailed notes

  # Review scheduling
  review_date: "2024-07-15",                  # Next review date
  retention_period: "1 year",                 # When to delete

  # Historical data
  original_runtime: "45s",                    # Test suite runtime
  flakiness_rate: "5%",                       # Historical flakiness
  tags: ["wallaby", "integration"],          # Original tags
}
```

## Review Process

### Quarterly Review (Every 3 Months)

1. **Review archived tests approaching retention period**
2. **Evaluate return conditions**
   - Have conditions been met?
   - Are they still relevant?
   - Should test be restored or deleted?

3. **Update metadata**
   - Extend retention if still valuable
   - Update return conditions if changed
   - Add notes on review decisions

### Annual Deep Review (Every 12 Months)

1. **Review all archived tests**
2. **Categorize by value**
   - High value: Extend retention
   - Medium value: Update review date
   - Low value: Delete

3. **Update archival policy**
   - Are criteria still appropriate?
   - Is retention period correct?
   - Should organization change?

### Review Checklist

```markdown
## Test: [Test Name] (Archived: [Date])

### Review Date: [Current Date]
### Reviewer: [Name]

- [ ] Read original archival reason
- [ ] Check if feature/functionality has returned
- [ ] Review return conditions - still relevant?
- [ ] Evaluate historical value - still useful?
- [ ] Check related issues/PRs - any updates?
- [ ] Determine retention period - extend or delete?

### Decision:
- [ ] Keep archived - extend retention to [date]
- [ ] Restore to active tests
- [ ] Delete - no longer valuable

### Notes:
[Reasoning for decision]
```

## Restoring Archived Tests

### When to Restore

1. **Feature Returns**
   - Feature is being re-implemented
   - Tests may be partially useful
   - Historical context is valuable

2. **Return Conditions Met**
   - All conditions in metadata are satisfied
   - Tests are relevant to current implementation
   - Tests still provide value

3. **Reference Needed**
   - Similar feature being implemented
   - Need examples of test patterns
   - Historical behavior documentation needed

### Restoration Process

#### Step 1: Review Test Content

```bash
# Read the archived test
cat test/archived/feature_tests/old_feature_test.exs

# Read metadata
cat test/archived/feature_tests/old_feature_test.exs.archived
```

#### Step 2: Evaluate Relevance

**Questions:**
- Does test still apply to current implementation?
- Are test patterns still valid?
- Does test coverage overlap with existing tests?
- Are assertions still relevant?

#### Step 3: Update Test if Needed

```elixir
# Before restoration, update:
# - Module names if changed
# - Factory usage if changed
# - Assertions if behavior changed
# - Tags if test type changed
```

#### Step 4: Move Back to Active Tests

```bash
# Move to appropriate directory
mv test/archived/feature_tests/old_feature_test.exs \
   test/unit/features/feature_test.exs

# Update test file as needed
# Run test to verify it works
mix test test/unit/features/feature_test.exs
```

#### Step 5: Update Inventory

Remove from `test/archived/INVENTORY.md` and add note:

```markdown
## Test Restorations

### Feature Name Test (Restored 2024-06-15)
- **Archived:** 2024-01-15
- **Restored:** 2024-06-15
- **New Location:** test/unit/features/feature_test.exs
- **Reason:** Feature redesign completed
- **Changes Made:** Updated factory usage, modernized assertions
```

## Retention Periods

### Default Retention by Category

| Category | Retention Period | Rationale |
|----------|-----------------|-----------|
| Feature Tests | 1 year | Features may return within a year |
| Integration Tests | 6 months | Integration patterns evolve quickly |
| Performance Tests | 2 years | Historical benchmarks valuable long-term |
| Migration Tests | 3 months | One-time migrations rarely relevant after |
| E2E Tests | 1 year | User flows may return in different form |
| Experimental Tests | 6 months | Experiments either ship or are abandoned |

### Extending Retention

**Criteria for Extension:**
- Test has unique historical value
- Feature return is planned but delayed
- Test documents complex behavior
- Reference value for similar features

**Extension Process:**
```elixir
# Update metadata file
%{
  # ... existing fields
  review_date: "2025-01-15",  # Extended from 2024-07-15
  retention_period: "2 years", # Extended from 1 year
  extension_reason: "Feature return planned for Q4 2024"
}
```

## Common Archival Scenarios

### Scenario 1: Third-Party Integration Removed

**Example:** Bandsintown integration disabled

```elixir
# test/archived/integration_tests/bandsintown_integration_test.exs.archived
%{
  archived_date: "2024-01-15",
  archived_by: "dev@example.com",
  original_path: "test/integration/discovery/bandsintown_integration_test.exs",
  reason: "Bandsintown integration temporarily disabled due to API changes",
  test_count: 8,
  return_conditions: [
    "Bandsintown API v3 migration completed",
    "New API key obtained",
    "Rate limiting implemented"
  ],
  related_issues: ["#789"],
  review_date: "2024-07-15",
  retention_period: "1 year",
  notes: """
  Tests cover error handling, rate limiting, and data transformation.
  When restoring, review new API documentation and update:
  - Endpoint URLs
  - Response format parsing
  - Error code handling
  """
}
```

### Scenario 2: Feature Flag Disabled

**Example:** New event creation flow disabled

```elixir
# test/archived/feature_tests/new_event_flow_test.exs.archived
%{
  archived_date: "2024-02-01",
  archived_by: "dev@example.com",
  original_path: "test/eventasaurus_web/features/new_event_flow_test.exs",
  reason: "New event creation flow behind feature flag, disabled in production",
  test_count: 15,
  return_conditions: [
    "A/B test results show improvement",
    "User feedback is positive",
    "Feature flag enabled for 100% of users"
  ],
  related_issues: ["#890"],
  tags: ["wallaby", "feature_flag"],
  review_date: "2024-05-01",
  retention_period: "6 months",
  notes: """
  Tests cover full event creation flow with new UX.
  Includes:
  - Multi-step form navigation
  - Validation at each step
  - Draft saving functionality
  - Preview before publish

  If feature is abandoned, delete these tests.
  If feature ships, move back to active tests.
  """
}
```

### Scenario 3: Data Migration Complete

**Example:** Event schema migration

```elixir
# test/archived/migration_tests/event_schema_migration_test.exs.archived
%{
  archived_date: "2024-03-01",
  archived_by: "dev@example.com",
  original_path: "test/eventasaurus_app/migrations/event_schema_migration_test.exs",
  reason: "One-time migration completed and verified in production",
  test_count: 6,
  related_prs: ["#901"],
  retention_period: "3 months",
  review_date: "2024-06-01",
  notes: """
  Migration completed 2024-02-28.
  Verified all events migrated successfully.

  Test documents:
  - Old schema structure
  - New schema structure
  - Data transformation logic
  - Rollback procedure

  Delete after 3 months unless needed for reference.
  """
}
```

### Scenario 4: Performance Baseline

**Example:** Query optimization baseline

```elixir
# test/archived/performance_tests/event_query_baseline_test.exs.archived
%{
  archived_date: "2024-01-20",
  archived_by: "dev@example.com",
  original_path: "test/performance/event_query_baseline_test.exs",
  reason: "Baseline performance test for comparison, query has been optimized",
  test_count: 4,
  original_runtime: "120s",
  related_prs: ["#912"],
  retention_period: "2 years",
  review_date: "2026-01-20",
  notes: """
  Historical baseline for event query performance.

  Original metrics (before optimization):
  - Simple query: 450ms average
  - Filtered query: 890ms average
  - Complex join: 2.3s average
  - Full-text search: 1.8s average

  After optimization (PR #912):
  - Simple query: 45ms average (10x improvement)
  - Filtered query: 120ms average (7x improvement)
  - Complex join: 380ms average (6x improvement)
  - Full-text search: 340ms average (5x improvement)

  Keep for historical comparison and future optimization work.
  """
}
```

## Archival Best Practices

### DO ✅

- **Document thoroughly** - Future you will thank you
- **Include return conditions** - Make restoration decisions easy
- **Set review dates** - Prevent forgotten tests
- **Update inventory** - Keep catalog current
- **Reference issues/PRs** - Provide context
- **Note what changed** - Explain why test no longer applies
- **Preserve test history** - Don't lose knowledge
- **Regular reviews** - Quarterly and annual reviews

### DON'T ❌

- **Archive without documentation** - Undocumented tests are useless
- **Skip metadata files** - Context is critical
- **Forget to update inventory** - Inventory keeps archive organized
- **Keep forever** - Everything has a retention period
- **Archive broken tests** - Fix or delete, don't archive
- **Mix archived and active** - Keep clear separation
- **Skip reviews** - Regular reviews prevent bloat

## Archive Inventory Format

### INVENTORY.md Structure

```markdown
# Archived Tests Inventory

Last Updated: 2024-03-15

## Summary
- Total Archived Tests: 24
- Feature Tests: 12
- Integration Tests: 6
- Performance Tests: 4
- Migration Tests: 2

## Upcoming Reviews
- 2024-04-01: 3 tests
- 2024-05-01: 5 tests
- 2024-06-01: 8 tests

## Upcoming Deletions (Retention Period Ending)
- 2024-04-15: Event Schema Migration Test
- 2024-05-01: Old Import Flow Test

---

## Active Archives

### Feature: New Event Flow (2024-02-01)
- **Path:** test/archived/feature_tests/new_event_flow_test.exs
- **Reason:** Feature flag disabled
- **Tests:** 15
- **Review:** 2024-05-01
- **Retention:** 6 months
- **Return Conditions:**
  - A/B test shows improvement
  - Feature flag enabled
- **Related:** #890

### Integration: Bandsintown API (2024-01-15)
- **Path:** test/archived/integration_tests/bandsintown_integration_test.exs
- **Reason:** API temporarily disabled
- **Tests:** 8
- **Review:** 2024-07-15
- **Retention:** 1 year
- **Return Conditions:**
  - API v3 migration complete
  - New API key obtained
- **Related:** #789

[Continue for all archived tests...]

---

## Recently Restored

### Feature: Social Sharing (2024-03-10)
- **Archived:** 2023-09-15
- **Restored:** 2024-03-10
- **New Location:** test/integration/social/sharing_test.exs
- **Reason:** Feature re-enabled after UX improvements

---

## Recently Deleted

### Migration: Old User Schema (2024-03-01)
- **Archived:** 2023-12-01
- **Deleted:** 2024-03-01
- **Reason:** Retention period expired, migration complete
```

## Troubleshooting

### Can't Find Archived Test

**Problem:** Looking for test but can't find in archive

**Solutions:**
1. Check INVENTORY.md for test location
2. Search by original path
3. Check if test was deleted (check git history)
4. Review restoration log

### Test Won't Run After Restoration

**Problem:** Restored test fails immediately

**Solutions:**
1. Update module names if changed
2. Update factory usage to current patterns
3. Check for removed dependencies
4. Update test tags
5. Review assertions against current behavior

### Don't Know Whether to Archive or Delete

**Decision Tree:**
```
Is the test still passing?
├─ No
│  └─ Is it testing removed code?
│     ├─ Yes → Could code return? → Yes: Archive, No: Delete
│     └─ No → Fix test or delete
└─ Yes
   └─ Is test providing value?
      ├─ Yes → Keep active
      └─ No → Will it provide value in future?
          ├─ Yes → Archive with clear return conditions
          └─ No → Delete
```

## Migration from Old Test Structure

### Phase 7: Archive Obsolete Tests (Week 7)

As part of test suite reorganization:

**Tasks:**
1. Identify tests marked with `@tag :skip` or `@tag :skip_ci`
2. Review each skipped test:
   - Why is it skipped?
   - Should it be fixed, archived, or deleted?
3. For archived tests:
   - Create metadata files
   - Move to test/archived/
   - Update inventory
4. For deleted tests:
   - Document deletion reason
   - Remove from codebase

**Current Skipped Tests (8 total):**
- Review each individually
- Determine archive vs delete vs fix

## Related Documentation

- **[test/README.md](../README.md)** - Main test suite documentation
- **[test/BEST_PRACTICES.md](../BEST_PRACTICES.md)** - Testing best practices
- **[test/scripts/README.md](../scripts/README.md)** - Test utility scripts

---

_For questions about test archival, consult this guide or ask in #engineering._
