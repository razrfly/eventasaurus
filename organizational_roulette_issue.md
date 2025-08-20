# Feature Request: Organizational Roulette - Gamified Group Travel/Event Planning

## 🎰 Executive Summary

Create a gamified group event planning feature where participants contribute to a shared pool for an upcoming vacation/event through monthly subscriptions, with an anonymous organizer managing the details and a roulette-style reveal of the destination.

## 🎯 Core Concept

Transform group event planning into an exciting, subscription-based experience where:
- A fixed group of friends commits to an upcoming trip/event
- Everyone contributes monthly to build up the event fund
- One member is secretly designated as the organizer
- The destination/details are revealed in a fun, gamified way
- The anticipation and mystery add excitement to the planning process

## 🚀 Key Features Required

### 1. Group Formation & Locking
- **Closed Group Creation**: Ability to create invite-only groups with a fixed member list
- **Member Commitment**: Members must explicitly opt-in/commit to participation
- **Group Lock Mechanism**: Once locked, no new members can join (only leave with penalties/rules)
- **Minimum/Maximum Participants**: Set constraints (e.g., min 4, max 12 people)

### 2. Anonymous Organizer System
- **Secret Assignment**: Randomly or manually assign one member as the organizer
- **Identity Masking**: Hide organizer identity from other participants
- **Privileged Actions**: Organizer can make decisions without revealing identity
- **Optional Reveal**: Choose when/if to reveal organizer identity (before, during, or after event)

### 3. Subscription & Payment Collection
- **Monthly Subscriptions**: Automated recurring payments from all participants
- **Payment Goals**: Set total fundraising targets with visual progress tracking
- **Milestone Rewards**: Unlock features/reveals as funding milestones are reached
- **Payment Flexibility**:
  - Fixed monthly amounts
  - Variable contributions based on member preferences
  - One-time larger payments option
- **Escrow/Hold System**: Funds held until event confirmation
- **Refund Rules**: Clear policies for cancellations/dropouts

### 4. Gamification Elements
- **Mystery Destination**: Location revealed through clues, puzzles, or countdown
- **Voting Rounds**: 
  - Initial preference polls (beach vs mountain, domestic vs international)
  - Elimination rounds for destination options
  - Activity preference voting
- **Progress Unlocks**:
  - 25% funded: Reveal continent/region
  - 50% funded: Reveal country
  - 75% funded: Reveal city
  - 100% funded: Full itinerary reveal
- **Engagement Mechanics**:
  - Daily/weekly clues about the destination
  - Mini-games or trivia to earn hints
  - Leaderboard for most engaged participants
- **Surprise Elements**: Random bonuses, mystery activities, surprise upgrades

### 5. Enhanced Polling System
- **Anonymous Voting**: Hide who voted for what
- **Weighted Voting**: Give organizer more weight or veto power
- **Preference Ranking**: Rank multiple options instead of single choice
- **Conditional Polls**: "If we go to X, would you prefer Y or Z?"

## 🏗 Implementation Leveraging Existing Features

### Current Features We Can Build On:
1. **Groups System** (`EventasaurusApp.Groups`)
   - Already has group creation, membership, and roles
   - Need: Locking mechanism, subscription tracking

2. **Polling System** (`EventasaurusApp.Events.Poll`)
   - Has voting, deadlines, and phase management
   - Need: Anonymous voting option, weighted voting

3. **Ticketing/Payment** (`EventasaurusApp.Ticketing`, Stripe integration)
   - Has payment processing and order management
   - Need: Subscription model, payment goals, escrow

4. **Event State Machine** (`EventasaurusApp.EventStateMachine`)
   - Has status transitions and thresholds
   - Need: New states for roulette events

5. **Privacy Settings** (in polls)
   - Has some anonymity features
   - Need: Expand for organizer anonymity

## 📊 Database Schema Additions

```elixir
# New table: roulette_events
- group_id (locked group)
- organizer_user_id (hidden)
- subscription_amount_cents
- goal_amount_cents
- current_amount_cents
- billing_day
- reveal_strategy (progressive/all_at_once/custom)
- reveal_milestones (jsonb)
- status (planning/collecting/revealing/confirmed/completed)

# New table: roulette_subscriptions
- roulette_event_id
- user_id
- monthly_amount_cents
- status (active/paused/cancelled)
- last_payment_date
- next_payment_date

# New table: roulette_reveals
- roulette_event_id
- reveal_type (clue/milestone/final)
- content
- unlocked_at
- unlock_condition

# Modifications to existing:
- groups: add is_locked, lock_date, subscription_enabled fields
- polls: add is_anonymous, weight_multipliers fields
```

