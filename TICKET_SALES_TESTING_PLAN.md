# Comprehensive Ticket Sales Testing Plan

## Overview

This issue tracks the complete testing plan for ticket sales and threshold events, from development E2E testing through production rollout.

## Current State Analysis

### ✅ What EXISTS

**Phase 1: Core Ticket Sales** (`priv/repo/dev_seeds/features/ticketing/ticket_scenarios.exs:seed_phase_1()`)
- Low-price event ($8 coffee meetup)
- High-price event ($299-499 tech conference)
- Multi-tier festival (5 ticket types, $89-449)
- Small capacity (15-seat chef's table, $185)
- Large capacity (800+ career expo, $5-49)

**Phase 2: Threshold Events** (`priv/repo/dev_seeds/features/ticketing/ticket_scenarios.exs:seed_phase_2()`)
1. **Community Garden Project** - Revenue threshold: $5,000
2. **New Playground for Lincoln Elementary** - Revenue threshold: $10,000
3. **Mystery Book Club Launch** - Attendee threshold: 20 people (FREE event)
4. **Advanced Photography Workshop** - Revenue threshold: $1,125
5. **Intro to Web Development Bootcamp** - Combined threshold: 50 attendees AND $2,500

### ❌ What DOESN'T EXIST

- Go-karting threshold event (exists as regular ticketed event only)
- Tram party event (does not exist)
- README documentation for threshold test scenarios

### 🔍 Threshold Event Schema

From `lib/eventasaurus_app/events/event.ex`:
- `status: :threshold` - Event awaiting threshold
- `threshold_type` - "attendee_count" | "revenue" | "both"
- `threshold_count` - Minimum attendees required
- `threshold_revenue_cents` - Minimum revenue required (in cents)
- `threshold_met?` - Virtual field (calculated)

---

## PHASE 1: Documentation & Seed Data Preparation

**Objective:** Document existing test scenarios and prepare seed data

### Tasks

- [ ] **Update README.md** with threshold event test scenarios section
  - [ ] Document all 5 existing Phase 2 threshold events
  - [ ] Include test organizer login credentials
  - [ ] Add instructions for running seeds
  - [ ] Add seed execution examples

- [ ] **Optional:** Create additional threshold events
  - [ ] Go-kart racing threshold event (minimum 30 participants OR $1,500 revenue)
  - [ ] Tram party threshold event (minimum 50 participants OR $2,500 revenue)

- [ ] **Verify seeds work correctly**
  ```bash
  mix ecto.reset
  mix seed.dev
  # Verify threshold events created with correct status
  ```

**Test Organizer Credentials:**
- Email: `community_builder@example.com`
- Password: `testpass123`

**Test Scenarios Available:**
- **Revenue Threshold**: Community Garden ($5k), Playground ($10k), Photography ($1,125)
- **Attendee Threshold**: Book Club (20 people)
- **Combined Threshold**: Coding Bootcamp (50 attendees + $2,500)

---

## PHASE 2: Development Environment E2E Testing (Playwright)

**Objective:** Comprehensive end-to-end testing of ticket purchase flow in development

**Prerequisites:**
- [ ] Development server running (`mix phx.server`)
- [ ] Seeds populated with threshold events
- [ ] Playwright MCP server available

### 2.1: Basic Ticket Purchasing

- [ ] **Logged-in user purchases ticket**
  - Navigate to event page
  - Select ticket type and quantity
  - Complete checkout flow
  - Verify order confirmation
  - Verify ticket quantity decreases

- [ ] **Guest user purchases ticket**
  - Navigate to event page as unauthenticated user
  - Select ticket and proceed to checkout
  - Enter email and payment details
  - Complete purchase
  - Verify guest account created
  - Verify confirmation email sent

### 2.2: Ticket Inventory Management

- [ ] **Ticket quantity reduces on purchase**
  - Check initial ticket quantity
  - Complete purchase
  - Verify quantity decremented
  - Verify "X tickets remaining" updates

- [ ] **Failed payment doesn't reduce inventory**
  - Start checkout process
  - Use failing test card
  - Verify payment fails
  - Verify ticket quantity unchanged
  - Verify ticket still available for purchase

- [ ] **Sold out scenario**
  - Purchase all available tickets
  - Verify "Sold Out" badge appears
  - Verify purchase button disabled
  - Verify waitlist option (if implemented)

### 2.3: Threshold Event Testing - Revenue Thresholds

**Test Event: Community Garden Project ($5,000 threshold)**
- [ ] Check initial status shows "Threshold: $0 / $5,000"
- [ ] Purchase $500 ticket
- [ ] Verify progress: "$500 / $5,000 (10%)"
- [ ] Purchase multiple tickets to reach $4,900
- [ ] Verify status still "threshold" (not met)
- [ ] Purchase final $100+ to exceed threshold
- [ ] Verify event status changes to "confirmed"
- [ ] Verify confirmation emails sent to all purchasers

**Test Event: Playground Fundraiser ($10,000 threshold)**
- [ ] Repeat above tests with higher threshold
- [ ] Test partial refund scenario (if threshold met, then refund drops below)

### 2.4: Threshold Event Testing - Attendee Thresholds

**Test Event: Mystery Book Club (20 attendees threshold, FREE)**
- [ ] Check initial status: "0 / 20 attendees"
- [ ] Have 19 users RSVP/join
- [ ] Verify status still "threshold"
- [ ] Have 20th user RSVP
- [ ] Verify event status changes to "confirmed"
- [ ] Verify all attendees notified

### 2.5: Threshold Event Testing - Combined Thresholds

**Test Event: Coding Bootcamp (50 attendees AND $2,500)**
- [ ] Check initial status shows both metrics
- [ ] Purchase tickets to reach $2,500 but only 40 attendees
- [ ] Verify status still "threshold" (both conditions required)
- [ ] Add 10 more attendees
- [ ] Verify event status changes to "confirmed"
- [ ] Verify both conditions displayed correctly

### 2.6: Multi-Tier Ticket Testing

- [ ] Test purchasing different ticket tiers
- [ ] Verify pricing calculations with multiple tiers
- [ ] Test early bird ticket expiration
- [ ] Verify VIP vs regular ticket benefits displayed

### 2.7: Edge Cases & Error Handling

- [ ] Concurrent purchases (race conditions)
- [ ] Expired payment session
- [ ] Invalid payment method
- [ ] Network interruption during checkout
- [ ] Browser back button during checkout
- [ ] Session timeout during purchase

---

## PHASE 3: Production Test Preparation

**Objective:** Prepare for safe testing in production environment with Stripe test mode

### Tasks

- [ ] **Create manual test event in production**
  - Simple event with threshold
  - Use test Stripe keys
  - Document event URL

- [ ] **Configure Stripe test mode**
  - Verify `STRIPE_SECRET_KEY` uses `sk_test_*` prefix
  - Document test card numbers:
    - Success: `4242 4242 4242 4242`
    - Decline: `4000 0000 0000 0002`
    - Requires authentication: `4000 0025 0000 3155`

- [ ] **Set up monitoring**
  - Sentry alerts for checkout errors
  - Stripe dashboard monitoring
  - Log aggregation for purchase flow

- [ ] **Document rollback plan**
  - How to disable ticketing if issues arise
  - Customer refund process
  - Communication plan

---

## PHASE 4: Production Testing with Stripe Test Mode

**Objective:** Validate complete flow in production using Stripe test cards

### Test Matrix

| Scenario | Card | Expected Outcome |
|----------|------|------------------|
| Successful purchase | 4242 4242 4242 4242 | Order created, ticket issued |
| Declined card | 4000 0000 0000 0002 | Graceful error, inventory unchanged |
| Auth required | 4000 0025 0000 3155 | 3D Secure challenge, then success |
| Threshold met | Multiple test purchases | Event confirms when threshold reached |
| Webhook delivery | Any successful | Stripe webhook received and processed |

### Validation Checklist

- [ ] Stripe test payment processes correctly
- [ ] Order created in database
- [ ] Ticket inventory updated
- [ ] Confirmation email sent
- [ ] Stripe webhook received
- [ ] Admin dashboard shows order
- [ ] User can view ticket in account
- [ ] Threshold events change status correctly

---

## PHASE 5: Limited Production Release

**Objective:** Controlled rollout with real users and test cards

### Approach

- [ ] **Select pilot event**
  - Choose low-risk event (small capacity, non-critical)
  - Communicate test nature to attendees
  - Offer free alternative if issues arise

- [ ] **Invite limited test group (10-20 users)**
  - Friends/family/internal team
  - Provide test credit card numbers
  - Ask for detailed feedback

- [ ] **Monitor closely**
  - Watch for errors in real-time
  - Quick response to issues
  - Collect user feedback

- [ ] **Iterate and fix**
  - Address any bugs immediately
  - Refine UX based on feedback
  - Document learnings

- [ ] **Gradual expansion**
  - Once stable, enable for more events
  - Monitor metrics (conversion rate, errors)
  - Prepare for full public launch

---

## Test Scenarios Summary

### Available Threshold Events (Seeded)

1. **Revenue Threshold - Low ($1,125)**: Advanced Photography Workshop
2. **Revenue Threshold - Medium ($5,000)**: Community Garden Project
3. **Revenue Threshold - High ($10,000)**: Playground Fundraiser
4. **Attendee Threshold (20 people)**: Mystery Book Club (FREE)
5. **Combined Threshold (50 + $2,500)**: Coding Bootcamp

### Test User Accounts

All test accounts use password: `testpass123`

- `community_builder@example.com` - Phase 2 organizer (threshold events)
- `event_tester@example.com` - Phase 1 organizer (standard ticket sales)
- `admin@example.com` - Admin persona
- `demo@example.com` - Demo account
- `holden@gmail.com` - Personal account (password: `sawyer1234`)

---

## Success Criteria

### Phase 1 (Documentation)
- ✅ README updated with threshold event documentation
- ✅ Seeds verified working
- ✅ Test scenarios documented

### Phase 2 (Development E2E)
- ✅ All ticket purchase flows work
- ✅ Inventory management correct
- ✅ All 3 threshold types (revenue, attendee, combined) work correctly
- ✅ Edge cases handled gracefully

### Phase 3 (Production Prep)
- ✅ Production test event created
- ✅ Stripe test mode configured
- ✅ Monitoring in place
- ✅ Rollback plan documented

### Phase 4 (Production Testing)
- ✅ All test cards work as expected
- ✅ Webhooks processed correctly
- ✅ No errors in production logs
- ✅ Threshold mechanics work in production

### Phase 5 (Limited Release)
- ✅ Pilot event completed successfully
- ✅ Positive user feedback
- ✅ No critical bugs
- ✅ Ready for full public launch

---

## Related Files

- Seed files: `priv/repo/dev_seeds/features/ticketing/ticket_scenarios.exs`
- Event schema: `lib/eventasaurus_app/events/event.ex`
- Ticketing context: `lib/eventasaurus_app/ticketing.ex`
- README: `README.md` (needs update)

---

## Notes

- Existing go-karting events are **not** threshold events (they're confirmed events with regular ticket sales)
- Tram party event does **not** exist and needs to be created if required
- All threshold event logic is already implemented in the Event schema
- Playwright MCP server should be used for all E2E testing
- Test in development first before touching production

---

## Labels

`testing`, `ticketing`, `stripe`, `e2e`, `playwright`, `threshold-events`, `phase-1`, `phase-2`, `documentation`

## Assignees

TBD

## Milestone

Ticketing System GA Launch
