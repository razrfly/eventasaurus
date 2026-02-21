# Wombie API Reference

## Overview

Wombie uses a **hybrid API architecture**:

- **REST API** (`/api/v1/mobile/*`) for public discovery endpoints (events, venues, movies, cities). No authentication required.
- **GraphQL API** (`/api/graphql`) for all authenticated operations (profile, event management, RSVP, plans). Requires Clerk JWT Bearer token.

This split lets the REST discovery endpoints be cached at the CDN edge while authenticated operations go through GraphQL with full type safety.

## Authentication

Authenticated endpoints require a Clerk JWT Bearer token in the `Authorization` header:

```
Authorization: Bearer <clerk_session_token>
```

The token is obtained client-side via Clerk's SDK (`Clerk.shared.auth.getToken()` on iOS).

---

## REST API (Public Discovery)

Base path: `/api/v1/mobile`

All endpoints are read-only (GET). No authentication required.

### Events

#### `GET /events/nearby`

Returns public events near coordinates, with aggregation (movies grouped by film, etc.).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `lat` | Float | Yes* | Latitude |
| `lng` | Float | Yes* | Longitude |
| `radius` | Float | No | Radius in meters (default: 50000) |
| `city_id` | Int | No | City ID (alternative to lat/lng) |
| `categories` | String | No | Comma-separated category IDs |
| `search` | String | No | Text search query |
| `date_range` | String | No | `today`, `tomorrow`, `this_weekend`, `next_7_days`, `next_30_days` |
| `sort_by` | String | No | `starts_at`, `title`, `popularity`, `relevance` |
| `sort_order` | String | No | `asc`, `desc` |
| `page` | Int | No | Page number (default: 1) |
| `per_page` | Int | No | Items per page (default: 20, max: 100) |
| `language` | String | No | Content language (default: `en`) |

*Either `lat`+`lng` or `city_id` is required.

**Response:** `{ events: [...], meta: { page, per_page, total_count, all_events_count, date_range_counts } }`

Event types in response: `"public"`, `"movie_group"`, `"event_group"`, `"container_group"`

#### `GET /events/:slug`

Returns event details by slug. Works for both public discovery events and user-created events.

#### `GET /categories`

Returns all active event categories.

**Response:** `{ categories: [{ id, name, slug, icon, color }] }`

### Cities

#### `GET /cities`

Search cities by name.

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | String | Search query |

#### `GET /cities/popular`

Returns popular/featured cities.

#### `GET /cities/resolve`

Resolves coordinates to a city.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `lat` | Float | Yes | Latitude |
| `lng` | Float | Yes | Longitude |

### Movies

#### `GET /movies`

Returns movies index with optional search.

| Parameter | Type | Description |
|-----------|------|-------------|
| `search` | String | Search query |
| `limit` | Int | Max results (default: 24) |

#### `GET /movies/:slug`

Returns movie details with screenings.

| Parameter | Type | Description |
|-----------|------|-------------|
| `city_id` | Int | Filter screenings by city |

### Other

#### `GET /sources/:slug`

Returns source/performer details.

#### `GET /containers/:slug`

Returns container (festival/conference) details.

#### `GET /venues/:slug`

Returns venue details.

---

## GraphQL API (Authenticated)

Endpoint: `POST /api/graphql`

Interactive playground: `/api/graphiql` (development only)

All operations require authentication unless noted otherwise.

### Queries

#### `myProfile`

Returns the authenticated user's profile.

```graphql
query {
  myProfile {
    id name email username bio avatarUrl profileUrl
    defaultCurrency timezone
  }
}
```

Returns: `User`

#### `myEvents(limit: Int)`

Returns events organized by the authenticated user.

```graphql
query {
  myEvents(limit: 20) {
    id slug title tagline description
    startsAt endsAt timezone
    status visibility theme
    coverImageUrl isTicketed isVirtual virtualVenueUrl
    isOrganizer participantCount myRsvpStatus
    venue { id name address latitude longitude }
    organizer { id name avatarUrl }
    createdAt updatedAt
  }
}
```

Returns: `[Event!]!`

#### `myEvent(slug: String!)`

Returns a single event by slug (organizer only).

Returns: `Event`

#### `attendingEvents(limit: Int)`

Returns upcoming events the user is attending.

```graphql
query {
  attendingEvents(limit: 20) {
    id slug title tagline
    startsAt endsAt timezone
    status visibility coverImageUrl
    isOrganizer participantCount myRsvpStatus
    venue { id name address }
    organizer { id name avatarUrl }
  }
}
```

Returns: `[Event!]!`

#### `myPlan(slug: String!)`

Returns the user's plan for a public event (null if no plan exists).

```graphql
query {
  myPlan(slug: "event-slug") {
    slug title inviteCount createdAt alreadyExists
  }
}
```

