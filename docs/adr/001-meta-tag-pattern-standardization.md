# ADR 001: Meta Tag Pattern Standardization

**Status:** Accepted
**Date:** 2025-01-29
**Decision Makers:** Development Team
**Context:** Phase 2.1 of SEO & Social Cards Code Consolidation (#2058)

## Context

We have two different approaches for managing SEO meta tags across our LiveView pages:

### Pattern A: Raw HTML String (PublicEventShowLive)
```elixir
defp generate_seo_data(event, breadcrumb_items, socket) do
  # ... build values ...

  open_graph_html = """
  <!-- Open Graph meta tags -->
  <meta property="og:type" content="event" />
  <meta property="og:title" content="#{escaped_title}" />
  <meta property="og:description" content="#{escaped_description}" />
  <meta property="og:image" content="#{escaped_image}" />
  <!-- ... more meta tags ... -->
  """

  %{
    json_ld: combined_json_ld,
    open_graph: open_graph_html,  # Raw HTML string
    canonical_url: canonical_url
  }
end
```

Then in the template:
```heex
<%= raw(@seo_data.open_graph) %>
```

### Pattern B: Individual Assigns (CityLive.Index)
```elixir
socket
|> assign(:meta_title, page_title(city))
|> assign(:meta_description, meta_description(city))
|> assign(:meta_image, social_card_url)
|> assign(:canonical_url, canonical_url)
|> assign(:json_ld, json_ld)
```

Then in the root layout template, these individual assigns are used to render meta tags.

## Decision

**We will standardize on Pattern B: Individual Assigns**

All LiveView pages must use individual socket assigns for SEO metadata:
- `:page_title` - Page title for `<title>` tag
- `:meta_title` - Open Graph / Twitter Card title
- `:meta_description` - Meta description for SEO and social sharing
- `:meta_image` - Social card image URL
- `:meta_type` - Open Graph type (e.g., "website", "event", "article")
- `:canonical_url` - Canonical URL for SEO
- `:json_ld` - JSON-LD structured data
- `:hreflang_path` (optional) - Path for hreflang alternate links

## Rationale

### Advantages of Pattern B (Individual Assigns)

1. **Separation of Concerns**
   - LiveView focuses on data logic
   - Templates handle presentation
   - Follows MVC/MVVM architectural principles

2. **Follows Phoenix Conventions**
   - Socket assigns are the idiomatic way to pass data to templates
   - Aligns with Phoenix's design philosophy
   - Familiar pattern for all Elixir/Phoenix developers

3. **Better Testability**
   - Can assert individual assign values directly
   - No need to parse HTML strings in tests
   - Easier to write unit tests

4. **More Flexible and Composable**
   - Individual values can be consumed by different layouts
   - Can selectively override specific meta tags
   - Easier to add new meta tags without breaking existing code

5. **Type Safety**
   - Can add `@type` specs for expected assigns
   - Compile-time checks with tools like Dialyzer
   - Better IDE autocomplete support

6. **Maintainability**
   - Changes to individual values don't require touching HTML strings
   - Easier to debug (inspect individual assigns)
   - Clear contract between LiveView and template

7. **Reusability**
   - Meta tag rendering logic can be centralized in root layout
   - Consistent rendering across all pages
   - Single source of truth for meta tag format

### Disadvantages of Pattern A (Raw HTML)

1. **Mixing Concerns**
   - HTML generation in business logic layer
   - Violates separation of concerns

2. **Harder to Test**
   - Must parse HTML to verify values
   - More complex test setup

3. **Less Flexible**
   - Can't access individual values without parsing
   - Difficult to selectively override tags

4. **Not Idiomatic**
   - Goes against Phoenix conventions
   - Confusing for new developers

5. **Security Risk**
   - Using `raw/1` in templates bypasses XSS protection
   - Must manually escape all values (error-prone)

## Implementation Plan

### Phase 1: Create SEO Helper Module
Create `EventasaurusWeb.Helpers.SEOHelpers` to standardize SEO data generation:

```elixir
defmodule EventasaurusWeb.Helpers.SEOHelpers do
  @moduledoc """
  Helpers for assigning SEO meta tags and structured data in LiveViews.

  This module provides a standardized way to set meta tags for:
  - Open Graph (Facebook, LinkedIn)
  - Twitter Cards
  - Standard SEO meta tags
  - JSON-LD structured data
  - Canonical URLs
  """

  @doc """
  Assigns standard SEO meta tags to a LiveView socket.

  ## Options
    * `:title` - Page title
    * `:description` - Meta description
    * `:image` - Social card image URL
    * `:type` - Open Graph type (default: "website")
    * `:canonical_path` - Canonical URL path (will be prefixed with base URL)
  """
  def assign_meta_tags(socket, opts)

  @doc """
  Builds a social card URL for an entity with cache-busting hash.
  """
  def build_social_card_url(entity, type, stats \\ %{})

  @doc """
  Builds a canonical URL from a path.
  """
  def build_canonical_url(path)
end
```

### Phase 2: Update Root Layout Template
Modify `root.html.heex` to consume individual assigns:

```heex
<!-- SEO Meta Tags -->
<title><%= assigns[:page_title] || "Wombie - Discover Events" %></title>
<meta name="description" content={assigns[:meta_description] || "Discover events happening near you"} />

<!-- Canonical URL -->
<%= if assigns[:canonical_url] do %>
  <link rel="canonical" href={@canonical_url} />
<% end %>

<!-- Open Graph Tags -->
<meta property="og:type" content={assigns[:meta_type] || "website"} />
<meta property="og:title" content={assigns[:meta_title] || assigns[:page_title] || "Wombie"} />
<meta property="og:description" content={assigns[:meta_description]} />
<%= if assigns[:meta_image] do %>
  <meta property="og:image" content={@meta_image} />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
<% end %>
<%= if assigns[:canonical_url] do %>
  <meta property="og:url" content={@canonical_url} />
<% end %>

<!-- Twitter Card Tags -->
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content={assigns[:meta_title] || assigns[:page_title]} />
<meta name="twitter:description" content={assigns[:meta_description]} />
<%= if assigns[:meta_image] do %>
  <meta name="twitter:image" content={@meta_image} />
<% end %>

<!-- JSON-LD Structured Data -->
<%= if assigns[:json_ld] do %>
  <script type="application/ld+json"><%= raw(@json_ld) %></script>
<% end %>
```

### Phase 3: Migrate Existing LiveViews
Update all LiveViews to use Pattern B:
- `PublicEventShowLive` - Remove `open_graph_html` generation, use individual assigns
- `CityLive.Index` - Already using Pattern B, ensure it uses SEOHelpers
- `PublicPollLive` - Migrate to Pattern B
- `ContainerDetailLive` - Migrate to Pattern B

### Phase 4: Update Tests
Update all tests to assert individual assigns instead of parsing HTML.

## Consequences

### Positive
- Consistent pattern across all LiveView pages
- Easier onboarding for new developers
- Better testability and maintainability
- Type-safe SEO metadata
- Centralized meta tag rendering

### Negative
- Requires migration of existing `PublicEventShowLive`
- Needs updates to existing tests
- May temporarily break SEO if migration is incomplete

### Neutral
- Requires creating new `SEOHelpers` module
- Needs documentation updates

## Migration Strategy

1. ✅ **Create ADR** (this document)
2. ⬜ **Create `SEOHelpers` module** with standardized functions
3. ⬜ **Update root layout template** to render from individual assigns
4. ⬜ **Migrate `PublicEventShowLive`** to use individual assigns
5. ⬜ **Migrate other LiveViews** to use `SEOHelpers`
6. ⬜ **Update tests** to verify individual assigns
7. ⬜ **Remove `open_graph_html` pattern** entirely
8. ⬜ **Document new pattern** in SEO best practices guide

## References

- Issue #2058: SEO & Social Cards Code Consolidation
- Phoenix LiveView Documentation on assigns
- Open Graph Protocol: https://ogp.me/
- Twitter Card Documentation: https://developer.twitter.com/en/docs/twitter-for-websites/cards

## Review and Approval

**Reviewed by:** Development Team
**Approved by:** Tech Lead
**Implementation:** In Progress (Phase 2 of Issue #2058)
