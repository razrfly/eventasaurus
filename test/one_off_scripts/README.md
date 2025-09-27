# One-Off Test Scripts

This directory contains one-off test scripts that were created for specific debugging and testing purposes. These are not part of the regular test suite but are kept for reference.

## Script Descriptions

### UTF-8 Related Tests
- `test_utf8.exs` - Basic UTF-8 validation tests
- `test_universal_utf8.exs` - Universal UTF-8 handling across scrapers
- `test_venue_utf8.exs` - UTF-8 handling for venue data
- `test_similarity_utf8.exs` - UTF-8 string similarity testing

### Integration Tests
- `test_integration.exs` - Integration test for full scraping pipeline
- `test_ticketmaster.exs` - Ticketmaster API testing
- `test_ticketmaster_full.exs` - Full Ticketmaster integration test
- `test_katy_perry.exs` - Specific event search test case

### Audit Scripts
- `audit_category_system.exs` - Category system audit
- `audit_script.exs` - General system audit
- `poll_audit.exs` - Poll system audit
- `detailed_audit.exs` - Detailed system analysis
- `check_participants.exs` - Event participants verification
- `quick_check.exs` - Quick system health check

## Usage

These scripts can be run individually using:
```bash
mix run test/one_off_scripts/[script_name].exs
```

Note: These are not maintained as part of the regular test suite and may require updates to work with current code.