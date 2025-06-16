# PRD: Test Suite Refactoring & Curation

## 1. Background & Problem Statement

Our current test suite, comprising several hundred tests across the `eventasaurus` project, has grown organically. This has led to several challenges:

*   **Lack of Clear Organization:** Tests for different concerns (unit, integration, E2E) are intermingled, making it difficult to reason about coverage and run specific test subsets.
*   **Redundancy & Inefficiency:** We have observed duplicate tests (e.g., `svg_converter_test`), and many tests build on each other implicitly rather than through explicit, shared setup. This slows down the test suite and makes it brittle.
*   **Maintenance Overhead:** Without clear conventions, adding new tests is inconsistent, and refactoring existing ones is a high-effort task. It's difficult for developers to know where to add a new test or how to structure it.
*   **Flakiness:** Integration and feature tests, when mixed with unit tests, can introduce flakiness into the main CI pipeline, slowing down development velocity.

This document outlines a plan to audit, refactor, and reorganize our existing tests, and establish a clear, forward-looking strategy for maintaining a healthy, efficient, and curated test suite.

## 2. Goals & Objectives

The primary goals of this initiative are to:

1.  **Improve Developer Experience:** Make writing, running, and debugging tests faster and more intuitive.
2.  **Increase CI/CD Efficiency:** Reduce test execution time and stabilize the build process by isolating different types of tests.
3.  **Enhance Code Quality:** Eliminate redundant tests, improve coverage, and ensure our tests provide a reliable safety net for refactoring and new feature development.
4.  **Establish Clear Standards:** Create a living document and set of conventions that guide future test development.

## 3. Audit of Current Test Structure

Based on an analysis of the `test/` directory, the current structure is as follows:

*   `test/eventasaurus/`: Core business logic tests.
    *   `services/`: Tests for service modules.
    *   `social_cards/`: Tests related to social card generation.
*   `test/eventasaurus_app/`: Application-level tests, including data-layer and business logic.
    *   `events/`: Tests for the `Events` context.
*   `test/eventasaurus_web/`: Web-layer tests.
    *   `features/`: End-to-end user journey tests (using Wallaby).
    *   `integration/`: Tests for specific web functionalities like authentication UX.
    *   `live/`: Phoenix LiveView tests.
    *   `services/`: Web-specific service tests.
*   `test/support/`: Helper modules, fixtures, and factories.

This structure mixes unit tests, integration tests (those hitting the database), and feature tests (those running a browser).

## 4. Proposed New Test Architecture & Strategy

We will restructure the `test/` directory to explicitly separate tests by their type and purpose. This aligns with Elixir community best practices and provides immediate clarity.

### 4.1. New Directory Structure

```
test/
├── unit/               # Pure functions, no external dependencies (DB, APIs). Fast.
│   ├── eventasaurus/
│   └── eventasaurus_app/
├── integration/        # Tests requiring the DB or other tightly-coupled services.
│   ├── eventasaurus_app/
│   └── eventasaurus_web/
├── feature/            # Isolated browser tests for specific components (Wallaby).
│   └── eventasaurus_web/
├── journeys/           # Complete end-to-end user flows (Playwright).
│   └── eventasaurus_web/
├── support/            # Unchanged: ConnCase, DataCase, fixtures, factories.
│   ├── conn_case.ex
│   ├── data_case.ex
│   ├── factory.ex
│   └── ...
└── test_helper.exs     # Unchanged.
```

### 4.2. Test Categorization & Tagging

We will use a combination of directory location and `ExUnit` tags to manage our tests.

*   **Location:** The directory (`unit/`, `integration/`, `feature/`) will be the primary means of categorization.
*   **Tags:** We will use `@moduletag` to enforce this.
    *   Files in `unit/` will have `@moduletag :unit`.
    *   Files in `integration/` will have `@moduletag :integration`.
    *   Files in `feature/` will have `@moduletag :feature`.
    *   Files in `journeys/` will have `@moduletag :journey`.
*   **`async: true`:** All unit tests **must** run with `async: true`. Integration tests will be evaluated on a case-by-case basis but will default to `async: false`. Feature tests must run `async: false`.

### 4.3. Mix Aliases for Targeted Test Runs

We will create `mix` aliases in `mix.exs` to run specific subsets of tests.

```elixir
# In mix.exs
defp aliases do
  [
    "test.all": ["test"],
    "test.unit": ["test --only unit"],
    "test.integration": ["test --only integration"],
    "test.feature": ["test --only feature"],
    "test.journeys": ["test --only journey"],
    # A pre-push hook alias
    "test.pre_commit": ["test.unit"]
  ]
end
```

This allows developers to run fast unit tests locally before pushing, while CI can run more comprehensive suites.

### 4.4. E2E & Journey Testing: Wallaby vs. Playwright

