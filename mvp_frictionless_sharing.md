# 🎯 MVP: Frictionless Event Sharing & RSVP System

## Problem Statement

Users face significant friction when organizing events with friends:

1. **Sharing Friction**: Manual copy-paste links, email addresses required
2. **Response Friction**: Facebook's "going vs interested" problem - unclear commitment 
3. **Mobile Gap**: No native iOS/Android apps for quick sharing
4. **Communication Barriers**: Email-only, no SMS/WhatsApp integration
5. **Discovery Issues**: Friends don't see events in their natural communication flows

## Solution Overview

Create a **minimal-friction event sharing system** that maximizes actual attendance through:
- One-click sharing to multiple channels (SMS, WhatsApp, social)
- Three-tier RSVP system (Yes/Maybe/No) avoiding Facebook's "interested" trap
- Mobile-first experience with native app capabilities
- Smart contact integration and suggested invitees
- Rich sharing previews and social proof

## MVP Requirements

### 🎯 Phase 1: Enhanced Web Sharing (2-3 weeks)

#### 1.1 Multi-Channel Sharing System
**Backend (`lib/eventasaurus_web/live/components/`):**
- [ ] New `SharingModalComponent` with multiple sharing options
- [ ] Add phone number field to `User` schema
- [ ] SMS integration service (Twilio/similar)
- [ ] WhatsApp sharing via URL schemes
- [ ] Social sharing (Twitter, Instagram, Facebook) with Open Graph tags

**Files to modify:**
- `lib/eventasaurus_app/accounts/user.ex` - Add phone field
- `lib/eventasaurus/emails.ex` - Add SMS notification service
- `lib/eventasaurus_web/components/` - New sharing modal
- `priv/repo/migrations/` - Add phone number migration

#### 1.2 Simplified RSVP System
**Replace current participant status with:**
- [ ] **"Going"** (firm commitment)
- [ ] **"Maybe"** (tentative, better than "interested")
- [ ] **"Can't make it"** (clear no)

**Files to modify:**
- `lib/eventasaurus_app/events/event_participant.ex` - Update status enum
- `lib/eventasaurus_web/live/components/participant_status_*.ex` - Update UI
- Database migration for status field

#### 1.3 One-Click RSVP Links
**Backend:**
- [ ] Generate secure RSVP tokens for each invitation
- [ ] Direct RSVP endpoint `/rsvp/:token/:status`
- [ ] Auto-account creation for new users

**Files to create:**
- `lib/eventasaurus_web/controllers/rsvp_controller.ex`
- `lib/eventasaurus_app/events/rsvp_token.ex` (schema)

### 🎯 Phase 2: Smart Contact Integration (2-3 weeks)

#### 2.1 Enhanced Friend Suggestions
**Extend existing `GuestInvitations` system:**
- [ ] Phone contact import (with permission)
- [ ] Cross-reference with app users by email/phone
- [ ] Suggest based on mutual connections
- [ ] Recent chat participants (if SMS integration allows)

**Files to modify:**
- `lib/eventasaurus_app/guest_invitations.ex` - Add contact matching
- New service: `lib/eventasaurus_app/services/contact_service.ex`

#### 2.2 Smart Invitation Templates
**Context-aware messages:**
- [ ] Different templates for movies vs. parties vs. casual hangouts  
- [ ] Time-sensitive language ("this weekend", "tomorrow")
- [ ] Group size messaging ("just us" vs. "big group")

**Files to modify:**
- `lib/eventasaurus/emails.ex` - Template variants
- `lib/eventasaurus_web/components/guest_invitation_modal.ex` - Template picker

### 🎯 Phase 3: Mobile Experience (4-6 weeks)

#### 3.1 Progressive Web App (PWA) Enhancement
**Immediate mobile improvements:**
- [ ] Service worker for offline capability
- [ ] Native sharing API integration
- [ ] Push notifications (web push)
- [ ] Contact picker API support
- [ ] Install prompts for home screen

**Files to create/modify:**
- `assets/js/service-worker.js`
- `assets/js/push-notifications.js`
- `lib/eventasaurus_web/live/` - PWA-optimized layouts

#### 3.2 Native App Strategy
**MVP Mobile Apps (React Native or Flutter):**
- [ ] Event creation optimized for mobile
- [ ] Contact sharing integration
- [ ] Native notifications
- [ ] Deep linking to events
- [ ] Camera integration for event photos

**New directories:**
- `/mobile/ios/` - iOS app
- `/mobile/android/` - Android app
- `/mobile/shared/` - Shared components

### 🎯 Phase 4: Viral & Engagement Features (2-3 weeks)

#### 4.1 Social Proof & Viral Mechanics
- [ ] "X friends are going" in sharing previews
- [ ] Event discovery feed for friends' public events
- [ ] Activity notifications ("Sarah just joined your movie night")
- [ ] Share event updates to attendees

