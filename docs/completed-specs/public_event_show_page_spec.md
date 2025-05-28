# Public Event Show Page Spec

## 1. Purpose and Audience
- This page is designed for end users (attendees, not event creators or admins).
- It is a public, shareable page for a single event, accessible via a unique slug (e.g., `/:slug`).
- No authentication or login required for viewing or registering.
- No admin/dashboard features, no event editing, no event creation.

## 2. Core Features

### a. Event Details Display
- Prominent event title, date, and time.
- Location (physical or virtual link).
- Description/agenda.
- Host/organizer info (optional, minimal).
- Event image/banner (if available).

### b. Registration Call-to-Action
- Clear, prominent registration button/form.
- Minimal required fields (name, email; possibly custom fields).
- Confirmation state after registration (e.g., “You’re registered!”).
- Optionally, add to calendar (Google, Outlook, etc.).
- Optionally, show number of registered attendees (if not private).

### c. Theming/Layout Options
- Users (event creators) can select from several pre-defined visual themes for the event page.
- Themes affect:
  - Fonts (type, size, weight)
  - Color palette (background, text, accent)
  - Button styles
  - Imagery/backgrounds (optional)
- Content remains unchanged; only styling is affected.
- Theme selection is per-event and stored with the event data.

### d. Responsive Design
- Page should look good on both desktop and mobile.
- Registration flow should be mobile-friendly.

### e. Social Sharing
- Social share buttons (Twitter, Facebook, LinkedIn, copy link).
- Open Graph/meta tags for attractive previews.

### f. Optional Add-ons (for future consideration)
- Countdown timer to event start.
- Speaker or guest list (if applicable).
- FAQ or additional info section.
- Customizable confirmation message.
- Option to hide/show attendee count.

## 3. Technical/Implementation Notes
- Page should be accessible via a simple, memorable URL (e.g., `/e/:slug` or `/event/:slug`).
- No dependencies on admin session or dashboard code.
- Each theme is a separate CSS file or a CSS-in-JS theme object.
- Theme can be previewed by the event creator before publishing.
- Safe against spam/abuse (basic anti-bot on registration form).

## 4. Out of Scope
- No event editing or management from this page.
- No dashboard, analytics, or admin controls.
- No login or authentication required for viewing/registering.

---

### Next Steps
- Review and refine this spec: Are there any features you want to add or remove?
- Prioritize features for MVP vs. future.
- Once finalized, we can break this into implementation tasks and start coding.
