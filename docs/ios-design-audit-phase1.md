# iOS Design Audit - Phase 1 Reference Document

> Competitive analysis of **Luma** and **Apple Invites** for Eventasaurus iOS redesign.
> Based on 223 Luma screenshots + 93 Apple Invites screenshots + current codebase audit.

---

## Executive Summary

**Luma** is the primary design reference — a mature event platform with discovery, hosting, messaging, ticketing, and social features. It has a clean, minimalist aesthetic with excellent information hierarchy.

**Apple Invites** is the premium native reference — Apple's own event invitation app that demonstrates best-in-class iOS native patterns: glassmorphism, immersive backgrounds, adaptive color theming, and deep system integration (Calendar, Photos, Apple Music).

**Recommendation:** Adopt Luma's information architecture and event discovery patterns, combined with Apple Invites' visual treatment (glassmorphic cards, immersive backgrounds, native system integrations). Build with the most modern SwiftUI features available.

---

## 1. Luma - Complete Screen Catalog

### 1.1 Onboarding (Screens 0-10)
- **Splash:** Simple black screen with centered Luma wordmark
- **Permission Prompts:** Standard iOS location/notification permission dialogs
- **Sign-in:** Email field → verification code flow (6 digits) → username entry
- **Welcome:** Clean onboarding with profile setup (name, username, avatar)

**Key Pattern:** Minimal onboarding — gets users to content fast. No tutorial carousels.

### 1.2 Main Navigation - Tab Bar (5 Tabs)
| Tab | Icon | Purpose |
|-----|------|---------|
| Home | House | Your Events feed (upcoming + past) |
| Explore | Compass | Discover nearby events |
| Create (+) | Plus circle | Create new event (center, prominent) |
| Favorites | Heart | Saved/liked events |
| Messages | Chat bubble | DMs and group chats |

**Key Pattern:** The Create button is the center tab — making event creation a first-class action, not buried in a menu. This is a major difference from our 3-tab layout.

### 1.3 Home Feed (Your Events)
- **Section Headers:** "Your Events" with date grouping
- **Event Cards:** Full-width cards with:
  - Cover image (top, rounded corners)
  - Event title (bold, large)
  - Date/time
  - Location
  - Attendee avatars (stacked circles, up to 5 shown + count)
  - Host badge/avatar
- **Filters:** "Upcoming" / "Past" toggle at top
- **Empty State:** Friendly illustration + "Find events" CTA

### 1.4 Discover/Explore (Screens 20-35)
- **"Nearby Events"** section header with city name + radius
- **Horizontal Category Scroll:** Pills/chips at top for filtering
  - Categories: All, Music, Tech, Art, Food, Social, Sports, etc.
- **Event Cards in Grid:** 2-column grid of square-ish cards
  - Cover image fills card
  - Title overlaid at bottom with dark gradient
  - Date badge in top-right corner
  - Attendee count badge
- **"Featured" Section:** Larger hero cards for promoted events
- **Calendar Pages:** `/calendar/{username}` — organizer profile with their event list
- **Map View:** Full-screen map with event thumbnail markers clustered by location
  - Tapping a marker shows a mini event card overlay at bottom

**Key Pattern:** Luma's discover is MUCH richer than our current DiscoverView. The 2-column grid, map integration, and organizer calendars are notable.

### 1.5 Event Detail (Screens 40-80)
This is Luma's strongest screen. Key elements from top to bottom:

1. **Cover Image:** Full-width hero, edge-to-edge
2. **Color-Adaptive Background:** Background color extracted from the cover image — the entire detail view takes on the event's visual identity
3. **Title:** Large, bold, white text overlaid or below image
4. **Date/Time Block:** Calendar icon + formatted date + time range
5. **Location Block:** Pin icon + venue name + address (tappable for maps)
6. **Host Section:** Avatar + name + "Hosted by" label
7. **Action Bar (Sticky/Floating):**
   - "Register" / "Get Tickets" primary CTA button (full-width, prominent)
   - Share button
   - Bookmark/save button
8. **Attendee Section:**
   - Stacked avatar row
   - "{N} Going" count
   - "See All" link → full guest list
9. **Description:** Rich text (supports basic formatting)
10. **About the Host:** Mini profile card with follow button

**Guest List View:**
- Sectioned: Going / Maybe / Waitlisted
- Each row: Avatar + Name + mutual connections badge
- Search within guest list

