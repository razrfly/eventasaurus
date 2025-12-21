# Architecture: Define 3-Layer Event Model

> **GitHub Issue Template** - Copy this content to create an issue at https://github.com/razrfly/eventasaurus/issues/new

## Overview

This issue proposes a formal 3-layer architecture for how events flow through and are created in the Eventasaurus ecosystem. Each layer serves a distinct purpose and builds upon the layer below it.

---

## Layer 1: Public Events Layer (Base Layer)

**Purpose:** Foundation layer containing all publicly discoverable events from external sources.

**Characteristics:**
- Events aggregated from scrapers (Cinema City, Bandsintown, Resident Advisor, etc.)
- Read-only from the user's perspective
- Canonical source of truth for public event data
- Handles deduplication and collision detection across sources
- Events have external IDs tied to their source (`{source}_{type}_{id}_{date}`)

**Data Sources:**
- Web scrapers
- Public APIs
- RSS/iCal feeds
- Partner data imports

**Key Concerns:**
- Data quality and validation
- Deduplication across sources
- Freshness and update frequency
- Source attribution and provenance

---

## Layer 2: Integration Layer (Platform Layer)

**Purpose:** API and integration layer for third-party applications and services.

**Characteristics:**
- Builds on top of the Public Events Layer
- Provides APIs for external consumption
- Handles ticket sales integrations
- Supports partner applications and white-label solutions
- May enrich events with additional metadata (pricing, availability, etc.)

**Use Cases:**
- Ticket sales platforms pulling event data
- Partner websites embedding event listings
- Analytics and reporting services
- Calendar sync services (Google Calendar, Apple Calendar)
- Notification services

**Key Concerns:**
- API stability and versioning
- Rate limiting and access control
- Data transformation for different consumers
- Webhook/push notification support
- Authentication and authorization

---

## Layer 3: User Application Layer (Top Layer)

**Purpose:** End-user facing applications for discovering and creating events.

**Characteristics:**
- Web application (Phoenix LiveView)
- iOS application
- Android application (future)
- Users can create their own events on top of Layers 1 & 2
- User-generated events coexist with scraped events
- Personalization and user preferences

**Capabilities:**
- Browse/search events from all layers
- Create private or public events
- RSVP and attendance tracking
- Social features (sharing, following, etc.)
- Personalized recommendations
- User profiles and preferences

**Key Concerns:**
- User experience and design consistency across platforms
- Real-time updates (LiveView, push notifications)
- Offline support (mobile apps)
- User-generated content moderation
- Privacy and data ownership

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  LAYER 3: User Applications                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │   Web App   │  │  iOS App    │  │ Android App │          │
│  │  (LiveView) │  │             │  │  (future)   │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
│         │                │                │                  │
│         │    User-Created Events          │                  │
│         └────────────────┼────────────────┘                  │
└──────────────────────────┼──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              LAYER 2: Integration / Platform                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  REST API   │  │  Webhooks   │  │  Ticket     │          │
│  │             │  │             │  │  Partners   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              LAYER 1: Public Events (Base)                   │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐    │
│  │ Cinema    │ │ Bands-    │ │ Resident  │ │  Week.pl  │    │
│  │ City      │ │ intown    │ │ Advisor   │ │           │    │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘    │
│                         Scrapers                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Considerations

### Event Ownership Model
- Layer 1 events: Owned by the system, attributed to source
- Layer 2 events: May be co-owned with partners
- Layer 3 events: Owned by the creating user

### Visibility Rules
- Layer 1: Public by default
- Layer 2: Configurable per integration
- Layer 3: User-controlled (public/private/friends-only)

### Conflict Resolution
When the same event exists across layers:
1. User-created events take precedence for display to that user
2. Layer 2 enrichments (ticketing, pricing) merge with Layer 1 data
3. Deduplication happens at Layer 1 before propagating up

---

## Tasks

- [ ] Document current architecture vs. proposed architecture
- [ ] Define data models for each layer
- [ ] Design API contracts for Layer 2
- [ ] Define event ownership and visibility rules
- [ ] Plan migration path for existing events
- [ ] Design user event creation flow for Layer 3
