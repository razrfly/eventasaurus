# Phased Domain Migration: eventasaur.us → wombie.com

## Overview
Structured migration from eventasaur.us to wombie.com domain with "Wombie" branding for all external-facing content. Internal code structure (module names, file paths) remains unchanged.

---

## 📋 Phase 0: Infrastructure Setup (MANUAL)

**Objective**: Prepare external infrastructure for new domain
**Type**: Manual setup tasks
**Dependencies**: None
**Owner**: @holden

### Tasks
- [ ] **DNS Configuration**
  - Configure wombie.com DNS records with domain registrar
  - Point A/AAAA records to hosting infrastructure
  - Verify DNS propagation

- [ ] **SSL/TLS Certificates**
  - Generate SSL certificate for wombie.com
  - Install certificate on hosting platform (Fly.io/other)
  - Test HTTPS connectivity

- [ ] **Email Provider Setup**
  - Configure email sending domain (wombie.com)
  - Set up SPF/DKIM/DMARC records
  - Create email addresses: `support@wombie.com`, `invitations@wombie.com`
  - Test email delivery

- [ ] **Supabase Configuration**
  - Add `https://wombie.com/auth/callback` to allowed redirect URLs
  - Update site URL to `https://wombie.com`
  - Verify OAuth flow works with new domain

### Success Criteria
- [ ] wombie.com resolves to correct IP
- [ ] HTTPS loads without certificate warnings
- [ ] Email sending works from @wombie.com addresses
- [ ] Supabase OAuth redirects function properly

### Estimated Effort
**1-2 hours** (waiting for DNS propagation may add time)

---

## ⚙️ Phase 1: Core Configuration (CODE)

**Objective**: Update application configuration for new domain
**Type**: Code changes
**Dependencies**: Phase 0 (infrastructure must be ready)

### Files to Modify

#### config/runtime.exs (7 changes)
```elixir
# Line 84: Default host
host = System.get_env("PHX_HOST") || "wombie.com"

# Line 91: CORS origins
check_origin: ["https://wombie.com", "https://www.wombie.com", ...]

# Line 175: Site URL
site_url: "https://wombie.com"

# Line 176: OAuth redirect URLs
additional_redirect_urls: ["https://wombie.com/auth/callback"]

# Line 196: Base URL config
config :eventasaurus, :base_url, "https://wombie.com"
```

#### config/supabase.exs
- [ ] Search for any `eventasaur.us` or `eventasaurus.com` references
- [ ] Update to `wombie.com`

#### lib/eventasaurus_web/components/layouts.ex
- [ ] Line 16: Update fallback domain from `"eventasaurus.com"` to `"wombie.com"`

### Tasks
- [ ] Update config/runtime.exs (7 locations)
- [ ] Update config/supabase.exs (if needed)
- [ ] Update layouts.ex fallback domain
- [ ] Test local development with new domain
- [ ] Verify configuration loads correctly

### Success Criteria
- [ ] Application starts without errors
- [ ] All URLs generated use wombie.com
- [ ] OAuth redirects work in development
- [ ] No hardcoded old domain references in config

### Estimated Effort
**30-45 minutes**

---

## 🎨 Phase 2: User-Facing Branding (CODE)

**Objective**: Update all user-visible branding from "Eventasaurus" to "Wombie"
**Type**: Code changes
**Dependencies**: Phase 1 (configuration must be updated first)

### Files to Modify

#### lib/eventasaurus_web/components/core_components.ex
- [ ] Line 890: Logo text `"Eventasaurus"` → `"Wombie"`
- [ ] Consider: Update emoji (🦖/🦕 → something wombie-related)

#### lib/eventasaurus_web/components/layouts/root.html.heex
- [ ] Line 18: Page title suffix `" · Eventasaurus"` → `" · Wombie"`
- [ ] Line 61: OpenGraph site name `"Eventasaurus"` → `"Wombie"`
- [ ] Line 73-77: Default meta descriptions with "Eventasaurus" → "Wombie"
- [ ] Line 453: Support email `support@eventasaurus.com` → `support@wombie.com`
- [ ] Line 475: Copyright `"© ... Eventasaurus"` → `"© ... Wombie"`
- [ ] Line 23: Consider updating favicon (currently dinosaur emoji)