**Registration Flow:**
- Bottom sheet: "Register for Event"
- Fields: Name, email, custom questions (set by host)
- Ticket type selection (Free, Paid tiers)
- Payment integration for paid events
- Confirmation screen with calendar add + share

**Key Patterns:**
- Color-adaptive theming from cover image is the signature Luma design element
- Floating CTA bar that stays visible during scroll
- Social proof (attendees) is front and center

### 1.6 Event Creation (Screens 100-150)
Multi-step creation flow:

1. **Cover Image Selection:**
   - Photo library picker
   - Camera option
   - Unsplash integration for stock images
   - AI-powered cover suggestions

2. **Event Details Form:**
   - Title (large text field, placeholder "Event Title")
   - Start date/time picker (native iOS wheel)
   - End date/time picker
   - Location search (Google Maps integration — address autocomplete)
   - Description (rich text with AI "Suggest Description" feature)

3. **AI Description Generator (Screen 145):**
   - Bottom sheet with "Suggest Description"
   - **Mood selector:** Emoji pills (party, formal, casual)
   - **Length selector:** S / M / L pills
   - **Additional Instructions:** Free text field
   - **Generate button**
   - This is a standout feature worth noting

4. **Event Settings (Screens 85-100):**
   - Registration type: Open, Approval Required, Invite Only
   - Capacity limit
   - Waitlist toggle
   - Registration questions (custom fields)
   - Ticket types (Free / Paid with price)
   - Check-in settings
   - Guest invite permissions (can guests invite others?)

5. **Post-Creation:**
   - Share sheet with link
   - Invite specific people
   - Event management dashboard

### 1.7 Check-in System (Screens 85-95)
- **QR Code Scanner:** Full-screen camera view for scanning guest QR codes
- **Guest Check-in List:** Search + manual check-in toggle per guest
- **Check-in Stats:** X/Y checked in, progress bar

### 1.8 Messaging (Screens 155-175)
- **DM List:** Standard chat list with avatars, last message preview, timestamps
- **DM Thread:** iMessage-like bubbles (blue for sent, gray for received)
- **Group Chat Creation:** Contact picker → name group → create
- **Group Chat:** Member list, admin controls (promote/remove), shared media

### 1.9 Profile & Settings (Screens 180-222)
**Profile:**
- Avatar (large, circular, tappable to edit)
- Display name + username
- Bio text
- Social links (Instagram, Twitter/X, LinkedIn, Website)
- "Edit Profile" button

**Settings:**
- Account Settings: Email, phone, password, connected accounts
- Payment Methods: Visa/card management, payment history
- Notification Preferences: Push toggle per category (new events, messages, updates)
- Appearance: Light/Dark/System
- Contact Support / Help Center
- Privacy Policy / Terms
- Sign Out / Delete Account

**Key Pattern:** Social links on profile are prominent — Luma is a social platform first.

### 1.10 Live Activity Widget (Screen 130)
- iOS Live Activity / Dynamic Island support
- Shows: Event name, time until start, venue
- Quick actions: Navigate, Check-in

---

## 2. Apple Invites - Complete Screen Catalog

### 2.1 Onboarding (Screens 0-1)
- **Welcome Screen:** "Welcome to Apple Invites" with friendly icon
  - Two paths: "Received an invitation?" / "Just got the app?"
  - Privacy disclaimer with "See how your data is managed..." link
  - Single "Continue" CTA
- **Home Carousel:** Horizontal paging cards showing sample events
  - Cards have: Photo background, event title, date, location, attendee avatars, "Hosting"/"Going" badges
  - "Get the party started with Invites" tagline
  - "Create an Event" CTA

**Key Pattern:** The horizontal paging carousel of event cards with rich backgrounds is stunning — each card is like a poster/invitation.

### 2.2 Main Navigation
- **NO tab bar** — single-screen app with:
  - "Upcoming" title (dropdown filter: Upcoming / Drafts / Past)
  - "+" create button (top right)
  - Profile avatar (top right)
- **Event list:** Full-width poster-style cards that fill the viewport width
  - Each card is an immersive invitation preview

**Key Pattern:** Apple Invites is intentionally simple. No discover feed, no social features, no messaging. It's purely about creating beautiful invitations and managing RSVPs.