#### 4.2 Polling Integration Enhancement
**Extend existing polling system:**
- [ ] Quick poll creation from invites ("What time works?")
- [ ] Location polling with map integration
- [ ] Activity polling (movie options, restaurant choices)

**Files to modify:**
- `lib/eventasaurus/events/poll.ex` - New poll types
- Existing poll components - Enhanced for sharing context

## Technical Implementation Plan

### Database Changes
```sql
-- Add to users table
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN phone_verified BOOLEAN DEFAULT FALSE;

-- RSVP tokens
CREATE TABLE rsvp_tokens (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT REFERENCES events(id),
  invitee_email VARCHAR(255),
  invitee_phone VARCHAR(20), 
  token VARCHAR(64) UNIQUE,
  expires_at TIMESTAMP,
  used_at TIMESTAMP,
  inserted_at TIMESTAMP DEFAULT NOW()
);

-- Enhanced participant status
ALTER TABLE event_participants 
  ALTER COLUMN status TYPE VARCHAR(20),
  ADD CONSTRAINT valid_status CHECK (status IN ('going', 'maybe', 'not_going', 'pending'));
```

### New Services Architecture
```
lib/eventasaurus_web/services/
├── sms_service.ex              # SMS notifications
├── contact_service.ex          # Contact import/matching  
├── sharing_service.ex          # Multi-channel sharing
├── rsvp_service.ex            # Token-based RSVP
└── notification_service.ex     # Push notifications
```

### API Endpoints
```
POST /api/events/:id/share      # Generate sharing links
POST /api/events/:id/invite     # Send invitations
GET  /rsvp/:token/:status       # One-click RSVP  
POST /api/contacts/import       # Import contacts
GET  /api/contacts/suggestions  # Get friend suggestions
```

## Success Metrics

### Primary KPIs
- **Invitation Conversion**: % of invites that result in RSVPs
- **Actual Attendance**: % of "going" responses that actually attend
- **Sharing Velocity**: Time from event creation to first invite sent
- **Viral Coefficient**: Avg new users per existing user
- **Mobile Usage**: % of interactions on mobile devices

### Target Goals (3 months post-launch)
- 80%+ invitation response rate (vs current ~40%)
- 90%+ "going" → actual attendance rate
- <30 seconds event creation to first invite
- 1.5+ viral coefficient for active users
- 70%+ mobile usage

## Implementation Priority

### Week 1-2: Foundation
1. Add phone numbers to user accounts
2. SMS service integration
3. Enhanced sharing modal

### Week 3-4: RSVP System
1. Simplified RSVP statuses
2. One-click RSVP tokens
3. Direct response links

### Week 5-6: Smart Suggestions
1. Contact import system
2. Enhanced friend matching
3. Context-aware templates

### Week 7-8: Mobile PWA
1. Service worker setup
2. Native sharing integration
3. Push notifications

### Week 9-12: Native Apps
1. React Native setup
2. Core sharing features
3. App store deployment

## Risk Mitigation

### Technical Risks
- **SMS costs**: Start with WhatsApp/social sharing, add SMS gradually
- **Contact privacy**: Explicit permissions, GDPR compliance
- **Mobile complexity**: Start with PWA, native apps as phase 2

### Product Risks  
- **Over-engineering**: Ship basic sharing first, iterate based on usage
- **Platform dependencies**: Avoid deep WhatsApp integration initially
- **User adoption**: A/B test invitation templates and flows

## Dependencies

### External Services
- **SMS Provider**: Twilio or similar ($$)
- **Push Notifications**: OneSignal or Firebase ($)
- **Contact APIs**: Platform-specific contact pickers
- **Social APIs**: Open Graph, Twitter Cards

### Internal Dependencies
- Current user authentication system ✅
- Existing event/participant models ✅
- LiveView real-time updates ✅
- Email infrastructure ✅

---

## Acceptance Criteria

### Phase 1 Complete When:
- [ ] Users can share events via SMS, WhatsApp, and social media
- [ ] RSVP system uses Going/Maybe/Not Going (no "Interested")
- [ ] One-click RSVP links work without requiring account creation
- [ ] Phone numbers added to user profiles with verification

### Phase 2 Complete When:
- [ ] Contact import works with permission flow
- [ ] Friend suggestions include phone contacts
- [ ] Invitation templates adapt to event context
- [ ] SMS notifications sent successfully

### Phase 3 Complete When:
- [ ] PWA installs on mobile devices
- [ ] Native sharing works on mobile
- [ ] Push notifications functional
- [ ] Mobile apps submitted to app stores

### Phase 4 Complete When:
- [ ] Social proof visible in sharing previews
- [ ] Event discovery feed shows friends' events
- [ ] Polling integration works from invites
- [ ] Activity notifications active

## Definition of Done

- [ ] All acceptance criteria met
- [ ] Unit tests written for new functionality
- [ ] Integration tests cover sharing workflows
- [ ] Performance tested under load
- [ ] Security reviewed for contact/SMS features
- [ ] Documentation updated
- [ ] Analytics tracking implemented
- [ ] User feedback collected and addressed