#### lib/eventasaurus/emails.ex
- [ ] Line 9: Email sender `{"Eventasaurus", "invitations@eventasaur.us"}` → `{"Wombie", "invitations@wombie.com"}`
- [ ] Review email templates for branding consistency

### Tasks
- [ ] Update logo component branding
- [ ] Update root layout branding (5+ locations)
- [ ] Update email sender configuration
- [ ] Review email templates for "Eventasaurus" mentions
- [ ] Consider favicon/logo asset updates
- [ ] Test user-facing pages for branding consistency

### Success Criteria
- [ ] All visible pages show "Wombie" branding
- [ ] Browser tab titles show "Wombie"
- [ ] Email "from" shows "Wombie <invitations@wombie.com>"
- [ ] Copyright footer shows "Wombie"
- [ ] No "Eventasaurus" visible to users

### Estimated Effort
**1 hour**

---

## 🔍 Phase 3: SEO & Discovery (CODE)

**Objective**: Update search engine and social sharing metadata
**Type**: Code changes
**Dependencies**: Phase 2 (branding must be consistent)

### Files to Modify

#### JSON-LD Schema Files
- [ ] `lib/eventasaurus_web/json_ld/public_event_schema.ex`
  - Update domain references in event URLs
  - Update organization/brand name

- [ ] `lib/eventasaurus_web/json_ld/local_business_schema.ex`
  - Update business URLs
  - Update brand name

- [ ] `lib/eventasaurus_web/json_ld/breadcrumb_list_schema.ex`
  - Update breadcrumb URLs

#### Open Graph Component
- [ ] `lib/eventasaurus_web/components/open_graph_component.ex`
  - Update default domain
  - Update site name
  - Update default image URLs

#### Sitemap Files
- [ ] `lib/eventasaurus/sitemap.ex`
  - Update base URL from eventasaurus.com to wombie.com

- [ ] `lib/eventasaurus/workers/sitemap_worker.ex`
  - Update domain references

- [ ] `lib/mix/tasks/sitemap.generate.ex`
  - Update domain configuration

### Tasks
- [ ] Update all JSON-LD schema files (3 files)
- [ ] Update OpenGraph component
- [ ] Update sitemap generation (3 files)
- [ ] Generate new sitemap with wombie.com URLs
- [ ] Validate JSON-LD markup with Google's testing tool
- [ ] Test social sharing preview (Twitter, Facebook)

### Success Criteria
- [ ] JSON-LD validates without errors
- [ ] Social sharing shows "Wombie" branding
- [ ] Sitemap contains only wombie.com URLs
- [ ] Search console can read sitemap
- [ ] OpenGraph previews show correct domain

### Estimated Effort
**1-1.5 hours**

---

## 📄 Phase 4: Content & Documentation (CODE + MANUAL)

**Objective**: Update documentation and external-facing content
**Type**: Mixed (code + manual review)
**Dependencies**: Phase 3 (SEO must be updated)

### Files to Modify

#### JavaScript Files
- [ ] `assets/js/musicbrainz_search.js`
  - Line 4: Comment header "Eventasaurus" → "Wombie"
  - Line 18: `appName: 'Eventasaurus'` → `'Wombie'`
  - Line 20: `appContactInfo: 'https://eventasaurus.com'` → `'https://wombie.com'`

- [ ] `assets/js/spotify_search.js`
  - Line 2: Comment header "Eventasaurus" → "Wombie"

#### Legal Pages (3 files)
- [ ] `lib/eventasaurus_web/controllers/page/page_html/privacy.html.heex`
  - Update company name throughout
  - Update contact information
  - Update domain references

- [ ] `lib/eventasaurus_web/controllers/page/page_html/terms.html.heex`
  - Update company name
  - Update domain references
  - Review all legal language

- [ ] `lib/eventasaurus_web/controllers/page/page_html/your_data.html.heex`
  - Update company name
  - Update contact email

#### Documentation Files
- [ ] `README.md`
  - Line 1: `# Eventasaurus 🦕` → `# Wombie [new emoji]`
  - Update all references throughout

- [ ] `docs/DEPLOYMENT.md`
  - Update domain references
  - Update deployment URLs

