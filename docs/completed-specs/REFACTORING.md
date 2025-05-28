# Eventasaurus Refactoring Recommendations

## Overview

This document outlines potential refactoring opportunities based on recent changes to the Eventasaurus codebase. These recommendations focus on code organization, consistency, and maintenance without introducing new features.

## High Priority Refactoring

### 1. Remove Unused Code & Aliases

- Remove unused `Venues` alias in `EventController`
- Clean up any references to deleted files (e.g., `public_event_controller.ex`)
- Remove unused function parameters and variables

### 2. Database Schema Consistency

- Ensure enum values in schemas match database constraints
- Add proper documentation for schema fields 
- Consider adding validation for capacity (should be positive integer)

### 3. Controller Organization

- Consider moving layout handling logic from controller to plug
- Move route-specific logic (differentiating between public/internal views) into dedicated module

## Medium Priority Refactoring

### 4. Template Organization & Duplication

- Extract common components between public and internal templates
- Create shared partials for date/time formatting, location display, etc.
- Consider using Phoenix Components for UI elements used in multiple places

### 5. Error Handling

- Add better error handling for when events don't exist
- Standardize flash message formats and content

### 6. Query Optimization

- Review preloading strategy in Events context
- Consider adding a separate function for lightweight event queries

## Low Priority Refactoring

### 7. Documentation Updates

- Update module and function documentation to reflect new dual-view approach
- Add examples of proper route usage in comments

### 8. Test Coverage

- Add tests for new routes and controller actions
- Create tests for both public and internal views
- Add tests for different event visibility scenarios

### 9. Code Style

- Ensure consistent pattern matching style in function definitions
- Review naming conventions for consistency (e.g., get_* vs fetch_*)

## Technical Debt to Address

### 10. Potential Issues

- ✅ Fixed inconsistency between New and Edit LiveViews - edit page now properly handles the slug parameter and uses consistent data structures for search results
- Verify proper authorization checks on all admin routes
- Review open graph meta tags implementation
- Ensure proper escaping of user-generated content in templates

### 11. Performance Considerations

- Review N+1 query patterns, especially when loading events with many attendees
- Consider adding caching for public event pages

## Next Steps

1. Address high priority refactoring issues first
2. Create specific tasks for each refactoring item
3. Consider establishing coding standards documentation to prevent future inconsistencies 