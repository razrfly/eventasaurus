# Ticketing Test Data Quick Reference

**Purpose**: Comprehensive ticketing test data for testing ticket purchases, threshold events, and payment flows across all pricing models and event types.

**Coverage**:
- **Phase 1**: 5 regular ticketed event scenarios (various price points and capacities)
- **Phase 2**: 5 threshold event scenarios (revenue, attendee count, and combined thresholds)
- **Additional**: 12+ professional ticketed events (go-karting, workshops, entertainment, fundraisers)

**URL Stability**: Event slugs are generated at seed time and remain constant until re-seed ✅

---

## 🎫 Test Organizer Credentials

All test accounts use password: `testpass123`

### Phase 1 Organizer (Regular Ticket Sales)
- **Email**: `event_tester@example.com`
- **Name**: Event Tester
- **Events**: Standard ticketed events with various price points

### Phase 2 Organizer (Threshold Events)
- **Email**: `community_builder@example.com`
- **Name**: Community Builder
- **Events**: Kickstarter-style threshold events

### Specialty Organizers
- **Go-Kart Racing**: `go_kart_racer@example.com`
- **Workshops**: `workshop_leader@example.com`
- **Entertainment**: `entertainment_host@example.com`
- **Fundraising**: `community_fundraiser@example.com`

### Test Buyers
- **Admin**: `admin@example.com` / `testpass123`
- **Demo User**: `demo@example.com` / `testpass123`
- **Dev Account**: `dev@example.com` / `testpass123`

> ⚠️ **Note**: These are test-only accounts for development. Never use real email/password combinations in seed data.

---

## 📊 PHASE 1: Regular Ticket Sales

### 1. Low-Price Event ($8) - Community Coffee Meetup
**Event**: http://localhost:4000/fawt6tlxee
**Organizer**: `event_tester@example.com`
**Status**: `:confirmed` (regular ticketed event)

**Tickets**:
- 💵 **General Admission** - $8.00 (100 available)
  - Includes coffee/tea and light refreshments

**Test Scenarios**:
- ✅ Small transaction processing
- ✅ High quantity inventory
- ✅ Simple single-tier pricing
- ✅ Guest checkout flow

---

### 2. High-Price Event ($299-$499) - Premium Tech Conference
**Event**: http://localhost:4000/r4fszax7op
**Organizer**: `event_tester@example.com`
**Status**: `:confirmed`

**Tickets**:
- 💼 **Standard Pass** - $299.00 (200 available)
  - Access to all sessions, expo hall, and networking events
- 👑 **VIP Pass** - $499.00 (50 available)
  - Standard Pass + Front-row seating, private Q&A, executive dinner

**Test Scenarios**:
- ✅ Large transaction amounts
- ✅ Two-tier pricing model
- ✅ VIP vs standard differentiation
- ✅ Payment processing for $299-$499 range

---

### 3. Multi-Tier Festival (5 tiers: $40-$449) - Summer Music Festival
**Event**: http://localhost:4000/pjgll7rqoj
**Organizer**: `event_tester@example.com`
**Status**: `:confirmed`

**Tickets** (5 different tiers):
1. 🅿️ **Premium Parking** - $40.00 (200 available)
2. 🎟️ **Early Bird General** - $89.00 (300 available) - Limited time!
3. 🎫 **General Admission** - $129.00 (800 available)
4. ⭐ **VIP Weekend Pass** - $249.00 (150 available)
5. 🌟 **Backstage Pass** - $449.00 (50 available)

**Test Scenarios**:
- ✅ Complex multi-tier pricing
- ✅ Early bird vs regular pricing
- ✅ Add-ons (parking separate from admission)
- ✅ Large capacity event (1,500 total tickets)
- ✅ Cart with multiple ticket types

---

### 4. Small Capacity Event (15 tickets) - Intimate Chef's Table Dinner
**Event**: http://localhost:4000/oz44qlhxr2
**Organizer**: `event_tester@example.com`
**Status**: `:confirmed`

**Tickets**:
- 🍽️ **Dinner Seat** - $185.00 (15 available only!)
  - Exclusive 7-course tasting menu with wine pairings

**Test Scenarios**:
- ✅ Very limited capacity
- ✅ Scarcity messaging
- ✅ "Only X tickets left" display
- ✅ Sold out state testing
- ✅ High-value single-tier pricing

---

### 5. Large Capacity Event (1,200 tickets) - Tech Careers Expo
**Event**: http://localhost:4000/w7oi1hvakp
**Organizer**: `event_tester@example.com`
**Status**: `:confirmed`

**Tickets** (3 tiers for different audiences):
1. 🎓 **Student Pass** - $5.00 (300 available)
2. 💼 **Job Seeker Pass** - $15.00 (800 available)
3. 🚀 **Premium Career Package** - $49.00 (100 available)

