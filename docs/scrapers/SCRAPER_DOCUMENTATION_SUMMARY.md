# Scraper Documentation & Audit Summary

> **Created**: 2025-10-07
> **Purpose**: Overview of scraper standardization initiative

---

## 📚 Documentation Overview

This initiative created three core documents to standardize and improve all event data scrapers:

### 1. [SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md)
**The Source of Truth** for how all scrapers should be built.

- ✅ Directory structure and naming conventions
- ✅ Required files and their purposes
- ✅ Unified data format (transformer output)
- ✅ Deduplication strategies (venues, events, performers)
- ✅ GPS coordinate handling (VenueProcessor integration)
- ✅ Job patterns and architectures
- ✅ Error handling standards
- ✅ Testing requirements
- ✅ Daily operation checklist

**Use this when**: Building new scrapers or refactoring existing ones

### 2. [SCRAPER_AUDIT_REPORT.md](./SCRAPER_AUDIT_REPORT.md)
**Grading and analysis** of all 7 existing scrapers.

- ✅ Grading rubric (10 categories, 100-point scale)
- ✅ Individual scraper reports with scores
- ✅ Strengths and weaknesses
- ✅ Specific improvement recommendations
- ✅ Priority-based action items (P0/P1/P2)
- ✅ Phase-based implementation plan

**Use this when**: Prioritizing improvements or understanding current state

### 3. [GitHub Issue Template](./.github/ISSUE_TEMPLATE/scraper_improvements.md)
**Standardized issue format** for tracking improvements.

- ✅ Structured checklist
- ✅ Testing requirements
- ✅ Documentation requirements
- ✅ Deployment checklist

**Use this when**: Creating issues for scraper improvements

---

## 🎯 Current State

### Scraper Inventory

| Scraper | Location | Grade | Status |
|---------|----------|-------|--------|
| **Resident Advisor** | `sources/resident_advisor/` | A+ (97) | ✅ Production Ready |
| **Ticketmaster** | `sources/ticketmaster/` | A (91) | ✅ Production Ready |
| **Karnet** | `sources/karnet/` | B+ (85) | ⚠️ Needs Tests |
| **Cinema City** | `sources/cinema_city/` | B (82) | ⚠️ Needs Validation |
| **Kino Krakow** | `sources/kino_krakow/` | B- (80) | ⚠️ Needs Validation |
| **Bandsintown** | `sources/bandsintown/` + `scraping/scrapers/bandsintown/` | C+ (75) | ❌ Needs Consolidation |
| **PubQuiz** | `sources/pubquiz/` | C (73) | ⚠️ Needs Refactoring |

**Average Grade**: 83.3/100 (B) - Good foundation, needs improvement

### Reference Implementations

**Best Practices** - Use these as templates:

1. **Resident Advisor** - Modern GraphQL scraper with comprehensive deduplication
2. **Ticketmaster** - Premium API integration with excellent error handling

---

## 🚨 Critical Issues

### P0 - Immediate Action Required

1. **Bandsintown Consolidation**
   - Duplicate implementations in `scraping/scrapers/` and `sources/`
   - **Action**: Consolidate into `sources/bandsintown/`
   - **Impact**: Confusion about which version runs, potential bugs

2. **Missing Tests**
   - Only Resident Advisor has minimal tests
   - **Action**: Add test suites for all scrapers
   - **Impact**: Can't validate daily operation, risky deployments

3. **Daily Operation Validation**
   - Cinema City, Kino Krakow, PubQuiz not tested for idempotency
   - **Action**: Run twice daily and verify no duplicates
   - **Impact**: May create duplicate events/venues

### P1 - Important

1. **Documentation Gap**
   - Most scrapers lack README files
   - **Action**: Create setup/config documentation
   - **Impact**: Difficult onboarding, configuration errors

2. **GPS Handling**
   - Some scrapers have manual geocoding
   - **Action**: Use VenueProcessor exclusively
   - **Impact**: Duplicate venues, inconsistent data

### P2 - Nice to Have

1. **Cinema Source Consolidation**
   - Cinema City and Kino Krakow have similar logic
   - **Action**: Extract shared cinema module
   - **Impact**: Code duplication, maintenance burden

---

## 📋 Implementation Plan

### Phase 1: Critical Fixes (Week 1)

#### Goals
- Eliminate duplicate implementations
- Ensure basic test coverage
- Validate daily operation

#### Tasks
1. **Bandsintown Consolidation**
   - [ ] Determine canonical implementation
   - [ ] Consolidate into `sources/bandsintown/`
   - [ ] Remove duplicate in `scraping/scrapers/`
   - [ ] Update job configurations

2. **Basic Test Suite** (All Scrapers)
   - [ ] Transformer unit tests
   - [ ] External ID stability tests
   - [ ] Daily run simulation tests

3. **Daily Operation Validation**
   - [ ] Cinema City: Run twice, verify no dupes
   - [ ] Kino Krakow: Run twice, verify no dupes
   - [ ] PubQuiz: Run twice, verify no dupes

#### Success Criteria
- ✅ No duplicate scraper implementations
- ✅ All scrapers have basic tests
- ✅ Cinema sources validated for daily use

---

### Phase 2: Quality Improvements (Week 2)

#### Goals
- Improve documentation
- Standardize GPS handling
- Better error handling

#### Tasks
1. **Documentation** (All Scrapers)
   - [ ] Create README templates
   - [ ] Document configuration
   - [ ] Add troubleshooting guides
   - [ ] Include usage examples

2. **GPS Handling Refactor**
   - [ ] Karnet: Remove manual geocoding
   - [ ] PubQuiz: Use VenueProcessor
   - [ ] Validate GPS fallback logic

