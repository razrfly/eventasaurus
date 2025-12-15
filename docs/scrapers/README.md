# Event Scraper Documentation

> **Essential reading** for anyone working with Eventasaurus event discovery scrapers

---

## 📚 Documentation Index

### ⭐ Start Here

**[SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md)** - **REQUIRED READING**
- The official specification for all event scrapers
- Directory structure and naming conventions
- Unified data format and transformation standards
- **Category mapping system (YAML-based)** 🆕
- Deduplication strategies
- GPS coordinate handling
- Job patterns and architectures
- Error handling and testing requirements

👉 **Read this first before building or modifying any scraper**

---

### 📊 Current State

**[SCRAPER_AUDIT_REPORT.md](./SCRAPER_AUDIT_REPORT.md)**
- Comprehensive audit of all 7 scrapers
- Grading rubric and individual scores
- Detailed strengths and weaknesses
- Priority-based action items (P0/P1/P2)
- Scraper comparison matrix

**Current Average Grade**: 83.3/100 (B)

**Production-Ready Scrapers**:
- ✅ Resident Advisor (A+ 97/100)
- ✅ Ticketmaster (A 91/100)

---

### 🛠️ Implementation Guides

**[SCRAPER_DOCUMENTATION_SUMMARY.md](./SCRAPER_DOCUMENTATION_SUMMARY.md)**
- Overview of documentation set
- 3-phase improvement plan (Weeks 1-3)
- Critical issues and priorities
- New scraper onboarding process
- Metrics and monitoring guidelines

**[SCRAPER_QUICK_REFERENCE.md](./SCRAPER_QUICK_REFERENCE.md)**
- Developer cheat sheet
- Quick start guide for new scrapers
- Common code patterns and examples
- Testing snippets
- Debugging commands
- Common mistakes to avoid

---

## 🎯 Quick Links by Task

### I want to...

**Build a new scraper**
1. Read [SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md)
2. Copy reference: `lib/eventasaurus_discovery/sources/resident_advisor/`
3. Create YAML category mapping: `priv/category_mappings/{source}.yml` (if applicable)
4. Check [SCRAPER_QUICK_REFERENCE.md](./SCRAPER_QUICK_REFERENCE.md) for patterns
5. Test: Run twice, verify no duplicates

**Fix an existing scraper**
1. Check [SCRAPER_AUDIT_REPORT.md](./SCRAPER_AUDIT_REPORT.md) for issues
2. Review [SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md) for standards
3. See [SCRAPER_DOCUMENTATION_SUMMARY.md](./SCRAPER_DOCUMENTATION_SUMMARY.md) for improvement plan
4. Create issue using template: `.github/ISSUE_TEMPLATE/scraper_improvements.md`

**Understand current scrapers**
1. Start with [SCRAPER_AUDIT_REPORT.md](./SCRAPER_AUDIT_REPORT.md) for overview
2. Review individual scraper grades and notes
3. Check reference implementations (Resident Advisor, Ticketmaster)

**Debug a scraper issue**
1. Check [SCRAPER_QUICK_REFERENCE.md](./SCRAPER_QUICK_REFERENCE.md) debugging section
2. Review error handling in [SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md)
3. Look at job logs and error patterns

**Audit scraper health**
1. Run `mix audit.scheduler_health` to verify jobs are running on schedule
2. Run `mix audit.date_coverage` to check for gaps in date coverage
3. Run `mix monitor.collisions` to detect TMDB matching issues
4. See [../scraper-monitoring-guide.md](../scraper-monitoring-guide.md) for detailed audit tool documentation

---

## 🚨 Critical Warnings

### Before You Code

1. **Always read SCRAPER_SPECIFICATION.md first** - It's the source of truth
2. **Never manual geocode** - VenueProcessor handles this automatically
3. **Test daily idempotency** - Run scraper twice, verify no duplicates
4. **Use stable external_ids** - Must be consistent across runs
5. **Follow reference implementations** - Resident Advisor and Ticketmaster

### Common Pitfalls

❌ **Don't**: Create new venue geocoding logic
✅ **Do**: Let VenueProcessor handle GPS coordinates

❌ **Don't**: Use `NaiveDateTime` for event times
✅ **Do**: Use `DateTime` with proper timezone conversion

❌ **Don't**: Generate external_ids with timestamps
✅ **Do**: Use stable identifiers from source data

❌ **Don't**: Skip tests
✅ **Do**: Test transformer, deduplication, and daily runs

---

## 📊 Current Scraper Status

| Scraper | Grade | Status | Priority Actions |
|---------|-------|--------|------------------|
| Resident Advisor | A+ (97) | ✅ Production | Add tests, create README |
| Ticketmaster | A (91) | ✅ Production | Add integration tests |
| Karnet | B+ (85) | ⚠️ Needs Tests | Add test suite, document |
| Cinema City | B (82) | ⚠️ Needs Validation | Test daily idempotency |
| Kino Krakow | B- (80) | ⚠️ Needs Validation | Test daily idempotency |
| Bandsintown | C+ (75) | ❌ Needs Work | **Consolidate duplicates** |
| PubQuiz | C (73) | ⚠️ Needs Refactor | Add tests, improve transformer |

See [SCRAPER_AUDIT_REPORT.md](./SCRAPER_AUDIT_REPORT.md) for detailed grading breakdown.

---

## 🎓 Learning Path

### For New Developers

1. **Day 1**: Read SCRAPER_SPECIFICATION.md completely
2. **Day 2**: Review Resident Advisor implementation (`sources/resident_advisor/`)
3. **Day 3**: Review Ticketmaster implementation (`sources/ticketmaster/`)
4. **Day 4**: Read SCRAPER_AUDIT_REPORT.md to understand current state
5. **Day 5**: Try adding a test to an existing scraper

### For Experienced Developers

1. Review SCRAPER_SPECIFICATION.md (30 min)
2. Check SCRAPER_QUICK_REFERENCE.md for patterns (15 min)
3. Review specific scraper in SCRAPER_AUDIT_REPORT.md (10 min)
4. Start implementing with reference to spec

---

## 📝 Related Documentation

- **Main README**: [../../README.md](../../README.md) - Project overview and setup
- **Issue Template**: [.github/ISSUE_TEMPLATE/scraper_improvements.md](../../.github/ISSUE_TEMPLATE/scraper_improvements.md)
- **GitHub Issues**: [Scraper Audit Report #1552](https://github.com/razrfly/eventasaurus/issues/1552)

---

## 🤝 Contributing

When working on scrapers:

1. ✅ Follow the specification
2. ✅ Use reference implementations
3. ✅ Test thoroughly (daily idempotency!)
4. ✅ Document your changes
5. ✅ Create issues using the template

---

## 📞 Getting Help

1. Check [SCRAPER_QUICK_REFERENCE.md](./SCRAPER_QUICK_REFERENCE.md) first
2. Review [SCRAPER_SPECIFICATION.md](./SCRAPER_SPECIFICATION.md) for standards
3. Look at reference implementations (Resident Advisor, Ticketmaster)
4. Check [SCRAPER_AUDIT_REPORT.md](./SCRAPER_AUDIT_REPORT.md) for known issues
5. Run audit tools: `mix audit.scheduler_health`, `mix audit.date_coverage`, `mix monitor.collisions`
6. Create a GitHub issue if needed

---

**Last Updated**: 2025-12-15
**Specification Version**: 1.0
**Average Scraper Grade**: 83.3/100 (B)