**Test Scenarios**:
- ✅ Very large capacity handling
- ✅ Low-price point ($5-$15)
- ✅ Discounted student pricing
- ✅ Volume ticket sales
- ✅ Three-tier audience segmentation

---

## 🎯 PHASE 2: Threshold Events (Kickstarter-Style)

### 1. Revenue Threshold ($1,125) - Advanced Photography Workshop
**Event**: http://localhost:4000/l44okmakzs
**Organizer**: `community_builder@example.com`
**Status**: `:threshold` 🎯
**Threshold Type**: `revenue`
**Threshold Amount**: $1,125 ($112,500 cents)

**Tickets**:
- 📸 **Workshop Seat** - $75.00 (20 available)
  - Full-day workshop with professional photographer

**Math**: Need 15 tickets sold ($75 × 15 = $1,125) to meet threshold

**Test Scenarios**:
- ✅ Revenue progress tracking ($0 → $1,125)
- ✅ Threshold meter display
- ✅ Status change: `:threshold` → `:confirmed` when goal met
- ✅ "Almost there!" messaging at $1,050 (14 tickets)
- ✅ Confirmation emails when threshold met
- ✅ Refund scenario if threshold not met by deadline

**Critical Testing Points**:
```
$0 / $1,125 (0%)       → Just launched
$750 / $1,125 (67%)    → 10 tickets sold, making progress
$1,050 / $1,125 (93%)  → 14 tickets sold, almost there!
$1,125 / $1,125 (100%) → 15 tickets sold, CONFIRMED! ✅
```

---

### 2. Revenue Threshold ($2,500) - Intro to Web Development Bootcamp
**Event**: http://localhost:4000/14omq8jfil
**Organizer**: `community_builder@example.com`
**Status**: `:threshold` 🎯
**Threshold Type**: `both` (Combined threshold!)
**Threshold Amount**: $2,500 ($250,000 cents)
**Threshold Count**: 50 attendees

**Tickets**:
- 💻 **Bootcamp Ticket** - $50.00 (100 available)
  - 2-day intensive web development bootcamp

**Math**: Need BOTH conditions:
- 50 attendees enrolled (50 tickets sold)
- $2,500 total revenue (50 × $50 = $2,500)

**Test Scenarios**:
- ✅ Combined threshold display (both metrics shown)
- ✅ Dual progress tracking
- ✅ Testing partial fulfillment (e.g., 40 tickets = $2,000 but only 40 people)
- ✅ Event only confirms when BOTH conditions met
- ✅ Complex threshold logic

**Critical Testing Points**:
```
40 tickets ($2,000) + 40 people → Still threshold (need 50 people)
50 tickets ($2,500) + 50 people → CONFIRMED! ✅ (both met)
```

---

### 3. Attendee Threshold (20 people) - Mystery Book Club Launch
**Event**: http://localhost:4000/sn2xarqgnk
**Organizer**: `community_builder@example.com`
**Status**: `:threshold` 🎯
**Threshold Type**: `attendee_count`
**Threshold Count**: 20 people
**Price**: **FREE** (no tickets, just RSVPs)

**Test Scenarios**:
- ✅ Free event with threshold (no payment processing)
- ✅ RSVP tracking instead of ticket sales
- ✅ Attendee count progress (0 / 20 people)
- ✅ Social proof ("19 people interested, be #20!")
- ✅ Status change when 20th person RSVPs
- ✅ Free threshold event flow

**Critical Testing Points**:
```
0 / 20 people (0%)    → Just launched
15 / 20 people (75%)  → Getting close!
19 / 20 people (95%)  → One more needed!
20 / 20 people (100%) → CONFIRMED! ✅
```

---

## 🏎️ Professional Ticketed Events

### Go-Kart Racing Events
**Organizer**: `go_kart_racer@example.com`

#### Grand Prix Go-Kart Championship
**Event**: http://localhost:4000/k8siixrujz
**Status**: `:confirmed`

**Tickets** (3 tiers):
1. 🎟️ **Early Bird Special** - $35.00 (15 available)
2. 🏁 **General Admission** - $45.00 (50 available)
3. 👑 **VIP Racer** - $85.00 (20 available)

**Test Scenarios**:
- ✅ Sports event ticketing
- ✅ Three-tier racing packages
- ✅ Early bird vs regular pricing

---

## 🔧 Testing Commands

### Seed Database with Stable Events
```bash
# Clean and reseed with all ticketing scenarios
mix seed.clean && mix seed.dev

# Verify Phase 1 events created
open http://localhost:4000/fawt6tlxee  # Coffee Meetup
open http://localhost:4000/r4fszax7op  # Tech Conference
open http://localhost:4000/pjgll7rqoj  # Music Festival

# Verify Phase 2 threshold events created
open http://localhost:4000/l44okmakzs  # Photography Workshop (revenue)
open http://localhost:4000/14omq8jfil  # Coding Bootcamp (combined)
open http://localhost:4000/sn2xarqgnk  # Book Club (attendee count)
```