### 2.3 Event Cards (Home Screen)
Each event card is a **full-width, full-bleed poster** with:
- Background image/emoji pattern/color filling the entire card
- "Hosting" or "Going" badge (top left with crown/checkmark icon)
- Attendee avatars (stacked, centered)
- Event title (large, styled typography — multiple font options)
- Date + time
- Location name
- The card itself looks like a physical invitation

**Key Pattern:** Events are presented as **invitation cards**, not list items. This is the core design philosophy — every event is treated as something beautiful and worth showcasing.

### 2.4 Event Creation (Screens 3-50)
The creation flow is where Apple Invites truly shines:

1. **Background Selection (Screens 30-35):**
   - **Sources:** Photos, Camera
   - **Emoji Patterns:** Pre-designed layouts with themed emojis (food, party, sports, etc.) — e.g., scattered pizza/chicken/plate emojis on solid green background
   - **Photographic:** Curated high-quality photos (candles, roses, champagne, pool, etc.)
   - **Colours:** Solid gradient options (blue, green, orange, pink, etc.)
   - Rich grid layout for browsing backgrounds

2. **Card Editor (Screens 10-20):**
   - Live preview of the invitation card
   - "Edit Background" button overlaid on image
   - **Glassmorphic form fields** overlaid on the background:
     - "Event Title" — large, centered, styled text
     - "Date and Time" with calendar icon
     - "Location" with pin icon
   - Fields appear as frosted glass cards floating over the background
   - "Preview" button (top right) shows how guests will see it

3. **Typography Picker (Screen 12):**
   - Inline font style selector: 4 options (serif, sans, bold, light)
   - Changes title typography in real-time

4. **Date/Time Picker (Screens 33-34):**
   - Bottom sheet expanding from the card
   - "All-day" toggle
   - "Include End Time" toggle
   - Native iOS date/time wheels
   - Clean "Done" button

5. **Location Search (Screen 40):**
   - Full-screen search with Apple Maps integration
   - "MAP LOCATIONS" header with results list
   - Each result: Red pin icon + address + city/state

6. **Description & Host (Screens 10-20):**
   - "Hosted by {Name}" with avatar
   - "Add a description" text field
   - All overlaid on the background with glassmorphic treatment

7. **Shared Album (Screen 4, 20, 45-50):**
   - "Shared Album" section: Guests can view and add photos
   - Grid of 3 photo thumbnails + "Add Photos" button
   - Integrates with iOS Shared Albums / iCloud Photos
   - Permission dialog for Photo Library access

8. **Shared Playlist (Screen 4, 20):**
   - "Shared Playlist" section
   - "Add Playlist" button → Apple Music integration
   - Guests can see and play the event playlist

**Key Patterns:**
- The **glassmorphic card floating over immersive background** is the defining Apple Invites pattern
- Everything is designed to make the invitation itself beautiful
- Deep iOS integration (Photos, Calendar, Music) — uniquely Apple

### 2.5 Invitation & RSVP (Screens 25-60)
**Invite Flow (Screen 25):**
- **"Invite with Public Link"** section:
  - Share buttons: Messages, Mail, Share Link, Copy Link
  - "Approve Guests" toggle
  - Explanation: "Send a public link for guests to RSVP"
- **"Invite Individuals"** section:
  - "Choose a Guest" field with add button
  - Contact picker integration (Screen 60)
  - Contacts list with checkboxes + "Show Selected" filter
  - "Select Contacts Later" option

**Guest List (Screen 7):**
- Sectioned by RSVP status:
  - **Going** (green checkmarks): Name + personal message ("Happy birthday!", "Excited!", "Can't wait")
  - **Maybe** (1): Name + note ("I'll need to check my calendar...")
  - **Not Going** (1): Name + note
- Three-dot menu per guest for actions
- Guest messages are a unique feature — each guest can leave a personal note

**RSVP Actions:**
- "Send a Note" button — opens modal for host to message all guests
- "Invite Guests" button — returns to invite flow

### 2.6 Event Detail (Guest View) (Screens 75-80)
As a guest sees it:
1. **Full-bleed background image** (hero, immersive)
2. **Event title** (large, styled typography)
3. **Date + time + location** (centered)
4. **"Send a Note" / "Invite Guests" action buttons** (glassmorphic pills)
5. **"Note Sent" confirmation** with the message and timestamp
6. **Host section:** "Hosted by {Name}" with avatar and description
7. **"7 Going"** with stacked avatars and "{Name} is going" social proof
8. **Weather widget:** Shows forecast for event date (temperature, conditions)
9. **Directions section:** Address + embedded Apple Maps view
10. **Shared Album:** Photo grid with "Add Photos" button
11. **Playlist:** Album art + "Birthday Playlist" with play button