- [ ] `docs/completed-specs/PRODUCTION_SETUP.md`
  - Update production domain references

- [ ] `SITEMAP_IMPLEMENTATION.md`
  - Update example URLs

### Tasks
- [ ] Update JavaScript API client headers (2 files)
- [ ] Update legal pages - **REQUIRES CAREFUL REVIEW** (3 files)
- [ ] Update README.md
- [ ] Update deployment documentation (3 files)
- [ ] Review all markdown docs for domain references
- [ ] Test external API integrations (MusicBrainz, Spotify)

### Success Criteria
- [ ] API clients identify as "Wombie"
- [ ] Legal pages reviewed and updated
- [ ] Documentation consistent with new branding
- [ ] External APIs recognize new user agent
- [ ] No broken documentation links

### Estimated Effort
**2-3 hours** (legal review takes time)

---

## 🧪 Phase 5: Testing & Validation (CODE)

**Objective**: Comprehensive testing of all changes
**Type**: Code changes + testing
**Dependencies**: Phases 1-4 (all code changes complete)

### Test Files to Update

#### JSON-LD Tests
- [ ] `test/eventasaurus_web/json_ld/public_event_schema_test.exs`
- [ ] `test/eventasaurus_web/json_ld/local_business_schema_test.exs`
- [ ] `test/eventasaurus_web/json_ld/breadcrumb_list_schema_test.exs`

#### Component Tests
- [ ] `test/eventasaurus_web/components/open_graph_component_test.exs`

#### Other Tests
- [ ] `test/eventasaurus/emails_test.exs`
- [ ] Any other tests with hardcoded domain references

### Testing Checklist

#### Functional Testing
- [ ] Homepage loads with "Wombie" branding
- [ ] Event pages show correct domain in URLs
- [ ] User authentication flow works
- [ ] Email sending works with new sender address
- [ ] All links point to wombie.com
- [ ] API integrations function properly

#### SEO Testing
- [ ] JSON-LD validates (Google Rich Results Test)
- [ ] OpenGraph preview works (Twitter Card Validator)
- [ ] Sitemap accessible at wombie.com/sitemap.xml
- [ ] Sitemap contains only wombie.com URLs
- [ ] robots.txt references correct sitemap

#### Cross-Browser Testing
- [ ] Chrome: All functionality works
- [ ] Firefox: All functionality works
- [ ] Safari: All functionality works
- [ ] Mobile browsers: Responsive and functional

#### Email Testing
- [ ] Test email sends from invitations@wombie.com
- [ ] Email contains correct branding
- [ ] Email links point to wombie.com
- [ ] SPF/DKIM passes (check email headers)

### Tasks
- [ ] Update test fixtures with new domain
- [ ] Run full test suite
- [ ] Fix any failing tests
- [ ] Manual testing checklist (functional, SEO, cross-browser, email)
- [ ] Load testing with new domain
- [ ] Security scan on new domain

### Success Criteria
- [ ] All automated tests pass
- [ ] Manual testing checklist complete
- [ ] No console errors on any page
- [ ] SEO validators show no errors
- [ ] Email delivery successful

### Estimated Effort
**2-3 hours**

---

## 🚀 Phase 6: Deployment & Monitoring (MANUAL + CODE)

**Objective**: Deploy to production and monitor
**Type**: Deployment + monitoring
**Dependencies**: Phase 5 (testing complete and passing)

### Pre-Deployment Checklist
- [ ] All previous phases complete
- [ ] All tests passing
- [ ] Staging environment tested successfully
- [ ] Rollback plan documented
- [ ] Team notified of deployment

### Deployment Tasks

#### Production Deployment
- [ ] Deploy code changes to production
- [ ] Verify production environment variables
- [ ] Test production domain (wombie.com)
- [ ] Verify SSL certificate active
- [ ] Check production logs for errors

#### DNS & Redirects (MANUAL - OPTIONAL)
- [ ] If keeping old domain: Set up 301 redirects
  - `eventasaur.us` → `wombie.com`
  - `www.eventasaur.us` → `wombie.com`
- [ ] Test redirect chain
- [ ] Verify no redirect loops

