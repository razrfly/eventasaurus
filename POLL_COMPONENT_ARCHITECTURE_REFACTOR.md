# Poll Component Architecture Refactor - Analysis & Proposal

## Executive Summary

The current poll component architecture has become messy due to inconsistent layout control patterns. This document analyzes the problems and proposes a clean, modular solution.

---

## Current Architecture Analysis

### Page Hierarchy

```
1. Event Page (/event-slug)
   └── Shows multiple polls with inline voting

2. All Polls Page (/event-slug/polls)
   └── Lists all polls for an event with inline voting

3. Individual Poll Page (/event-slug/polls/1)
   └── Shows single poll in detail view
```

### Component Hierarchy

```
Page Template
├── Card/Container (rendered by page)
│   ├── Header Section (rendered by page)
│   │   ├── Emoji, Title, Description
│   │   ├── Status Badge
│   │   └── "View Poll" Button
│   │
│   └── PublicGenericPollComponent (LiveView component)
│       ├── Internal Header (sometimes hidden via hide_header)
│       │   ├── Emoji, Title, Description
│       │   └── Voter Count
│       │
│       ├── PollOptions or VotingInterfaceComponent
│       │   └── Voting Header (sometimes hidden via show_header)
│       │       ├── Voting System Title
│       │       ├── Voter Count
│       │       └── Instructions
│       │
│       └── SuggestionForm
```

---

## Problem Identification

### 1. Inconsistent Prop Naming

Three different props across components for similar concepts:

| Component | Prop Name | Purpose |
|-----------|-----------|---------|
| DateSelectionPollComponent | `show_container` | Control whether component renders wrapper |
| PublicGenericPollComponent | `hide_header` | Control whether component renders header |
| VotingInterfaceComponent | `show_header` | Control whether component renders header |

**Problem**: Different naming conventions create confusion about what each prop does.

### 2. Duplicate Information Display

Poll metadata (emoji, title, description, voter count) is rendered at THREE levels:

**Level 1 - Page Template (Card Header)**:
```heex
<!-- public_polls_live.html.heex lines 71-104 -->
<div class="flex items-center justify-between mb-4">
  <div class="flex items-center space-x-3">
    <div class="text-2xl"><%= poll_emoji(poll.poll_type) %></div>
    <div>
      <h3 class="text-lg font-semibold"><%= poll.title %></h3>
      <p class="text-sm text-gray-600"><%= poll.description %></p>
    </div>
  </div>
  <span class="badge"><%= poll_phase_display_text(poll.phase) %></span>
  <.link>View Poll</.link>
</div>
```

**Level 2 - PublicGenericPollComponent (Internal Header)**:
```heex
<!-- public_generic_poll_component.ex lines 331-344 -->
<%= if !@hide_header do %>
  <div class="mb-4">
    <h3><%= poll_emoji(@poll.poll_type) %> <%= get_poll_title_base(@poll) %></h3>
    <p><%= PollPhaseUtils.get_phase_description(@poll.phase, @poll.poll_type) %></p>
    <.voter_count poll_stats={@poll_stats} poll_phase={@poll.phase} />
  </div>
<% end %>
```

**Level 3 - VotingInterfaceComponent (Voting Header)**:
```heex
<!-- voting_interface_component.ex lines 198-237 -->
<%= if @show_header do %>
  <div class="px-4 py-4 border-b">
    <h3><%= get_voting_title(@poll.voting_system) %></h3>
    <.voter_count poll_stats={@poll_stats} />
    <p><%= get_voting_instructions(@poll.voting_system) %></p>
  </div>
<% end %>
```

**Result**: User sees "🎬 Suggestions, 8 voters" THREE times on the same page!

### 3. Unclear Component Responsibility

Current pattern uses boolean flags to hide/show sections based on context:

```heex
<!-- All Polls Page - hides component headers -->
<.live_component
  module={PublicGenericPollComponent}
  hide_header={true}
  ...
/>

<!-- Individual Poll Page - shows component headers -->
<.live_component
  module={PublicGenericPollComponent}
  hide_header={false}  # or omitted (defaults to false)
  ...
/>
```

**Problem**: Components must know about parent layouts to decide what to render. This violates separation of concerns and makes components tightly coupled to specific page layouts.

### 4. Cascading Hide/Show Logic

PublicGenericPollComponent passes its `hide_header` state down to child components:

```elixir
# public_generic_poll_component.ex line 361
<.live_component
  module={EventasaurusWeb.VotingInterfaceComponent}
  show_header={!@hide_header}  # Inverted logic!
  ...
/>
```

**Problem**: Inverted boolean logic (`show_header={!@hide_header}`) is confusing. Why is one prop named "hide" and the other "show"?

### 5. Page-Specific Layout Duplication

Each page duplicates card/container markup:

**Event Page** (public_event_live.ex lines 1495-1526):
```heex
<div class="bg-white border rounded-xl p-6 mb-8">
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-3">
      <%= poll_emoji(poll.poll_type) %>
      <h2><%= poll.title %></h2>
      <div class="badge"><%= poll.phase %></div>
    </div>
    <.link>View Poll</.link>
  </div>
  <!-- Component here -->
</div>
```