### Quick Test All Ticketing Scenarios
```bash
# Phase 1: Regular Ticket Sales (5 events)
open http://localhost:4000/fawt6tlxee && \
open http://localhost:4000/r4fszax7op && \
open http://localhost:4000/pjgll7rqoj && \
open http://localhost:4000/oz44qlhxr2 && \
open http://localhost:4000/w7oi1hvakp

# Phase 2: Threshold Events (3 events)
open http://localhost:4000/l44okmakzs && \
open http://localhost:4000/14omq8jfil && \
open http://localhost:4000/sn2xarqgnk
```

### Database Queries for Testing
```bash
# Check all threshold events
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT id, title, slug, status, threshold_type, threshold_revenue_cents, threshold_count \
   FROM events WHERE status = 'threshold' AND deleted_at IS NULL;"

# Check tickets for specific event
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT t.title, t.base_price_cents, t.quantity FROM tickets t \
   JOIN events e ON t.event_id = e.id WHERE e.slug = 'l44okmakzs';"

# Check threshold progress (after purchases)
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT e.title, e.threshold_revenue_cents, SUM(o.total_cents) as current_revenue \
   FROM events e LEFT JOIN orders o ON e.id = o.event_id \
   WHERE e.status = 'threshold' GROUP BY e.id, e.title, e.threshold_revenue_cents;"
```

---

## 📊 Coverage Matrix

### Phase 1: Regular Ticket Sales

| Scenario | Price Range | Capacity | Tiers | Status |
|----------|-------------|----------|-------|--------|
| Coffee Meetup | $8 | 100 | 1 | ✅ |
| Tech Conference | $299-$499 | 250 | 2 | ✅ |
| Music Festival | $40-$449 | 1,500 | 5 | ✅ |
| Chef's Table | $185 | 15 | 1 | ✅ |
| Career Expo | $5-$49 | 1,200 | 3 | ✅ |

**Total Phase 1**: 5/5 scenarios covered (100% ✅)

### Phase 2: Threshold Events

| Scenario | Type | Threshold Amount | Tickets/RSVPs | Status |
|----------|------|------------------|---------------|--------|
| Photography Workshop | Revenue | $1,125 | $75 × 20 | ✅ |
| Coding Bootcamp | Both | $2,500 + 50 people | $50 × 100 | ✅ |
| Book Club | Attendee Count | 20 people | FREE | ✅ |

**Total Phase 2**: 3/3 threshold types covered (100% ✅)

---

## 🎯 Use Cases

### Testing Ticket Purchase Flow
1. **Navigate to event**: http://localhost:4000/fawt6tlxee
2. **Select ticket tier**: Click "Buy Tickets" → Select quantity
3. **Checkout**: Complete Stripe test payment (card: `4242 4242 4242 4242`)
4. **Verify**: Check order confirmation, ticket inventory decreases

### Testing Threshold Progress
1. **Start at zero**: http://localhost:4000/l44okmakzs (Photography Workshop)
2. **Purchase tickets**: Buy 10 tickets ($750 total)
3. **Check progress**: Verify display shows "$750 / $1,125 (67%)"
4. **Reach threshold**: Buy 5 more tickets ($375)
5. **Verify confirmation**: Event status changes to `:confirmed`

### Testing Failed Payments
1. **Navigate to event**: Any ticketed event
2. **Select ticket**: Add to cart
3. **Use declining card**: `4000 0000 0000 0002`
4. **Verify graceful failure**: Error message, inventory unchanged
5. **Retry with valid card**: `4242 4242 4242 4242` → Success

### Testing Guest Checkout
1. **Open incognito**: Clear browser cookies or use incognito mode
2. **Navigate to event**: http://localhost:4000/fawt6tlxee
3. **Buy ticket as guest**: Enter email, complete checkout
4. **Verify guest account**: Check user created in database
5. **Verify order**: Guest receives confirmation email

### Testing Sold Out State
1. **Select small capacity event**: http://localhost:4000/oz44qlhxr2 (15 tickets)
2. **Purchase all tickets**: Buy all 15 dinner seats
3. **Verify sold out**: "Sold Out" badge appears
4. **Verify button disabled**: Purchase button no longer clickable

---

## 🐛 Debugging Tips

### Event Not Found
```bash
# Check if event exists
curl http://localhost:4000/fawt6tlxee

# Query database directly
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT * FROM events WHERE slug = 'fawt6tlxee';"
```