#### Search Engine Updates (MANUAL)
- [ ] Google Search Console: Add wombie.com property
- [ ] Submit new sitemap to search engines
- [ ] If using old domain redirects: Set up address change in Search Console
- [ ] Bing Webmaster Tools: Add wombie.com

#### External Service Updates (MANUAL)
- [ ] Update any third-party integrations with new domain
- [ ] Update analytics tracking (Google Analytics, etc.)
- [ ] Update social media profiles with new website
- [ ] Update any external documentation/wikis

### Monitoring Checklist (First 48 Hours)

#### Technical Monitoring
- [ ] Monitor error rates (should not spike)
- [ ] Monitor response times (should be normal)
- [ ] Check email delivery rates
- [ ] Watch for 404 errors
- [ ] Monitor SSL certificate status

#### User Experience Monitoring
- [ ] Monitor user signups/logins
- [ ] Check for user-reported issues
- [ ] Verify social sharing working
- [ ] Test from different geographic locations
- [ ] Monitor organic search traffic

#### SEO Monitoring
- [ ] Check search engine indexing of new domain
- [ ] Monitor search rankings (may fluctuate initially)
- [ ] Verify crawl budget allocation
- [ ] Check for duplicate content issues

### Tasks
- [ ] Deploy to production
- [ ] Set up domain redirects (if applicable)
- [ ] Update search engine tools
- [ ] Update external services
- [ ] Monitor for 48 hours
- [ ] Document any issues and resolutions

### Success Criteria
- [ ] Production site loads on wombie.com
- [ ] No critical errors in logs
- [ ] Email delivery functioning
- [ ] Search engines can crawl site
- [ ] User experience unchanged (except branding)
- [ ] Analytics tracking correctly

### Rollback Plan
If critical issues arise:
1. Revert code deployment
2. Point DNS back to old domain
3. Restore old email configuration
4. Notify users of temporary reversion
5. Debug issues in staging
6. Re-attempt deployment

### Estimated Effort
**2-4 hours** (deployment + initial monitoring)

---

## 📊 Summary

### Total Estimated Effort
- Phase 0: 1-2 hours (manual)
- Phase 1: 30-45 minutes (code)
- Phase 2: 1 hour (code)
- Phase 3: 1-1.5 hours (code)
- Phase 4: 2-3 hours (code + manual)
- Phase 5: 2-3 hours (testing)
- Phase 6: 2-4 hours (deployment + monitoring)

**Total: ~10-16 hours** across multiple days (DNS propagation, monitoring)

### File Change Summary
- **Configuration files**: 3 files
- **Layout/branding files**: 4 files
- **SEO/metadata files**: 7 files
- **Documentation files**: 6+ files
- **Test files**: 5+ files
- **JavaScript files**: 2 files
- **Legal pages**: 3 files

**Total: ~30 files** (all external-facing, no internal code changes)

### Risk Assessment
- **Low Risk**: Configuration and branding changes (reversible)
- **Medium Risk**: Legal page updates (need careful review)
- **High Risk**: DNS/email setup (requires manual configuration)

### Success Metrics
- [ ] All public-facing content shows "Wombie" branding
- [ ] All URLs use wombie.com domain
- [ ] Emails send from @wombie.com addresses
- [ ] SEO metadata updated correctly
- [ ] Search engines can index new domain
- [ ] User experience unaffected (except branding)
- [ ] No increase in error rates
- [ ] Email deliverability maintained

---

## ⚠️ Important Reminders

### DO NOT CHANGE
- ❌ Module names: `EventasaurusWeb`, `Eventasaurus`, `EventasaurusApp`
- ❌ Database schemas and table names
- ❌ Internal function/variable names
- ❌ File/folder structure: `lib/eventasaurus/`, `lib/eventasaurus_web/`
- ❌ Mix project name in `mix.exs`
- ❌ Internal code comments and documentation strings
- ❌ Test module names

### Key Principles
1. **External Only**: Only change user-facing content
2. **Systematic**: Complete each phase before starting next
3. **Test Everything**: Test after each phase
4. **Document Changes**: Keep track of what was modified
5. **Monitor Closely**: Watch for issues after deployment

---

## 🔗 Related Issues
Supersedes: #1657 (original unstructured issue)