**All Polls Page** (public_polls_live.html.heex lines 69-104):
```heex
<div class="bg-white rounded-lg shadow-sm border p-6">
  <div class="flex items-center justify-between mb-4">
    <div class="flex items-center space-x-3">
      <%= poll_emoji(poll.poll_type) %>
      <h3><%= poll.title %></h3>
    </div>
    <span class="badge"><%= poll_phase_display_text(poll.phase) %></span>
    <.link>View Poll</.link>
  </div>
  <!-- Component here -->
</div>
```

**Problem**: Nearly identical markup repeated across pages. If we want to change card styling, we must update multiple files.

---

## Root Cause Analysis

The fundamental issue: **Mixing presentation concerns with behavioral components**.

**Components should focus on ONE thing**:
- ✅ Behavioral components: Handle state, events, business logic
- ✅ Presentation components: Handle layout, styling, display

**Current components violate this**:
- PublicGenericPollComponent tries to be BOTH behavioral (voting logic) AND presentational (cards, headers)
- Result: Parent pages must use hide/show flags to override component presentation

---

## Recommended Solution: Standardized Mode Pattern

### Core Principle

**Components should accept a `mode` prop that clearly defines layout responsibility**:

```elixir
mode: :full        # Component owns all presentation (headers, containers, chrome)
mode: :content     # Component renders only interactive content, parent handles chrome
```

### Implementation Strategy

#### Phase 1: Standardize Poll Component Props

**Rename inconsistent props to `mode`**:

```elixir
# BEFORE (inconsistent)
<.live_component module={DateSelectionPollComponent} show_container={false} />
<.live_component module={PublicGenericPollComponent} hide_header={true} />
<.live_component module={VotingInterfaceComponent} show_header={false} />

# AFTER (consistent)
<.live_component module={DateSelectionPollComponent} mode={:content} />
<.live_component module={PublicGenericPollComponent} mode={:content} />
<.live_component module={VotingInterfaceComponent} mode={:content} />
```

#### Phase 2: Define Component Mode Contracts

Each component documents what it renders in each mode:

**PublicGenericPollComponent**:

```elixir
# mode: :full (DEFAULT)
# Renders:
#   - Poll header (emoji, title, description, voter count)
#   - Poll options or voting interface
#   - Suggestion form (if phase allows)
# Parent provides: Nothing (self-contained)

# mode: :content
# Renders:
#   - Poll options or voting interface (no header)
#   - Suggestion form (if phase allows)
# Parent provides: Card wrapper, header, stats
```

**VotingInterfaceComponent**:

```elixir
# mode: :full (DEFAULT)
# Renders:
#   - Voting header (title, voter count, instructions)
#   - Voting UI (buttons, ranking, etc.)
# Parent provides: Nothing

# mode: :content
# Renders:
#   - Voting UI only (no header)
# Parent provides: Voting context/instructions
```

#### Phase 3: Update Parent Templates

**Event Page** (use `:content` mode):
```heex
<div class="poll-card">
  <!-- Parent renders header -->
  <div class="poll-card-header">
    <%= poll_emoji(poll.poll_type) %>
    <h2><%= poll.title %></h2>
    <span class="badge"><%= poll.phase %></span>
  </div>

  <!-- Component renders content only -->
  <.live_component
    module={PublicGenericPollComponent}
    mode={:content}
    poll={poll}
    ...
  />
</div>
```

**Individual Poll Page** (use `:full` mode):
```heex
<!-- Page renders large header -->
<div class="page-header">
  <h1 class="text-3xl"><%= @poll.title %></h1>
  <p><%= @poll.description %></p>
</div>

<!-- Component renders with internal header (smaller) -->
<.live_component
  module={PublicGenericPollComponent}
  mode={:full}
  poll={@poll}
  ...
/>
```

#### Phase 4: Extract Shared Card Component (Optional)

Create a reusable `PollCard` component to reduce duplication:

```heex
# lib/eventasaurus_web/components/poll_card.ex
defmodule EventasaurusWeb.Components.PollCard do
  use EventasaurusWeb, :component

  attr :poll, :map, required: true
  attr :event, :map, required: true
  attr :show_view_link, :boolean, default: true
  slot :inner_block, required: true

  def poll_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <!-- Header -->
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center space-x-3">
          <div class="text-2xl"><%= poll_emoji(@poll.poll_type) %></div>
          <div>
            <h3 class="text-lg font-semibold">
              <.link navigate={~p"/#{@event.slug}/polls/#{@poll.number}"}>
                <%= @poll.title %>
              </.link>
            </h3>
            <%= if @poll.description do %>
              <p class="text-sm text-gray-600"><%= @poll.description %></p>
            <% end %>
          </div>
        </div>

        <%= if @show_view_link do %>
          <.link navigate={~p"/#{@event.slug}/polls/#{@poll.number}"}>
            View Poll
          </.link>
        <% end %>
      </div>

      <!-- Content slot -->
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
```

**Usage**:
```heex
<.poll_card poll={poll} event={@event}>
  <.live_component
    module={PublicGenericPollComponent}
    mode={:content}
    poll={poll}
    ...
  />
</.poll_card>
```