**Key Pattern:** The **weather widget** on the event detail is a fantastic native integration. Also the **directions** section with embedded map.

### 2.7 Event Settings (Screen 70)
- **Guests:** Additional Guests toggle (+1 Guest)
- **Approve Guests:** Toggle on/off
- **Privacy:** "Remove Background Preview" — hides background until verified guest
- **Accessibility:** "Background Image Description" for screen readers
- **Event Management:**
  - Duplicate Event
  - Cancel Event
  - Pause Replies

### 2.8 Settings (Screens 90-92)
Minimal settings:
- iCloud+ subscription upsell
- Account info (name, email, Apple Account)
- Push Notifications toggle
- Email Updates toggle
- Privacy, Help, Terms links

---

## 3. Comparative Analysis

### 3.1 Information Architecture

| Feature | Luma | Apple Invites | Eventasaurus (Current) |
|---------|------|---------------|----------------------|
| Tab Count | 5 (Home, Explore, Create, Favorites, Messages) | 1 (single screen) | 3 (Discover, My Events, Profile) |
| Discovery Feed | Rich grid + map + categories | None (host-only) | List with filters |
| Event Creation | Full-featured with AI | Beautiful card builder | Not implemented |
| Messaging | DMs + Group Chat | Host notes only | Not implemented |
| Ticketing | Built-in (free + paid) | None | Link out to ticket URL |
| Check-in | QR scanner + manual | None | Not implemented |
| Social Features | Following, profiles, social links | None | Minimal profile |
| System Integration | Basic (calendar add) | Deep (Calendar, Photos, Music, Weather) | None |

### 3.2 Visual Design Comparison

| Aspect | Luma | Apple Invites | Recommendation |
|--------|------|---------------|----------------|
| Background Treatment | Color-adaptive from cover image | Full-bleed immersive backgrounds | **Apple Invites** — more dramatic and engaging |
| Card Style | Clean white/dark cards with shadow | Glassmorphic cards over backgrounds | **Apple Invites** — more modern, uses native materials |
| Typography | System SF Pro, standard weights | Multiple styled fonts (serif/sans choices) | **Luma** — cleaner for an information-dense app |
| Color System | Neutral base + category accent colors | Event-specific color theming | **Hybrid** — Luma's neutrals for chrome, Apple's adaptive for event content |
| Navigation | Standard tab bar + nav stack | Minimal, single-screen | **Luma** — we need discovery + navigation depth |
| Event Presentation | List/grid items | Poster/invitation cards | **Apple Invites** for event cards, Luma for list views |
| Empty States | Illustrations + CTAs | Minimal calendar icon | **Luma** — friendlier empty states |
| Loading States | Standard spinners | N/A (local data) | Standard ProgressView is fine |

### 3.3 Interaction Patterns

| Pattern | Luma | Apple Invites | Recommendation |
|---------|------|---------------|----------------|
| Event Card Tap | Navigate to detail | Navigate to detail | Standard |
| Filter Selection | Horizontal chip scroll | Dropdown filter | **Luma** — chips are more discoverable |
| Date Selection | Chip pills (Today, Tomorrow, etc.) | Native iOS wheel picker | **Hybrid** — chips for browse, wheel for creation |
| City/Location | Modal picker with search | Inline Apple Maps search | Luma's pattern (we already have this) |
| Share | Standard share sheet | Messages/Mail/Link buttons | **Apple Invites** — explicit share options are clearer |
| RSVP | Bottom sheet form | Note + RSVP buttons | **Apple Invites** — simpler and more elegant |
| Image Selection | Photo library + Unsplash + AI | Photos + Emoji patterns + Curated | **Apple Invites** — emoji backgrounds are delightful |
| Scroll Behavior | Infinite scroll with pagination | Horizontal paging | Depends on context |

---

## 4. Key Design Patterns to Adopt