We are currently using both Wallaby and Playwright for browser-based testing. To move forward effectively, we need a clear strategy.

*   **Wallaby:** Tightly integrated into Elixir, allowing for easy use of `Mox`, factories, and other backend code. It's excellent for testing specific LiveView components or features in isolation.
*   **Playwright:** A modern, powerful, Node.js-based tool that excels at running complex, multi-step user journeys. Its debugging and tracing capabilities are superior for diagnosing issues in long-running flows.

**Recommendation:**

1.  **Standardize on Playwright for `journeys/`:** All new, complete user journey tests (e.g., registration-to-ticket-purchase) should be written using Playwright. This leverages its strengths for our most critical end-to-end flows.
2.  **Use Wallaby for `feature/` tests:** Existing Wallaby tests, which tend to be smaller in scope, will be categorized as `feature` tests. This is a good home for tests that verify a single page or component's functionality.
3.  **Gradual Migration:** We will not perform a mass-rewrite. Instead, as Wallaby tests become flaky or as the features they cover are significantly updated, we will migrate them to Playwright.

This approach allows us to use the best tool for the job while providing a clear path toward consolidating our E2E suite on a single, modern tool in the long term.

## 5. Refactoring & Migration Plan

This will be a phased approach to minimize disruption.

### Phase 1: Setup & Initial Migration (1-2 days)

1.  **Create New Directories:** Create the `unit/`, `integration/`, `feature/`, and `journeys/` directories.
2.  **Update `mix.exs`:** Add the new `mix` aliases.
3.  **Initial File Move:** Perform a "best guess" move of existing test files into the new directories.
    *   Most files in `test/eventasaurus` -> `test/unit/eventasaurus`.
    *   Files in `test/eventasaurus_app` that use `DataCase` -> `test/integration/eventasaurus_app`.
    *   Existing **Wallaby** tests -> `test/feature/eventasaurus_web`.
    *   Existing **Playwright** tests -> `test/journeys/eventasaurus_web`.
    *   Files in `test/eventasaurus_web/live` -> `test/integration/eventasaurus_web` (as they often require the DB).
4.  **Add Tags:** Add the corresponding `@moduletag` to each moved file.
5.  **Run Subsets:** Run each test subset (`mix test.unit`, etc.) to ensure they pass. Fix any initial issues with paths or helpers.

### Phase 2: Audit, Refactor & Remove (3-5 days)

This is the core of the work. We will tackle this context by context.

1.  **Identify Redundancy:**
    *   **Example:** `test/eventasaurus/services/svg_converter_test.exs` and `test/eventasaurus_web/services/svg_conversion_test.exs` likely test the same thing. We will consolidate them into a single `test/unit/eventasaurus/services/svg_converter_test.exs`.
2.  **Refactor Brittle Tests:**
    *   Review tests with complex, multi-step setups. Break them into smaller, more focused tests.
    *   Ensure proper use of `Mox` for mocking external services, especially in integration and feature tests.
3.  **Consolidate Factories & Fixtures:**
    *   Review `test/support/fixtures` and `test/support/factory.ex`. Ensure factories are the primary way to generate test data and that fixtures are only used for static assets (e.g., sample images).
4.  **Enforce `async: true`:** Audit all tests in `test/unit` and ensure they can and do run with `async: true`. Refactor any that can't to remove side-effects.

### Phase 3: Documentation & Future Governance (1 day)

1.  **Create `TESTING_GUIDE.md`:** Create a new markdown file in the root or `docs/` directory. This guide will be the source of truth for testing. It will include:
    *   The testing philosophy and structure.
    *   An explanation of each test type (`unit`, `integration`, `feature`).
    *   Instructions on where to add new tests.
    *   How to use the `mix` aliases.
    *   Best practices for writing good tests (e.g., using factories, mocking).
2.  **Team Review:** Share the guide with the team for feedback and buy-in.

## 6. Going Forward: A System for New Tests

With the new structure and documentation in place, the process for adding a new test becomes clear:

1.  **What am I testing?**
    *   A pure function with no dependencies? -> It's a **unit test**. Place it in `test/unit/`.
    *   Logic that involves the database or other application contexts? -> It's an **integration test**. Place it in `test/integration/`.
    *   A user flow through the web interface? -> It's a **feature test**. Place it in `test/feature/`.
2.  **Consult `TESTING_GUIDE.md`** for conventions and examples.
3.  **Use `mix test.pre_commit`** before pushing code to get fast feedback.

This systematic approach will prevent the test suite from degrading over time and ensure it remains a valuable asset for the team.

## 7. Next Steps

1.  **Approval:** Seek approval for this plan from the project stakeholders.
2.  **Execution:** Begin Phase 1 of the migration plan.
3.  **Communication:** Keep the team informed of the progress and changes.
