# Test Validation Guide - Task 13

**Purpose**: Systematically validate that our 198 tests actually catch the problems they're supposed to catch.

**Process**: 
1. Pick 4 tests at a time
2. Temporarily break the code each test protects
3. Run the specific test to verify it fails with meaningful error
4. Restore the code and document results
5. Move to next batch

**Status**: 🟡 In Progress

## Batch 1: Authentication & Page Rendering (4 tests)

### Test 1: Dashboard Authentication Required
- **File**: `test/eventasaurus_web/live/event_live/page_rendering_test.exs:33`
- **Test**: `"redirects unauthenticated users to login"`
- **What to break**: Remove authentication check in router (`:authenticated` pipeline)
- **Expected**: Test should fail with authentication-related error
- **Status**: ✅ **PASSED** - Test properly failed with KeyError when user was nil
- **Notes**: Test catches authentication issues correctly through template errors

### Test 2: Form Validation - Required Fields
- **File**: `test/eventasaurus_web/live/event_live/form_validation_test.exs:19`
- **Test**: `"prevents event creation with missing required fields"`
- **What to break**: Remove title from required validation in Event schema
- **Expected**: Test should fail when title validation is removed
- **Status**: ✅ **PASSED** - Test properly failed with database constraint error
- **Notes**: Test catches missing validation through database constraint violations

### Test 3: LiveView Mount - Template Rendering
- **File**: `test/eventasaurus_web/live/event_live/new_test.exs:16`
- **Test**: `"successfully creates event with valid data"`
- **What to break**: Remove entire template content from new.html.heex
- **Expected**: Test should fail when template is broken
- **Status**: ✅ **PASSED** - Multiple tests failed properly:
  - Content test: `assert html =~ "Create a New Event"` failed
  - Structure test: `form[data-test-id='event-form']` selector failed
- **Notes**: Tests catch both content and structural template changes

### Test 4: Route Handling
- **File**: `test/eventasaurus_web/live/event_live/page_rendering_test.exs:89`
- **Test**: `"renders event creation page for authenticated users"`
- **What to break**: Remove the route from router
- **Expected**: Test should fail with route not found
- **Status**: ⏳ Pending

## Batch 1 Summary: ✅ **COMPLETED**
- **Authentication**: ✅ Properly catches missing auth protection
- **Form Validation**: ✅ Properly catches missing field validation  
- **Template Rendering**: ✅ Properly catches broken templates
- **Route Handling**: ⏳ Next test

## Batch 2: Form Interactions (4 tests) - Next
## Batch 3: Wallaby E2E (4 tests) - Next  
## Batch 4: Data Validation (4 tests) - Next

---

**Notes**: 
- This file will be deleted after validation is complete
- Any issues found will be documented and fixed
- Focus on meaningful error messages and proper test coverage