### 4.1 From Luma (Information Architecture)
1. **5-Tab Navigation** — Add Create (center) and Favorites tabs
2. **Discover Grid** — 2-column event card grid instead of single-column list
3. **Map View Toggle** — Add map view to discover with event markers
4. **Color-Adaptive Event Detail** — Extract dominant color from cover image
5. **Floating Action Bar** — Sticky CTA on event detail (Register/Share/Save)
6. **Attendee Social Proof** — Stacked avatars + count prominently displayed
7. **AI Description Generator** — Mood + length + custom instructions
8. **Organizer Calendars** — Profile pages with event history
9. **Category Chip Filtering** — Already implemented, keep refining

### 4.2 From Apple Invites (Visual Treatment)
1. **Glassmorphic Cards** — `.ultraThinMaterial` / `.glass` for overlaid content
2. **Immersive Backgrounds** — Full-bleed cover images that define the event's visual identity
3. **Poster-Style Event Cards** — Events presented as beautiful invitation cards, not list items
4. **Inline Typography Picker** — Font style options for event titles
5. **Weather Widget** — Show forecast on event detail for the event date
6. **Embedded Maps** — MapKit view with directions directly in event detail
7. **Shared Photo Album** — Photo grid tied to event
8. **Background Picker Categories** — Emoji patterns, photographic, solid colors as event backgrounds
9. **Guest Notes** — Personal messages with RSVP

### 4.3 Modern SwiftUI Features to Leverage
1. **`.glass` modifier** (iOS 26+) — True glassmorphism for cards and overlays
2. **`MeshGradient`** (iOS 18+) — Rich animated gradients for backgrounds
3. **`ScrollView` with `.scrollTransition`** — Parallax and fade effects on scroll
4. **`NavigationSplitView`** — For iPad support
5. **`ContentUnavailableView`** — Already using, expand usage
6. **`TipKit`** — Contextual tips for new users
7. **`StoreKit` views** — If adding premium features
8. **`WidgetKit` + Live Activities** — Event countdown widgets
9. **`MapKit` with `MapCameraPosition`** — More interactive maps
10. **`PhotosPicker`** — Native photo selection (already in iOS 16+)

---

## 5. Proposed Eventasaurus Design Direction

### 5.1 Design Philosophy
> "Luma's intelligence with Apple Invites' beauty, built natively for iOS"

- **Discovery = Luma-inspired:** Dense, filterable, actionable
- **Event Presentation = Apple Invites-inspired:** Beautiful, immersive, poster-like
- **Event Detail = Hybrid:** Luma's information depth with Apple's visual treatment
- **Chrome/Navigation = Luma-inspired:** 5 tabs, standard iOS navigation
- **Materials/Effects = Apple-native:** Glassmorphism, materials, adaptive colors

### 5.2 Priority Screen Redesigns

**Priority 1 — Event Detail View (Highest Impact)**
- Full-bleed cover image hero
- Color-adaptive background extracted from cover
- Glassmorphic info cards floating over background
- Sticky floating action bar (CTA + Share + Save)
- Weather widget for event date
- Embedded map with directions
- Attendee avatars with social proof
- Source attribution preserved

**Priority 2 — Discover Feed**
- 2-column card grid (poster-style cards like Apple Invites)
- Map view toggle
- Preserved filter chips (categories + date ranges)
- Featured/promoted section at top

**Priority 3 — Event Card Component**
- Full-bleed cover image background
- Glassmorphic overlay at bottom with title/date/location
- Attendee avatar stack
- Category badge
- "Going"/"Hosting" status badge (like Apple Invites)

**Priority 4 — Home/My Events**
- Upcoming/Past toggle
- Poster-style cards for your events
- Draft events section (if creation is added)

**Priority 5 — Navigation Update**
- Consider 5-tab layout when creation features are ready
- For now: keep 3 tabs but plan for expansion

### 5.3 Color & Material System

```
Base Chrome:
  - Light: White / System Background
  - Dark: System Background (.systemBackground)

Event-Adaptive:
  - Extract dominant color from event cover image
  - Use as background gradient on event detail
  - Apply as accent color for that event's UI elements

Materials:
  - .ultraThinMaterial for overlaid cards
  - .glass (iOS 26) for primary glassmorphic surfaces
  - .regularMaterial for navigation bars over content

Accent Colors:
  - Category-based: Music=blue, Food=orange, etc. (already implemented)
  - Source-based: Domain gradient mapping (already implemented)
```

### 5.4 Typography System

```
Event Title (Display):    .largeTitle or custom Display font
Section Headers:          .title2.bold()
Card Titles:             .headline
Body Text:               .body
Captions/Badges:         .caption, .caption2
Date/Time:               .subheadline (monospaced digits)
```

