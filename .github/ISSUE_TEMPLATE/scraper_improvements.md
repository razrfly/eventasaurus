---
name: Scraper Improvement
about: Track improvements to event scrapers based on audit report
title: '[SCRAPER] Improve {source_name} scraper'
labels: scraper, improvement
assignees: ''
---

## Source

**Scraper Name**: [e.g., Resident Advisor]
**Current Grade**: [e.g., A+ (97/100)]
**Priority**: [P0/P1/P2]

## Reference Documents

- [Scraper Specification](../../docs/scrapers/SCRAPER_SPECIFICATION.md)
- [Audit Report](../../docs/scrapers/SCRAPER_AUDIT_REPORT.md)
- [Implementation Guide](../../docs/scrapers/SCRAPER_DOCUMENTATION_SUMMARY.md)
- [Quick Reference](../../docs/scrapers/SCRAPER_QUICK_REFERENCE.md)

## Issues Identified

### Critical (P0)
- [ ] Issue 1
- [ ] Issue 2

### Important (P1)
- [ ] Issue 1
- [ ] Issue 2

### Nice to Have (P2)
- [ ] Issue 1
- [ ] Issue 2

## Acceptance Criteria

- [ ] All required files present and properly organized
- [ ] Transformer returns unified format
- [ ] Uses BaseJob for all Oban workers
- [ ] Deduplication tested (can run daily without duplicates)
- [ ] GPS handling via VenueProcessor
- [ ] Error handling with proper logging
- [ ] Unit tests for transformer
- [ ] README with setup instructions
- [ ] External IDs are stable across runs

## Testing Checklist

- [ ] Unit tests pass
- [ ] Integration test with real data (limited sample)
- [ ] Daily run simulation (run twice, verify no duplicates)
- [ ] Error handling tested (network failures, invalid data)
- [ ] GPS geocoding tested (venues without coordinates)

## Documentation

- [ ] README created/updated
- [ ] Inline code documentation
- [ ] Configuration examples
- [ ] Troubleshooting section

## Deployment

- [ ] Staging environment tested
- [ ] Production deployment plan
- [ ] Monitoring alerts configured
- [ ] Rollback plan documented