Returns: `Plan` (nullable)

### Mutations

#### `createEvent(input: CreateEventInput!)`

Creates a new event. The authenticated user becomes the organizer.

```graphql
mutation {
  createEvent(input: { title: "My Event", startsAt: "2026-03-01T19:00:00Z" }) {
    event { id slug title status }
    errors { field message }
  }
}
```

#### `updateEvent(slug: String!, input: UpdateEventInput!)`

Updates an event (organizer only).

#### `deleteEvent(slug: String!)`

Deletes an event (organizer only). Returns `{ success, errors }`.

#### `publishEvent(slug: String!)`

Publishes an event (sets status to confirmed, visibility to public).

#### `cancelEvent(slug: String!)`

Cancels an event (organizer only).

#### `rsvp(slug: String!, status: RsvpStatus!)`

Sets the user's RSVP status for an event.

```graphql
mutation {
  rsvp(slug: "event-slug", status: GOING) {
    event { id slug title participantCount myRsvpStatus }
    status
    errors { field message }
  }
}
```

#### `cancelRsvp(slug: String!)`

Removes the user's RSVP from an event.

```graphql
mutation {
  cancelRsvp(slug: "event-slug") {
    success
    errors { field message }
  }
}
```

#### `createPlan(slug: String!, emails: [String!]!, message: String)`

Creates a "Plan with Friends" for a public event and sends email invitations.

```graphql
mutation {
  createPlan(slug: "event-slug", emails: ["friend@example.com"], message: "Let's go!") {
    plan { slug title inviteCount createdAt alreadyExists }
    errors { field message }
  }
}
```

#### `inviteGuests(slug: String!, emails: [String!]!, message: String)`

Invites guests to an event by email (organizer only).

#### `uploadImage(file: Upload!)`

Uploads an image via multipart form upload (Absinthe Upload). Returns `{ url, errors }`.

### Types

#### User

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID! | User ID |
| `name` | String! | Display name |
| `email` | String | Email (only visible to self) |
| `username` | String | Username |
| `bio` | String | Bio text |
| `avatarUrl` | String! | Avatar image URL |
| `profileUrl` | String | Public profile URL |
| `defaultCurrency` | String | Preferred currency |
| `timezone` | String | Preferred timezone |

#### Event

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID! | Event ID |
| `slug` | String! | URL slug |
| `title` | String! | Event title |
| `tagline` | String | Short tagline |
| `description` | String | Full description |
| `startsAt` | DateTime | Start date/time |
| `endsAt` | DateTime | End date/time |
| `timezone` | String | Timezone |
| `status` | EventStatus! | Draft, Polling, Threshold, Confirmed, Canceled |
| `visibility` | EventVisibility! | Public or Private |
| `theme` | EventTheme | Visual theme |
| `coverImageUrl` | String | Cover image URL |
| `isTicketed` | Boolean! | Has ticketing |
| `isVirtual` | Boolean! | Virtual event |
| `virtualVenueUrl` | String | Virtual venue link |
| `isOrganizer` | Boolean! | Current user is organizer |
| `participantCount` | Int! | Number of participants |
| `myRsvpStatus` | RsvpStatus | Current user's RSVP |
| `venue` | Venue | Event venue |
| `organizer` | User | Event organizer |
| `createdAt` | DateTime! | Created timestamp |
| `updatedAt` | DateTime! | Updated timestamp |

#### Venue

| Field | Type |
|-------|------|
| `id` | ID! |
| `name` | String! |
| `address` | String |
| `latitude` | Float |
| `longitude` | Float |

#### Plan

| Field | Type | Description |
|-------|------|-------------|
| `slug` | String! | Plan event slug |
| `title` | String! | Plan event title |
| `inviteCount` | Int! | Number of invites sent |
| `createdAt` | DateTime! | Created timestamp |
| `alreadyExists` | Boolean | True if plan already existed |

### Enums

| Enum | Values |
|------|--------|
| `EventStatus` | `DRAFT`, `POLLING`, `THRESHOLD`, `CONFIRMED`, `CANCELED` |
| `EventVisibility` | `PUBLIC`, `PRIVATE` |
| `EventTheme` | `MINIMAL`, `COSMIC`, `VELOCITY`, `RETRO`, `CELEBRATION`, `NATURE`, `PROFESSIONAL` |
| `RsvpStatus` | `GOING`, `INTERESTED`, `NOT_GOING` |

### Error Handling

All mutations return an `errors` field with `[{ field, message }]`. Check this field before accessing the data.

GraphQL-level errors (authentication, not found, etc.) are returned in the top-level `errors` array of the GraphQL response.

---

## Rate Limiting

- REST API: 60 requests/minute per IP
- GraphQL API: 60 requests/minute per IP
- Plan creation (`createPlan`): 5 requests/10 minutes per user