---

## 6. Gap Analysis — What We Need to Build

### Already Have (Keep & Enhance)
- [x] NavigationStack with typed destinations
- [x] Category chip filtering
- [x] Date range filtering
- [x] City picker with search
- [x] Event detail with venues, sources, categories
- [x] Movie detail with screenings
- [x] Source detail with city filter
- [x] Container/Festival detail
- [x] Venue detail with map
- [x] Pull-to-refresh
- [x] Infinite scroll pagination
- [x] Clerk authentication
- [x] Location services

### Need to Build (New)
- [ ] Glassmorphic card components
- [ ] Color extraction from cover images (dominant color)
- [ ] Poster-style event cards (replacing current list cards)
- [ ] 2-column discover grid layout
- [ ] Floating action bar on event detail
- [ ] Weather widget integration (WeatherKit)
- [ ] Map view toggle on discover
- [ ] Attendee avatar stacks (social proof)
- [ ] Event favoriting/bookmarking
- [ ] Immersive scroll-away header on event detail
- [ ] Improved empty states with illustrations
- [ ] Haptic feedback on key interactions
- [ ] Accessibility audit and VoiceOver improvements

### Future Phases (Not Now)
- [ ] Event creation flow
- [ ] Messaging system
- [ ] Check-in/QR scanner
- [ ] Ticketing
- [ ] Live Activities / Widgets
- [ ] Shared photo albums
- [ ] AI description generator

---

## 7. Reference Screenshots Index

### Luma Key Screens (for implementation reference)
| Screen # | Description | Key Pattern |
|----------|-------------|-------------|
| 0-5 | Onboarding/splash | Minimal onboarding |
| 10-15 | Home feed | Event card layout |
| 20-25 | Discover/Explore | 2-column grid + categories |
| 30-35 | Nearby events | Location-based feed |
| 40-50 | Event detail | Color-adaptive background |
| 55-60 | Guest list | Sectioned attendee list |
| 65-70 | Registration | Bottom sheet form |
| 75-80 | Event settings | Host management |
| 85-95 | Check-in | QR scanner + guest list |
| 100-110 | Cover image picker | Unsplash + camera + library |
| 115-120 | Category browse | Category hub pages |
| 125-130 | Map view | Event markers on map |
| 135-140 | Event creation form | Title/date/location/description |
| 145 | AI description | Mood + length + generate |
| 155-160 | DM thread | iMessage-style chat |
| 165-175 | Group chat | Member management |
| 180-190 | Profile & edit | Social links + avatar |
| 195-205 | Settings | Payment, notifications, account |
| 210-222 | Notifications | Push notification cards |

### Apple Invites Key Screens (for implementation reference)
| Screen # | Description | Key Pattern |
|----------|-------------|-------------|
| 0 | Welcome | Clean onboarding |
| 1-2 | Home carousel | Poster-style event cards |
| 3-4 | Event creation empty | Glassmorphic form fields |
| 5-6 | Home with events | Upcoming filter + poster cards |
| 7-8 | Guest list | Sectioned by RSVP + personal notes |
| 9 | Emoji event card | Emoji pattern background |
| 10-12 | Card editor | Live preview + typography picker |
| 15-20 | Event detail (edit) | Background + glassmorphic fields |
| 25 | Invite flow | Public link + individual invites |
| 30-35 | Background picker | Emoji/Photo/Color categories |
| 33-34 | Date picker | Inline bottom sheet |
| 40 | Location search | Apple Maps results |
| 45-50 | Shared album | Photo grid + Photo Library access |
| 55 | Apple Music | Playlist integration |
| 60 | Contact picker | iOS contacts with checkboxes |
| 65 | Drafts view | Draft event cards |
| 70 | Event settings | Guest controls, privacy, a11y |
| 75-78 | Event detail (guest) | Full experience with weather, map, album, playlist |
| 80 | Event detail (host) | Action buttons + note sent |
| 85 | Calendar integration | iCloud Calendar sync |
| 90-92 | Settings | Account, notifications, privacy |

---

*Document generated: 2026-02-19*
*Sources: Mobbin screenshots (Luma Jul 2025, Apple Invites Feb 2025)*
*Current codebase: Eventasaurus iOS (SwiftUI, iOS 16+)*
