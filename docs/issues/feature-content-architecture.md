# Feature Content Architecture

## Problem Statement

Currently, feature information is scattered across multiple places:

1. **Home page features**: 8 hardcoded feature cards in `home.html.heex` with emoji, title, and description
2. **Changelog entries**: Each entry has a `changes` array with bullet-point items (type + description)
3. **Roadmap items**: Future features in Sanity, but separate from the feature showcase

This creates several issues:
- No single source of truth for "what features does the app have"
- Can't easily reuse feature information across pages (home, features page, marketing)
- Home page features don't connect to changelog timeline
- Some changelog entries ARE feature launches, but aren't marked as such
- Can't embed feature widgets elsewhere on the site

## Key Insight

**Features and Changelog entries are orthogonal dimensions:**
- **Features** = WHAT (capabilities the app offers)
- **Changelog** = WHEN (timeline of releases/updates)

A feature:
- May be introduced in one changelog entry
- May be enhanced across multiple changelog entries
- Exists independently of the timeline
- Should be showcasable with icon, description, screenshots

## Recommended Solution

### Create a Separate "Feature" Content Type in Sanity

```javascript
// Sanity schema: feature.js
{
  name: 'feature',
  title: 'Feature',
  type: 'document',
  fields: [
    // Core identity
    { name: 'title', type: 'string', title: 'Title' },
    { name: 'slug', type: 'slug', title: 'Slug' },

    // Descriptions
    { name: 'shortDescription', type: 'text', title: 'Short Description',
      description: 'One-liner for cards (under 100 chars)' },
    { name: 'fullDescription', type: 'text', title: 'Full Description',
      description: 'Longer explanation for feature pages' },

    // Visual
    { name: 'icon', type: 'string', title: 'Icon',
      description: 'Emoji or icon identifier (e.g., "📊" or "chart-bar")' },
    { name: 'image', type: 'image', title: 'Screenshot/Illustration' },

    // Organization
    { name: 'category', type: 'string', title: 'Category',
      options: {
        list: [
          'planning', 'social', 'commerce', 'discovery',
          'communication', 'integration', 'customization'
        ]
      }
    },
    { name: 'tags', type: 'array', of: [{ type: 'string' }], title: 'Tags' },

    // Display control
    { name: 'status', type: 'string', title: 'Status',
      options: { list: ['live', 'beta', 'coming_soon'] },
      initialValue: 'live'
    },
    { name: 'isFeatured', type: 'boolean', title: 'Featured on Home Page',
      description: 'Show in the main features grid',
      initialValue: false
    },
    { name: 'displayOrder', type: 'number', title: 'Display Order' },

    // Relationships
    { name: 'relatedChangelog', type: 'array', title: 'Related Changelog Entries',
      of: [{ type: 'reference', to: [{ type: 'changelogEntry' }] }],
      description: 'Changelog entries where this feature was added/updated'
    }
  ]
}
```

### Also Update changelogEntry Schema (optional)

Add reverse reference for discoverability:
```javascript
// In changelogEntry schema, add:
{ name: 'relatedFeatures', type: 'array', title: 'Related Features',
  of: [{ type: 'reference', to: [{ type: 'feature' }] }],
  description: 'Features introduced or enhanced in this release'
}
```

## How This Would Be Used

### 1. Home Page Feature Grid
**Query**: Features where `isFeatured == true`, ordered by `displayOrder`
**Display**: Icon, title, shortDescription in a grid

```elixir
# Replace hardcoded HTML with:
<.feature_grid features={@featured_features} />
```

### 2. Dedicated Features Page (New)
**Route**: `/features`
**Query**: All features grouped by category
**Display**: Full cards with image, fullDescription, "Added in [date]" from changelog

### 3. Enhanced Changelog Display
When viewing a changelog entry, show related features:
- "Features introduced in this release"
- Feature badges/icons inline

### 4. Feature Widget Component
Reusable component that can be embedded anywhere:
```elixir
# Embed a single feature card
<.feature_card feature={@feature} />

# Embed features by category
<.feature_list category="planning" />

# Embed feature badges
<.feature_badges features={@features} />
```

## What About Changelog "Changes" Array?

**Keep it as-is.** The changes array serves a different purpose:
- Granular change notes (bug fixes, minor improvements, specific updates)
- Not every change is a feature
- Good for detailed release notes

The relationship:
- **Changelog entry** = a release at a point in time
- **Changelog changes** = bullet points of what changed in that release
- **Feature** = a standalone capability that might span multiple releases

Example:
- Feature: "Smart Date Polling"
- Related changelog entries:
  - Oct 2024: "Smart Date Polling" (initial launch)
  - Nov 2024: "Polling Improvements" (enhanced anonymous voting)
  - Dec 2024: "Performance Updates" (faster poll loading)

## Implementation Phases

### Phase 1: Sanity Schema (Sanity Studio)
- [ ] Create `feature` document type
- [ ] Optionally add `relatedFeatures` to `changelogEntry`
- [ ] Test in Sanity Studio

### Phase 2: Elixir Integration
- [ ] Create `lib/eventasaurus/sanity/features.ex` service
- [ ] GROQ queries: all, featured, by category, by slug
- [ ] ETS caching (5-minute TTL like changelog)
- [ ] Transform functions

### Phase 3: Phoenix Components
- [ ] Create `lib/eventasaurus_web/components/feature_components.ex`
  - `feature_card/1` - single feature display
  - `feature_grid/1` - home page grid
  - `feature_list/1` - categorized list
  - `feature_badge/1` - small inline badge
- [ ] Integrate with existing tag color system

### Phase 4: Page Updates
- [ ] Update home page to use Sanity features
- [ ] Create `/features` page
- [ ] Enhance changelog to show related features

### Phase 5: Content Migration
- [ ] Migrate 8 hardcoded home features to Sanity
- [ ] Create features from key changelog entries
- [ ] Link features to relevant changelog entries

## Visual Comparison

### Current State
```
Home Page:
  [Hardcoded HTML features]

Changelog:
  Entry 1 → [changes: [...]]
  Entry 2 → [changes: [...]]

Roadmap:
  Item 1, Item 2, Item 3
```

### Proposed State
```
Features (Sanity):                Changelog (Sanity):
  Feature A ←─────────────────────→ Entry 1 (introduces A)
  Feature B ←─────────────────────→ Entry 2 (introduces B)
  Feature C ←────────┬────────────→ Entry 3 (introduces C)
                     └────────────→ Entry 5 (enhances C)

Home Page:
  [Features where isFeatured=true]

Features Page:
  [All features by category]

Changelog Page:
  [Entries with related feature badges]
```

## Benefits

1. **Single source of truth**: All features defined once in Sanity
2. **Reusable**: Display features anywhere via components
3. **Connected**: Features link to when they were added/enhanced
4. **Flexible**: Categories, ordering, featured flags
5. **Maintainable**: Update feature info in one place
6. **Marketing-ready**: Features page, widgets for landing pages
7. **Separation of concerns**: Features = capabilities, Changelog = timeline

## Questions to Consider

1. Should features have their own detail pages (`/features/date-polling`)?
2. Should we show "New" badges on recently launched features?
3. How do roadmap items transition to features when released?
4. Should categories match the existing tag system or be separate?

---

*Created: December 2024*
*Status: Proposal/Brainstorm*
