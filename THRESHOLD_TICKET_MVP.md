# Threshold Ticket Sales MVP Testing

**Parent Issue:** #2397 (Comprehensive Testing Plan)

## Goal

Test ONE threshold event end-to-end to validate threshold ticket sales work correctly before rolling out go-karts and tram party events in production.

---

## Test Event: Community Garden Project

**Why this event:**
- Revenue threshold: $5,000 (realistic, testable amount)
- Multiple ticket tiers ($10, $25, $50, $100, $500)
- Similar structure to go-karts/tram party (ticketed activity with minimum viability threshold)
- Already seeded and ready to test

**Event Details:**
- **Organizer:** `community_builder@example.com` / `testpass123`
- **Threshold Type:** Revenue
- **Threshold Amount:** $5,000
- **Ticket Tiers:** 5 tiers from $10 to $500
- **Status:** Should be `:threshold` until $5k raised

**Seed Command:**
```bash
mix ecto.reset
mix seed.dev
# This creates the Community Garden event via Phase 2 seeds
```

---

## Critical Test Scenarios

### 1. Verify Event Setup
- [ ] Event exists with status `:threshold`
- [ ] Threshold displays: "$0 / $5,000"
- [ ] All 5 ticket tiers are available
- [ ] Purchase buttons are enabled

### 2. Ticket Purchase Flow (Logged-in User)
- [ ] Navigate to Community Garden event page
- [ ] Select ticket tier (e.g., $50 "Green Thumb Champion")
- [ ] Add to cart
- [ ] Complete checkout with test Stripe card
- [ ] Verify order confirmation
- [ ] Verify ticket inventory decreases

### 3. Threshold Progress Tracking
- [ ] Purchase $500 ticket → Verify progress shows "$500 / $5,000 (10%)"
- [ ] Purchase more tickets to reach $4,900
- [ ] Verify status still shows `:threshold`
- [ ] Purchase final tickets to exceed $5,000
- [ ] **Critical:** Verify event status changes to `:confirmed`
- [ ] Verify all ticket holders receive confirmation emails

### 4. Failed Payment Handling
- [ ] Start ticket purchase
- [ ] Use declining test card: `4000 0000 0000 0002`
- [ ] Verify payment fails gracefully
- [ ] **Critical:** Verify ticket quantity NOT reduced
- [ ] Verify threshold progress NOT updated
- [ ] Verify ticket still available for purchase

### 5. Guest User Purchase
- [ ] Open event page in incognito/logged out
- [ ] Select ticket and proceed to checkout
- [ ] Enter email and payment details
- [ ] Complete purchase
- [ ] Verify guest account created
- [ ] Verify ticket purchased and counted toward threshold

---

## Playwright MCP Testing Workflow

### Setup
```bash
# Terminal 1: Start dev server
mix phx.server

# Terminal 2: Ready for Playwright MCP commands
```

### Test Execution (using MCP tools)
1. `mcp__playwright__browser_navigate` → Community Garden event page
2. `mcp__playwright__browser_snapshot` → Verify threshold UI
3. `mcp__playwright__browser_click` → Select ticket tier
4. `mcp__playwright__browser_fill_form` → Enter checkout details
5. `mcp__playwright__browser_type` → Enter test card `4242 4242 4242 4242`
6. `mcp__playwright__browser_click` → Complete purchase
7. `mcp__playwright__browser_snapshot` → Verify confirmation
8. Navigate back and verify threshold updated

---

## Success Criteria

✅ **MVP Complete When:**
1. Can purchase tickets as logged-in user
2. Can purchase tickets as guest user
3. Threshold progress updates correctly after each purchase
4. Event status changes to `:confirmed` when threshold met
5. Failed payments don't reduce inventory or update threshold
6. All ticket holders receive confirmation when threshold met

---

## Production Rollout Prep

Once MVP testing passes:

### Phase 1: Create Real Events
- [ ] Create "Go-Kart Grand Prix" threshold event in production
  - Combined threshold: 30 attendees + $1,500 revenue
  - Ticket price: $50
- [ ] Create "Tram Party Experience" threshold event in production
  - Combined threshold: 50 attendees + $2,500 revenue
  - Ticket price: $50

### Phase 2: Test in Production (Stripe Test Mode)
- [ ] Configure Stripe test keys in production
- [ ] Test complete purchase flow with test cards
- [ ] Verify webhooks work correctly
- [ ] Verify threshold mechanics in production environment

### Phase 3: Limited Beta Release
- [ ] Send to 5-10 friends/family with test cards
- [ ] Monitor for issues
- [ ] Collect feedback
- [ ] Fix any bugs

### Phase 4: Real Launch
- [ ] Switch to live Stripe keys
- [ ] Launch go-karts event
- [ ] Launch tram party event
- [ ] Monitor conversion and errors

---

## Quick Reference

### Test Stripe Cards
- **Success:** `4242 4242 4242 4242`
- **Decline:** `4000 0000 0000 0002`
- **Requires Auth:** `4000 0025 0000 3155`

### Test Accounts
- **Organizer:** `community_builder@example.com` / `testpass123`
- **Regular User:** `demo@example.com` / `testpass123`
- **Your Account:** `holden@gmail.com` / `sawyer1234`

### Important Files
- Seeds: `priv/repo/dev_seeds/features/ticketing/ticket_scenarios.exs`
- Event Schema: `lib/eventasaurus_app/events/event.ex`
- Ticketing Context: `lib/eventasaurus_app/ticketing.ex`

---

## Next Steps

1. **Run seeds** to create Community Garden event
2. **Start Playwright MCP testing** - go through 5 critical scenarios
3. **Document any issues** found during testing
4. **Fix bugs** if any are discovered
5. **Move to production testing** once dev testing passes
6. **Create real events** (go-karts, tram party)
7. **Launch to beta users**

---

## Labels
`testing`, `high-priority`, `feature`, `documentation`

## Related
- Parent issue: #2397 (Full testing plan)