3. **Error Handling Improvements**
   - [ ] Add emoji logging (✅❌⚠️🔄)
   - [ ] Distinguish critical vs retryable
   - [ ] Improve log context

#### Success Criteria
- ✅ All scrapers have comprehensive READMEs
- ✅ Consistent GPS handling via VenueProcessor
- ✅ Clear, actionable error messages

---

### Phase 3: Advanced Features (Week 3)

#### Goals
- Add deduplication handlers
- Comprehensive testing
- Evaluate consolidation opportunities

#### Tasks
1. **Deduplication Handlers**
   - [ ] Karnet: Add dedup_handler.ex
   - [ ] Bandsintown: Add dedup_handler.ex
   - [ ] PubQuiz: Add dedup_handler.ex

2. **Integration Tests** (All Scrapers)
   - [ ] Real API/scraping tests with fixtures
   - [ ] Error scenario testing
   - [ ] Performance benchmarks

3. **Cinema Consolidation Analysis**
   - [ ] Identify shared cinema logic
   - [ ] Design shared module
   - [ ] Evaluate migration effort
   - [ ] Decision: Consolidate or keep separate

#### Success Criteria
- ✅ All scrapers have dedup handlers
- ✅ Comprehensive test coverage (>80%)
- ✅ Decision made on cinema consolidation

---

## 🎓 New Scraper Onboarding

When adding a new event source, follow this process:

### 1. Planning
- [ ] Review [SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md)
- [ ] Check source priority (0-100)
- [ ] Identify data source type (API, HTML scraper, feed)
- [ ] Determine required features (GPS, performers, prices)

### 2. Implementation
- [ ] Create directory: `sources/{source_name}/`
- [ ] Implement required files (source.ex, config.ex, transformer.ex, jobs)
- [ ] Use BaseJob for Oban workers
- [ ] Return unified format from transformer
- [ ] Let VenueProcessor handle GPS/geocoding

### 3. Testing
- [ ] Unit tests for transformer
- [ ] Integration test with real data sample
- [ ] Daily run simulation (run twice, verify no duplicates)
- [ ] Error handling tests

### 4. Documentation
- [ ] Create README
- [ ] Document configuration
- [ ] Add usage examples
- [ ] Include troubleshooting

### 5. Deployment
- [ ] Test in staging
- [ ] Configure monitoring
- [ ] Deploy to production
- [ ] Monitor first daily run

### Reference Implementations
- **API Source**: [sources/ticketmaster/](./lib/eventasaurus_discovery/sources/ticketmaster/)
- **GraphQL Source**: [sources/resident_advisor/](./lib/eventasaurus_discovery/sources/resident_advisor/)
- **HTML Scraper**: [sources/karnet/](./lib/eventasaurus_discovery/sources/karnet/)
- **Cinema Source**: [sources/cinema_city/](./lib/eventasaurus_discovery/sources/cinema_city/)

---

## 📊 Metrics & Monitoring

### Key Metrics to Track

1. **Data Quality**
   - Events created vs updated (should be mostly updates after initial run)
   - Venue deduplication rate
   - Geocoding success rate
   - Events with GPS coordinates

2. **Performance**
   - Sync job duration
   - Events processed per minute
   - API rate limit compliance
   - Job failure rate

3. **Coverage**
   - Active event sources
   - Cities covered per source
   - Events per source per day
   - Data freshness (last_seen_at distribution)

### Monitoring Alerts

- ⚠️ **Job failures** > 10% for any source
- ⚠️ **Geocoding failures** > 5%
- ⚠️ **Duplicate venues created** (should be rare)
- ⚠️ **No events updated** in daily run (source may be down)

---

## 🔄 Ongoing Maintenance

### Weekly
- [ ] Review scraper logs for errors
- [ ] Check geocoding success rates
- [ ] Monitor duplicate detection

### Monthly
- [ ] Audit deduplication effectiveness
- [ ] Review new events vs updates ratio
- [ ] Check for scraper failures
- [ ] Update documentation as needed

### Quarterly
- [ ] Review scraper priorities
- [ ] Evaluate new sources to add
- [ ] Assess consolidation opportunities
- [ ] Update specification if needed

---

## 📖 Additional Resources

### Internal
- [VenueProcessor](./lib/eventasaurus_discovery/scraping/processors/venue_processor.ex) - GPS matching logic
- [EventProcessor](./lib/eventasaurus_discovery/scraping/processors/event_processor.ex) - Event deduplication
- [BaseJob](./lib/eventasaurus_discovery/sources/base_job.ex) - Job behavior

### External
- [Oban Documentation](https://hexdocs.pm/oban/Oban.html) - Background jobs
- [HTTPoison](https://hexdocs.pm/httpoison/HTTPoison.html) - HTTP client
- [Floki](https://hexdocs.pm/floki/Floki.html) - HTML parsing

---

## 🤝 Contributing

When improving scrapers:

1. **Follow the Spec** - [SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md) is the source of truth
2. **Use the Template** - Create issues using [scraper_improvements.md](./.github/ISSUE_TEMPLATE/scraper_improvements.md)
3. **Test Thoroughly** - Daily operation must be idempotent
4. **Document Changes** - Update READMEs and inline docs
5. **Reference Best Practices** - Look at Resident Advisor and Ticketmaster

---

## 🎯 Success Criteria

This initiative is successful when:

- ✅ All scrapers score B+ (85+) or higher
- ✅ All scrapers have comprehensive tests
- ✅ All scrapers run daily without duplicates
- ✅ New scrapers can be added in <1 day
- ✅ Documentation is comprehensive and up-to-date

**Current Progress**: 2/7 scrapers are production-ready (Resident Advisor, Ticketmaster)
**Target**: 7/7 scrapers production-ready within 3 weeks