---

## Alternative Approaches Considered

### Option A: Component Composition (More Granular)

Split into smaller focused components:
- `PollHeader` - Just metadata display
- `PollOptions` - Just options list
- `PollVotingInterface` - Just voting UI
- `PollSuggestionForm` - Just suggestion form

**Pros**: Maximum flexibility, true single responsibility
**Cons**: Too many small components, complex parent logic, harder to maintain

**Verdict**: ❌ Over-engineering for current needs

### Option B: Slots Pattern (Phoenix 1.7+)

Use slots for custom sections:
```heex
<.poll_component poll={poll}>
  <:header><custom header></:header>
  <:content><voting interface></:content>
</.poll_component>
```

**Pros**: Very flexible, modern Phoenix pattern
**Cons**: Requires Phoenix 1.7+, more complex API

**Verdict**: ⚠️ Good future direction, but mode pattern is simpler for now

### Option C: Multiple Component Variants

Create separate components for each use case:
- `PollCardComponent` - For list views
- `PollDetailComponent` - For detail views
- `PollInlineComponent` - For embedded views

**Pros**: Clear separation, no conditional logic
**Cons**: Code duplication, harder to maintain consistency

**Verdict**: ❌ Too much duplication

---

## Migration Plan

### Step 1: Add Mode Support (No Breaking Changes)
- Add `mode` prop to components (defaults to `:full` for backward compatibility)
- Keep old props (`hide_header`, `show_header`, `show_container`) working
- Add deprecation warnings in logs

### Step 2: Update Templates (One Page at a Time)
- Convert Event Page to use `mode={:content}`
- Convert All Polls Page to use `mode={:content}`
- Convert Individual Poll Page to use `mode={:full}`
- Test each page thoroughly

### Step 3: Remove Old Props
- Remove `hide_header` from PublicGenericPollComponent
- Remove `show_header` from VotingInterfaceComponent
- Remove `show_container` from DateSelectionPollComponent
- Update all remaining usages to `mode`

### Step 4: Extract PollCard (Optional)
- Create shared `PollCard` component
- Refactor pages to use `<.poll_card>` wrapper
- Remove duplicated card markup

---

## Benefits of Proposed Solution

1. **Clear Contracts**: Each component documents what `mode: :full` and `mode: :content` include
2. **Consistent API**: All components use same `mode` prop
3. **Loose Coupling**: Components don't need to know about parent layouts
4. **Easy to Extend**: Add new modes (e.g., `:compact`, `:minimal`) without breaking existing code
5. **Better Maintainability**: Change card styling in one place (PollCard component)
6. **No Duplicate Info**: Clear responsibility for who renders what in each mode
7. **Backward Compatible**: Migration can happen incrementally

---

## Testing Considerations

After refactor, verify:
- ✅ Event page shows polls with cards, no duplicate headers
- ✅ All Polls page shows polls with cards, no duplicate headers
- ✅ Individual Poll page shows full poll with internal headers
- ✅ Voting works correctly in all three views
- ✅ Suggestion forms work correctly
- ✅ Mobile responsive layouts still work
- ✅ All poll types (movie, music, date, custom, places, time) render correctly

---

## Conclusion

**Current State**: Messy, inconsistent, tightly coupled
**Proposed State**: Clean, consistent, modular

**Recommendation**: Implement Mode Pattern (Phase 1-3)

**Optional Enhancement**: Extract PollCard component (Phase 4)

**Estimated Effort**:
- Phase 1-3: ~4 hours (standardize props, update templates)
- Phase 4: ~2 hours (extract PollCard component)
- Testing: ~2 hours

**Total**: ~8 hours for complete refactor

---

## Open Questions

1. Should `mode` be an atom (`:full`, `:content`) or string (`"full"`, `"content"`)?
   - **Recommendation**: Atom (more idiomatic Elixir)

2. Should we support additional modes like `:minimal` or `:compact`?
   - **Recommendation**: Start with just `:full` and `:content`, add more only if needed

3. Should PollCard be a component or a function component?
   - **Recommendation**: Function component (simpler, no state needed)

4. How to handle the Event Page which already shows polls without calling them out as "duplicate"?
   - **Recommendation**: Event page should ALSO use `mode: :content` pattern for consistency

---

## Files Requiring Changes

### Phase 1-3 (Core Refactor)
- `lib/eventasaurus_web/live/components/public_generic_poll_component.ex` - Add mode prop
- `lib/eventasaurus_web/live/components/voting_interface_component.ex` - Add mode prop
- `lib/eventasaurus_web/live/components/date_selection_poll_component.ex` - Add mode prop
- `lib/eventasaurus_web/live/public_event_live.ex` - Update component calls
- `lib/eventasaurus_web/live/public_polls_live.html.heex` - Update component calls
- `lib/eventasaurus_web/live/public_poll_live.html.heex` - Update component calls

### Phase 4 (Optional Enhancement)
- `lib/eventasaurus_web/components/poll_card.ex` - New file
- All parent templates - Use new PollCard wrapper

---

_Document created: 2025-10-14_
_Status: Proposal - No code changes yet_