## 🎮 User Journey

1. **Initiation**: User creates a "Roulette Event" and invites friends
2. **Commitment**: Friends join and commit to monthly contribution
3. **Lock-in**: Group locks, organizer secretly assigned
4. **Collection Phase**: Monthly payments collected, progress tracked
5. **Engagement**: Polls, clues, and games keep participants engaged
6. **Progressive Reveal**: Details unveiled as milestones are hit
7. **Final Reveal**: Full destination/plans revealed
8. **Execution**: Trip happens with accumulated funds
9. **Completion**: Memories shared, potentially plan next roulette

## 💡 Unique Selling Points

1. **Anticipation Building**: The mystery creates excitement over months
2. **Financial Commitment**: Regular payments ensure serious participation
3. **Social Bonding**: Shared journey brings group closer
4. **Surprise Element**: Even organizer can add surprises for themselves
5. **Reduced Planning Friction**: One person handles logistics secretly

## 🔒 Security & Trust Considerations

- **Escrow Protection**: Funds protected until event confirmation
- **Transparency Options**: Show total collected without revealing individual contributions
- **Audit Trail**: Full payment history available to all members
- **Dispute Resolution**: Clear rules for conflicts or cancellations
- **Organizer Accountability**: Post-event reveal with expense breakdown

## 📈 Monetization Opportunities

1. **Platform Fee**: Small percentage of collected funds
2. **Premium Features**: 
   - Custom reveal animations
   - Advanced gamification options
   - Professional organizer assistance
3. **Partner Integrations**: Travel agencies, hotels, activity providers
4. **Insurance Options**: Trip cancellation protection

## 🚦 Implementation Phases

### Phase 1: MVP (2-3 weeks)
- Locked groups with subscription setup
- Basic anonymous organizer assignment
- Simple payment collection (no recurring initially)
- Basic milestone-based reveals

### Phase 2: Gamification (2-3 weeks)
- Progressive reveal system
- Clues and hints mechanism
- Enhanced anonymous polling
- Engagement tracking

### Phase 3: Full Automation (3-4 weeks)
- Recurring subscription payments
- Automated milestone unlocks
- Complex reveal strategies
- Mini-games and activities

### Phase 4: Polish & Scale (2-3 weeks)
- Advanced gamification
- Partner integrations
- Mobile app optimization
- Analytics and insights

## 🎯 Success Metrics

- **Activation Rate**: % of groups that lock and start collecting
- **Completion Rate**: % of roulette events that reach their goal
- **Engagement Score**: Average interactions per user per week
- **Payment Success Rate**: % of successful monthly collections
- **User Satisfaction**: Post-event NPS scores
- **Viral Coefficient**: How many new groups each successful event creates

## 🤔 Open Questions

1. **Legal/Regulatory**: Do we need money transmitter licenses for holding funds?
2. **International**: How to handle multi-currency groups?
3. **Organizer Selection**: Random, elected, or volunteer?
4. **Refund Policy**: What happens if someone needs to drop out?
5. **Maximum Duration**: Should we limit how long collection can run?
6. **Destination Restrictions**: How to handle if revealed destination doesn't work for someone?

## 💭 Alternative Variations

1. **Mystery Dinner Club**: Monthly restaurant roulette in the same city
2. **Concert Roulette**: Save up for mystery concert/festival
3. **Adventure Roulette**: Surprise outdoor activities
4. **Staycation Roulette**: Local mystery experiences
5. **Gift Roulette**: Group saves to surprise one member

## 🔗 Related Issues/Features

- Enhanced group privacy settings
- Subscription payment infrastructure
- Advanced polling mechanisms
- Notification system for reveals
- Mobile app support for engagement features

---

**Labels:** `enhancement`, `feature-request`, `gamification`, `payments`, `high-priority`

**Assignee:** TBD

**Milestone:** Q1 2025 - Roulette Launch