### Threshold Not Updating
```bash
# Check orders for event
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT * FROM orders WHERE event_id = (SELECT id FROM events WHERE slug = 'l44okmakzs');"

# Check if threshold logic running
# Look for EventStateMachine or threshold calculation logs
tail -f log/dev.log | grep -i threshold
```

### Stripe Payment Failing
- **Test Mode Keys**: Verify `STRIPE_SECRET_KEY` starts with `sk_test_`
- **Webhook Setup**: Check webhook endpoint configured (for threshold confirmations)
- **Test Cards**: Use official Stripe test cards
  - Success: `4242 4242 4242 4242`
  - Decline: `4000 0000 0000 0002`
  - Requires Auth: `4000 0025 0000 3155`

### Tickets Not Decreasing
```bash
# Check current ticket inventory
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT t.title, t.quantity, COUNT(oi.id) as sold \
   FROM tickets t LEFT JOIN order_items oi ON t.id = oi.ticket_id \
   WHERE t.event_id = (SELECT id FROM events WHERE slug = 'fawt6tlxee') \
   GROUP BY t.id, t.title, t.quantity;"
```

---

## 📋 Stripe Test Cards

### Successful Payments
- **Basic success**: `4242 4242 4242 4242`
- **CVC**: Any 3 digits (e.g., `123`)
- **Expiry**: Any future date (e.g., `12/28`)
- **ZIP**: Any 5 digits (e.g., `12345`)

### Testing Declines
- **Generic decline**: `4000 0000 0000 0002`
- **Insufficient funds**: `4000 0000 0000 9995`
- **Lost card**: `4000 0000 0000 9987`
- **Stolen card**: `4000 0000 0000 9979`

### Testing Authentication
- **Requires authentication**: `4000 0025 0000 3155`
  - Triggers 3D Secure / SCA flow
  - Use this to test authentication challenges

---

## 🎬 Real-World Testing Scenarios

### Scenario 1: Regular Ticket Purchase (Logged-in User)
```
1. Login as demo@example.com
2. Navigate to Coffee Meetup (http://localhost:4000/fawt6tlxee)
3. Click "Buy Tickets"
4. Select quantity: 2 tickets
5. Proceed to checkout
6. Enter card: 4242 4242 4242 4242
7. Complete purchase
8. Verify: Order confirmation, email sent, tickets in account
```

### Scenario 2: Threshold Event (Revenue Goal)
```
1. Navigate to Photography Workshop (http://localhost:4000/l44okmakzs)
2. Verify initial state: "$0 / $1,125 (0%)"
3. Purchase 10 tickets ($750 total)
4. Verify progress: "$750 / $1,125 (67%)"
5. Purchase 5 more tickets ($375 total)
6. Verify CONFIRMED: "$1,125 / $1,125 (100%)" + Status: confirmed
7. Verify: All 15 ticket holders receive confirmation email
```

### Scenario 3: Guest Checkout
```
1. Open incognito window
2. Navigate to Tech Conference (http://localhost:4000/r4fszax7op)
3. Buy Standard Pass ($299)
4. Enter guest email: test@example.com
5. Complete Stripe checkout
6. Verify: Guest account created, order confirmed, email sent
```

### Scenario 4: Failed Payment Protection
```
1. Navigate to Music Festival (http://localhost:4000/pjgll7rqoj)
2. Add General Admission ticket to cart
3. Check initial inventory: 800 tickets available
4. Use declining card: 4000 0000 0000 0002
5. Payment fails
6. Verify: Inventory still 800 (unchanged!)
7. Retry with valid card: 4242 4242 4242 4242
8. Verify: Purchase succeeds, inventory now 799
```

---

## 📝 Notes

- **Slug Stability**: Event slugs are generated at seed time and change with each re-seed
- **Password**: All test organizer accounts use `testpass123`
- **Stripe Mode**: Development uses test keys (`sk_test_*`)
- **Threshold Events**: Status `:threshold` until conditions met, then auto-changes to `:confirmed`
- **Email Confirmations**: Check `log/dev.log` for email preview links in development

---

## 🔗 Related Documentation

- **Polling Test Data**: `priv/repo/dev_seeds/POLLING_TEST_DATA.md`
- **Seed README**: `priv/repo/dev_seeds/README.md`
- **MVP Testing Issue**: #2399 (Threshold Ticket Sales MVP)
- **Comprehensive Testing Plan**: #2397 (Full production rollout plan)
- **Ticketing Context**: `lib/eventasaurus_app/ticketing.ex`
- **Event Schema**: `lib/eventasaurus_app/events/event.ex`

---

**Last Updated**: January 2025 (Phase 1 & 2 Complete)
**Seed Files**:
- `priv/repo/dev_seeds/features/ticketing/ticket_scenarios.exs`
- `priv/repo/dev_seeds/features/ticketing/ticketed_events.exs`
