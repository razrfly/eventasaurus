# Admin Dashboard Style Guide

This guide documents the unified design patterns and components for Eventasaurus admin dashboards. Created as part of Issue #3396 (Admin Dashboard Unification).

## Overview

All admin pages should use the shared component library from `EventasaurusWeb.Admin.Components.HealthComponents` to ensure consistent UI/UX across the admin interface.

## Design Principles

### 1. Consistency
- Same visual language for health status across all pages
- Unified color scheme for status indicators
- Consistent spacing and typography

### 2. Accessibility
- Color-coded status always includes text/emoji alternatives
- Sufficient color contrast ratios
- Keyboard-navigable interactive elements

### 3. Responsiveness
- Mobile-first approach
- Components adapt to container width
- Tables scroll horizontally on small screens

### 4. Information Hierarchy
- Critical metrics prominently displayed
- Progressive disclosure of details
- Clear visual grouping of related information

## Color System

### Status Colors

| Status | Background | Text | Border | Use Case |
|--------|------------|------|--------|----------|
| Healthy | `bg-green-100` | `text-green-800` | `border-green-500` | Score >= 80%, success |
| Warning | `bg-yellow-100` | `text-yellow-800` | `border-yellow-500` | Score 60-79%, degraded |
| Critical | `bg-red-100` | `text-red-800` | `border-red-500` | Score < 60%, errors |
| Disabled | `bg-gray-100` | `text-gray-600` | `border-gray-300` | Inactive, no data |

### Status Emojis

| Status | Emoji | Label |
|--------|-------|-------|
| Healthy | `checkmark` | "Healthy" |
| Warning | `warning` | "Warning" |
| Critical | `x_mark` | "Critical" |
| Disabled | `dash` | "Disabled" |

### Accent Colors

| Purpose | Color | Usage |
|---------|-------|-------|
| Primary | Blue | Links, primary actions |
| Secondary | Gray | Secondary text, borders |
| Success | Green | Positive metrics, completions |
| Error | Red | Errors, critical issues |
| Info | Blue | Informational highlights |

## Component Usage

### Health Score Display

**Use `health_score_pill/1`** for:
- Table cells
- Inline status indicators
- Compact displays

```heex
<.health_score_pill score={85} status={:healthy} />
```

**Use `health_score_large/1`** for:
- Hero sections
- Detail page headers
- Dashboard summaries

```heex
<.health_score_large score={92} status={:healthy} label="City Health" />
```

### Progress Bars

**Use `progress_bar/1`** for:
- Percentage displays
- Coverage indicators
- Completion tracking

```heex
<.progress_bar value={75} color={:green} size={:md} show_label={true} />
```

Sizes: `:sm` (h-1), `:md` (h-2), `:lg` (h-3)
Colors: `:green`, `:blue`, `:yellow`, `:red`, `:gray`

### Sparklines

**Use `sparkline/1`** for:
- 7-day trend visualization
- Historical data comparison
- Compact trend display

```heex
<.sparkline data={[10, 15, 12, 18, 22, 20, 25]} color={:blue} />
```

### Stat Cards

**Use `stat_card/1`** for:
- Summary statistics
- Key metrics display
- Dashboard overview cards

```heex
<.stat_card
  label="Total Events"
  value="3,847"
  color={:blue}
  subtitle="Last 30 days"
/>
```

**Use `admin_stat_card/1`** for:
- Cards with icons
- Admin-specific metrics

```heex
<.admin_stat_card
  title="Active Cities"
  value="12"
  icon={:location}
  color={:blue}
/>
```

### Tables

**Use `sortable_header/1`** for:
- Sortable table columns
- Consistent header styling

```heex
<.sortable_header
  label="City"
  column={:name}
  sort_by={@sort_column}
  sort_dir={@sort_direction}
  on_sort="sort"
  align={:left}
/>
```

**Use `source_status_table/1`** for:
- Complete source health tables
- Monitoring dashboards

```heex
<.source_status_table
  sources={@source_stats}
  title="Source Health"
  sort_by={@sort_by}
  sort_dir={@sort_dir}
  on_sort="sort_sources"
/>
```

### Status Badges

**Use `status_badge/1`** for:
- Job/task status
- Oban job states

```heex
<.status_badge status={:success} />
<.status_badge status={:failure} />
<.status_badge status={:cancelled} />
```

### Trend Indicators

**Use `trend_indicator/1`** for:
- Percentage changes
- Week-over-week comparisons

```heex
<.trend_indicator change={5.2} size={:md} show_arrow={true} />
```

## Health Score Formula

The standardized 4-component health score:

| Component | Weight | Description |
|-----------|--------|-------------|
| Event Coverage | 40% | Days with events / total days (7-day window) |
| Source Activity | 30% | Sources active in last 24h / total sources |
| Data Quality | 20% | Events with complete data / total events |
| Venue Health | 10% | Venues with valid coordinates / total venues |

### Score Thresholds

| Score Range | Status | Color |
|-------------|--------|-------|
| 80-100% | Healthy | Green |
| 60-79% | Warning | Yellow |
| < 60% | Critical | Red |

## Page Structure

### Standard Admin Page Layout

```heex
<div class="px-4 sm:px-6 lg:px-8 py-8">
  <!-- Header -->
  <div class="mb-8">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-semibold text-gray-900">Page Title</h1>
        <p class="mt-2 text-sm text-gray-600">Page description</p>
      </div>
      <div class="flex gap-2">
        <!-- Action buttons -->
      </div>
    </div>
  </div>

  <!-- Summary Cards -->
  <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
    <!-- Stat cards -->
  </div>

  <!-- Main Content -->
  <div class="bg-white shadow rounded-lg">
    <!-- Tables, charts, etc. -->
  </div>
</div>
```

### Card Container

```heex
<div class="bg-white shadow rounded-lg p-6">
  <h3 class="text-lg font-semibold text-gray-900 mb-4">Section Title</h3>
  <!-- Content -->
</div>
```

## Importing Components

In your LiveView module:

```elixir
import EventasaurusWeb.Admin.Components.HealthComponents
```

Or import specific components:

```elixir
import EventasaurusWeb.Admin.Components.HealthComponents, only: [
  health_score_pill: 1,
  progress_bar: 1,
  sortable_header: 1
]
```

## Admin Pages Using This Guide

- `/admin` - Admin Dashboard
- `/admin/cities/health` - City Health Index
- `/admin/cities/:slug/health` - City Health Detail
- `/admin/monitoring` - Source Monitoring
- `/admin/monitoring/sources/:source_key` - Source Detail

## Related Documentation

- `lib/eventasaurus_web/live/admin/components/health_components.ex` - Component source
- GitHub Issue #3396 - Admin Dashboard Unification
