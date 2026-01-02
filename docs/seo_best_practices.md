# SEO Best Practices Guide

**Version:** 1.1.0
**Last Updated:** 2025-01-02
**Maintainer:** Development Team

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [JSON-LD Structured Data](#json-ld-structured-data)
4. [Social Media Cards](#social-media-cards)
5. [Meta Tags & Open Graph](#meta-tags--open-graph)
6. [SEO Helper Modules](#seo-helper-modules)
7. [Testing & Validation](#testing--validation)
8. [Common Patterns](#common-patterns)
9. [Troubleshooting](#troubleshooting)
10. [Resources](#resources)

---

## Overview

This guide documents SEO best practices for the Eventasaurus/Wombie platform, covering:

- **Structured Data**: JSON-LD schemas for events, cities, venues, and breadcrumbs
- **Social Cards**: Dynamic Open Graph images for Facebook, Twitter, LinkedIn, etc.
- **Meta Tags**: Standardized approach for page metadata
- **Helper Modules**: Reusable utilities for consistent SEO implementation

### Architecture Principles

1. **Separation of Concerns**: LiveViews provide data, templates render HTML
2. **DRY (Don't Repeat Yourself)**: Centralized logic in helper modules
3. **Type Safety**: Use Elixir typespecs for all public APIs
4. **Standards Compliance**: Follow Schema.org, Open Graph Protocol, Twitter Card specs
5. **Performance**: Cache-busted social cards, optimized image delivery

### Related Documentation

- [ADR 001: Meta Tag Pattern Standardization](adr/001-meta-tag-pattern-standardization.md)
- [Social Card Architecture Guide](#social-card-system-architecture) (this document)
- [Helper Module Reference](#seo-helper-modules) (this document)

---

## Quick Start

### Adding SEO to a New LiveView Page

```elixir
defmodule EventasaurusWeb.MyNewLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.MyEntitySchema

  @impl true
  def mount(_params, _session, socket) do
    # 1. CRITICAL: Capture request URI for correct URL generation (ngrok support)
    raw_uri = get_connect_info(socket, :uri)
    request_uri =
      cond do
        match?(%URI{}, raw_uri) -> raw_uri
        is_binary(raw_uri) -> URI.parse(raw_uri)
        true -> nil
      end

    # 2. Load your data
    entity = load_my_entity()

    # 3. Generate JSON-LD structured data
    json_ld = MyEntitySchema.generate(entity)

    # 4. Generate social card URL (if applicable)
    social_card_url = SEOHelpers.build_social_card_url(entity, :my_type)

    # 5. Assign SEO metadata using helper
    socket =
      socket
      |> assign(:entity, entity)
      |> SEOHelpers.assign_meta_tags(
        title: "#{entity.name} - Wombie",
        description: entity.description,
        image: social_card_url,
        type: "website",
        canonical_path: "/my-route/#{entity.slug}",
        json_ld: json_ld,
        request_uri: request_uri  # CRITICAL: Pass request_uri for ngrok/proxy support
      )

    {:ok, socket}
  end
end
```

> **⚠️ IMPORTANT:** Always capture and pass `request_uri` to `SEOHelpers.assign_meta_tags/2`. Without it, URLs will use static configuration (localhost in development) instead of the actual request host (ngrok, production domain, etc.). This causes social media crawlers to fail because they cannot access localhost URLs.
>
> See [Development & ngrok Support](#development--ngrok-support) for more details.

### ⛔ Critical: LiveView Lifecycle and SEO Timing

**SEO metadata MUST be set synchronously in `mount/3` or `handle_params/3`.** Social media crawlers (Facebook, Twitter, LinkedIn, etc.) only see the initial server-rendered HTML response—they do not execute JavaScript or wait for WebSocket connections.

```elixir
# ✅ CORRECT: SEO in mount (synchronous, before initial render)
def mount(_params, _session, socket) do
  entity = load_entity()
  socket =
    socket
    |> assign(:entity, entity)
    |> SEOHelpers.assign_meta_tags(title: entity.name, ...)
  {:ok, socket}
end

# ✅ CORRECT: SEO in handle_params (synchronous, on each navigation)
def handle_params(%{"slug" => slug}, _url, socket) do
  entity = load_entity(slug)
  socket =
    socket
    |> assign(:entity, entity)
    |> SEOHelpers.assign_meta_tags(title: entity.name, ...)
  {:noreply, socket}
end

# ❌ WRONG: SEO in handle_info (async, after WebSocket connects)
def handle_info(:load_data, socket) do
  entity = load_entity()
  # Crawlers NEVER see this - they're already gone!
  socket = SEOHelpers.assign_meta_tags(socket, title: entity.name, ...)
  {:noreply, socket}
end
```

**Why This Matters:**
1. **Server-Side Rendering (SSR)**: `mount` runs during the initial HTTP request
2. **Crawler Behavior**: Facebook/Twitter fetch the HTML once and parse `<meta>` tags immediately
3. **No JavaScript**: Crawlers don't wait for LiveView's WebSocket or `handle_info` callbacks
4. **Timing**: `handle_info` runs *after* the initial HTML is already sent to the client

**Common Mistake - Empty String vs `nil`:**

```elixir
# ❌ WRONG: Empty string is TRUTHY in Elixir
def mount(_params, _session, socket) do
  socket = assign(socket, :open_graph, "")  # This is truthy!
  {:ok, socket}
end

def handle_info(:load_data, socket) do
  socket = assign(socket, :open_graph, build_og_tags())  # Too late!
  {:noreply, socket}
end

# In template: if @open_graph do ... end
# Result: Empty string passes the condition, but contains no useful data
```

```elixir
# ✅ CORRECT: Set actual SEO data in mount, use nil for "not loaded yet"
def mount(_params, _session, socket) do
  entity = load_entity()
  og_tags = build_og_tags(entity)
  socket =
    socket
    |> assign(:open_graph, og_tags)  # Real data, set synchronously
    |> SEOHelpers.assign_meta_tags(...)
  {:ok, socket}
end
```

**Reference Implementations:**
- `venue_live/show.ex` - SEO in `handle_params` via `load_and_assign_venue/2`
- `public_event_show_live.ex` - SEO in `handle_params`
- `city_live/index.ex` - SEO in `mount`

### What Gets Generated

The `SEOHelpers.assign_meta_tags/2` function assigns the following to your socket:

- `:page_title` - Used in `<title>` tag
- `:meta_title` - Open Graph / Twitter title
- `:meta_description` - Meta description for all platforms
- `:meta_image` - Social card image URL
- `:meta_type` - Open Graph type ("website", "event", "article")
- `:canonical_url` - Canonical URL for SEO
- `:json_ld` - JSON-LD structured data

These are automatically consumed by the root layout template.

---

## JSON-LD Structured Data

JSON-LD (JavaScript Object Notation for Linked Data) provides structured data that search engines use to understand your content and display rich results.

### Why JSON-LD Matters

- **Rich Search Results**: Google displays enhanced results with images, ratings, dates
- **Knowledge Graph**: Your content can appear in Google's Knowledge Graph
- **Voice Search**: Structured data improves voice search optimization
- **SEO Rankings**: Indirect ranking boost through better CTR from rich results

### Available Schema Modules

| Module | Schema Type | Use Case | Status |
|--------|-------------|----------|--------|
| `PublicEventSchema` | Event | Event detail pages | ✅ Active |
| `CitySchema` | City | City discovery pages | ✅ Active |
| `LocalBusinessSchema` | LocalBusiness | Venue pages | ✅ Active |
| `BreadcrumbListSchema` | BreadcrumbList | Navigation breadcrumbs | ✅ Active |

### Schema Type Selection Guide

**Use `Event` schema when:**
- Displaying a specific event with date/time
- Event has a location and organizer
- Event has tickets or registration

**Use `City` schema when:**
- Displaying city-level event discovery
- Showcasing city statistics and venues
- Aggregating multiple events by location

**Use `LocalBusiness` schema when:**
- Displaying venue information
- Venue has address, hours, contact info
- Venue hosts multiple events

**Use `BreadcrumbList` schema when:**
- Page has hierarchical navigation
- Multiple levels of navigation exist
- Improves site structure understanding

### Creating a New JSON-LD Schema

#### Step 1: Create Schema Module

```elixir
# lib/eventasaurus_web/json_ld/my_entity_schema.ex
defmodule EventasaurusWeb.JsonLd.MyEntitySchema do
  @moduledoc """
  Generates JSON-LD structured data for MyEntity pages.

  Implements Schema.org MyEntityType schema for rich search results.

  ## Schema Documentation
  - https://schema.org/MyEntityType
  - https://developers.google.com/search/docs/appearance/structured-data/my-entity
  """

  alias EventasaurusWeb.UrlHelper

  @doc """
  Generates JSON-LD structured data for a MyEntity.

  ## Required Fields
  - `:name` - Entity name
  - `:description` - Entity description
  - `:url` - Entity URL (slug)

  ## Returns
  JSON-encoded string ready for `<script type="application/ld+json">` tag.
  """
  @spec generate(map()) :: String.t()
  def generate(entity) do
    base_url = UrlHelper.get_base_url()

    schema = %{
      "@context" => "https://schema.org",
      "@type" => "MyEntityType",
      "name" => entity.name,
      "description" => entity.description || "",
      "url" => "#{base_url}/my-route/#{entity.slug}",
      # Add schema-specific fields
      "identifier" => entity.id,
      "dateCreated" => format_date(entity.inserted_at),
      "dateModified" => format_date(entity.updated_at)
    }

    # Remove nil values for cleaner output
    schema = Enum.reject(schema, fn {_k, v} -> is_nil(v) end) |> Map.new()

    Jason.encode!(schema, pretty: false)
  end

  defp format_date(nil), do: nil
  defp format_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_date(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
```

#### Step 2: Use in LiveView

```elixir
json_ld = MyEntitySchema.generate(entity)

socket
|> SEOHelpers.assign_meta_tags(
  title: entity.name,
  description: entity.description,
  json_ld: json_ld  # Pass to helper
)
```

### Schema.org Compliance Checklist

- [ ] All required properties included
- [ ] Valid Schema.org type selected
- [ ] URLs are absolute (include protocol and domain)
- [ ] Dates in ISO 8601 format
- [ ] No HTML in text fields (plain text only)
- [ ] Images include width/height/format
- [ ] Addresses include all components
- [ ] Testing with Google Rich Results Test

### Google Rich Results Guidelines

**Event Schema Requirements:**
```elixir
%{
  "@context" => "https://schema.org",
  "@type" => "Event",
  "name" => "Required: Event title",
  "startDate" => "Required: ISO 8601 date",
  "location" => "Required: Place or VirtualLocation",
  # Optional but recommended
  "description" => "Event description",
  "image" => ["https://example.com/image.jpg"],
  "endDate" => "ISO 8601 date",
  "organizer" => %{"@type" => "Organization", "name" => "Organizer name"},
  "offers" => %{"@type" => "Offer", "price" => "0", "priceCurrency" => "USD"}
}
```

**Common Validation Errors:**
1. Missing required fields
2. Invalid date format (must be ISO 8601)
3. Relative URLs instead of absolute
4. HTML in text fields
5. Incorrect @type value

---

## Social Media Cards

Social media cards are custom images and metadata that appear when your pages are shared on platforms like Facebook, Twitter, LinkedIn, WhatsApp, and Slack.

### Social Card System Architecture

```
User shares URL → Platform fetches metadata → Finds social card URL →
Requests PNG → Server generates/caches card → Platform displays preview
```

### Supported Card Types

| Type | URL Pattern | Controller | Use Case |
|------|-------------|------------|----------|
| Event | `/:slug/social-card-:hash.png` | `EventSocialCardController` | Event pages |
| Poll | `/:slug/polls/:num/social-card-:hash.png` | `PollSocialCardController` | Poll pages |
| City | `/social-cards/city/:slug/:hash.png` | `CitySocialCardController` | City pages |

### Hash-Based Cache Busting

Social cards use content-based hashing for intelligent cache invalidation:

**How it works:**
1. Generate hash from card content (title, description, image, stats)
2. Include hash in URL: `/event/social-card-a1b2c3d4.png`
3. When content changes, hash changes automatically
4. Old URL becomes invalid, social platforms re-fetch new card
5. Unchanged content = same hash = maximum caching

**Benefits:**
- Social platforms cache cards for up to 1 year
- Content updates force immediate re-fetch
- No manual cache invalidation needed
- CDN-friendly (long cache headers safe)

**Hash Generation Example:**
```elixir
# Events: Hash includes title, description, image, theme, updated_at
event_hash = HashGenerator.generate_hash(event, :event)
# => "a1b2c3d4"

# Polls: Hash includes title, type, phase, options, event theme
poll_hash = HashGenerator.generate_hash(poll, :poll)
# => "e5f6g7h8"

# Cities: Hash includes name, stats (events, venues, categories)
city_hash = HashGenerator.generate_hash(city_with_stats, :city)
# => "b2c3d4e5"
```

### SVG to PNG Conversion Process

Social cards are generated on-demand from SVG templates:

```
1. Request: GET /event/social-card-abc123.png
2. Controller: Validate hash, fetch event data
3. Template: Render SVG with event data (1200x630px)
4. Converter: rsvg-convert SVG → PNG
5. Response: Serve PNG with cache headers (1 year)
6. Cleanup: Delete temporary PNG file
```

**System Dependencies:**
- **librsvg2-bin** (provides `rsvg-convert` command)
- Install: `apt-get install librsvg2-bin` (Ubuntu/Debian)
- Verify: `rsvg-convert --version`

**SVG Template Guidelines:**
- Dimensions: 1200x630px (Open Graph standard)
- Safe zone: Keep text within 1140x570px (avoid cropping)
- Font sizes: Minimum 24px for readability
- Contrast: High contrast for readability on mobile
- Fallbacks: Handle missing data gracefully

### Adding a New Social Card Type

#### Step 1: Create SVG Template

```elixir
# lib/eventasaurus_web/views/social_card_view.ex
def render_my_entity_card_svg(entity) do
  """
  <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
    <!-- Background -->
    <rect width="1200" height="630" fill="#1a1a1a"/>

    <!-- Safe zone guide (remove in production) -->
    <!-- <rect x="30" y="30" width="1140" height="570" fill="none" stroke="#ff0000"/> -->

    <!-- Content -->
    <text x="60" y="100" font-family="Arial, sans-serif" font-size="48" fill="#ffffff" font-weight="bold">
      #{escape_xml(entity.title)}
    </text>

    <text x="60" y="160" font-family="Arial, sans-serif" font-size="24" fill="#cccccc">
      #{escape_xml(entity.subtitle)}
    </text>

    <!-- Logo -->
    <text x="60" y="580" font-family="Arial, sans-serif" font-size="20" fill="#666666">
      Wombie
    </text>
  </svg>
  """
end

# XML escape helper (prevent injection)
defp escape_xml(nil), do: ""
defp escape_xml(text) when is_binary(text) do
  text
  |> String.replace("&", "&amp;")
  |> String.replace("<", "&lt;")
  |> String.replace(">", "&gt;")
  |> String.replace("\"", "&quot;")
  |> String.replace("'", "&#39;")
end
```

#### Step 2: Extend Hash Generator

```elixir
# lib/eventasaurus/social_cards/hash_generator.ex

# Add fingerprint function for your entity type
defp build_fingerprint(entity, :my_entity) do
  %{
    type: :my_entity,
    id: Map.get(entity, :id),
    title: Map.get(entity, :title, ""),
    description: Map.get(entity, :description, ""),
    # Include any fields that affect visual appearance
    stats: Map.get(entity, :stats, %{}),
    updated_at: format_timestamp(Map.get(entity, :updated_at)),
    version: @social_card_version
  }
end

# Update generate_url_path to handle your entity type
def generate_url_path(data, :my_entity) when is_map(data) do
  hash = generate_hash(data, :my_entity)
  slug = Map.get(data, :slug, "unknown")
  "/my-entities/#{slug}/social-card-#{hash}.png"
end
```

#### Step 3: Create Controller

```elixir
# lib/eventasaurus_web/controllers/my_entity_social_card_controller.ex
defmodule EventasaurusWeb.MyEntitySocialCardController do
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusApp.MyContext
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.Helpers.SocialCardHelpers
  import EventasaurusWeb.SocialCardView

  def generate_card_by_slug(conn, %{"slug" => slug, "hash" => hash, "rest" => rest}) do
    Logger.info("Social card requested for entity: #{slug}, hash: #{hash}")

    final_hash = SocialCardHelpers.parse_hash(hash, rest)

    case MyContext.get_entity_by_slug(slug) do
      nil ->
        Logger.warning("Entity not found: #{slug}")
        send_resp(conn, 404, "Entity not found")

      entity ->
        if SocialCardHelpers.validate_hash(entity, final_hash, :my_entity) do
          Logger.info("Hash validated for #{slug}")

          # Render SVG
          svg_content = render_my_entity_card_svg(entity)

          # Generate PNG and serve
          case SocialCardHelpers.generate_png(svg_content, slug, entity) do
            {:ok, png_data} ->
              SocialCardHelpers.send_png_response(conn, png_data, final_hash)

            {:error, error} ->
              SocialCardHelpers.send_error_response(conn, error)
          end
        else
          expected_hash = HashGenerator.generate_hash(entity, :my_entity)
          SocialCardHelpers.send_hash_mismatch_redirect(
            conn, entity, slug, expected_hash, final_hash, :my_entity
          )
        end
    end
  end
end
```

#### Step 4: Add Route

```elixir
# lib/eventasaurus_web/router.ex
scope "/", EventasaurusWeb do
  pipe_through :browser

  # Social card route
  get "/my-entities/:slug/social-card-:hash/*rest",
      MyEntitySocialCardController, :generate_card_by_slug
end
```

#### Step 5: Use in LiveView

```elixir
social_card_url = SEOHelpers.build_social_card_url(entity, :my_entity)

socket
|> SEOHelpers.assign_meta_tags(
  title: entity.title,
  description: entity.description,
  image: social_card_url,  # Social card URL with hash
  type: "website",
  canonical_path: "/my-entities/#{entity.slug}",
  json_ld: json_ld
)
```

### Social Card Dimensions & Specifications

**Open Graph (Facebook, LinkedIn, WhatsApp):**
- Recommended: 1200x630px (1.91:1 ratio)
- Minimum: 600x315px
- Maximum: 8MB file size
- Format: PNG or JPEG

**Twitter Cards:**
- Summary Large Image: 1200x628px (same as OG)
- Summary: 120x120px minimum
- Maximum: 5MB file size
- Format: PNG, JPEG, GIF, WebP

**Platform-Specific Notes:**
- **Facebook**: Caches aggressively (use hash-based URLs)
- **Twitter**: Validates images, shows broken icon if invalid
- **LinkedIn**: Prefers 1200x627px for articles
- **WhatsApp**: Uses Open Graph, shows preview in chat
- **Slack**: Unfurls links with Open Graph data
- **Discord**: Similar to Slack, uses Open Graph

---

## Meta Tags & Open Graph

### Standard Pattern (Individual Assigns)

Per [ADR 001](adr/001-meta-tag-pattern-standardization.md), we use individual socket assigns consumed by the root layout:

```elixir
# In LiveView
socket
|> SEOHelpers.assign_meta_tags(
  title: "Page Title",
  description: "Page description for SEO",
  image: "https://example.com/image.png",
  type: "website",
  canonical_url: "https://example.com/page",
  json_ld: json_ld_string
)

# Assigns created:
# :page_title - For <title> tag
# :meta_title - For og:title
# :meta_description - For meta description
# :meta_image - For og:image
# :meta_type - For og:type
# :canonical_url - For canonical link
# :json_ld - For structured data
```

### Root Layout Integration

The root layout (`root.html.heex`) consumes these assigns and renders meta tags:

```heex
<!-- Page Title -->
<title><%= assigns[:page_title] || "Wombie - Discover Events" %></title>

<!-- Meta Description -->
<meta name="description" content={assigns[:meta_description] || "Discover events"} />

<!-- Canonical URL -->
<%= if assigns[:canonical_url] do %>
  <link rel="canonical" href={@canonical_url} />
<% end %>

<!-- Open Graph Tags -->
<meta property="og:type" content={assigns[:meta_type] || "website"} />
<meta property="og:title" content={assigns[:meta_title] || assigns[:page_title]} />
<meta property="og:description" content={assigns[:meta_description]} />
<%= if assigns[:meta_image] do %>
  <meta property="og:image" content={@meta_image} />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
<% end %>
<meta property="og:url" content={assigns[:canonical_url] || request_url(@conn)} />
<meta property="og:site_name" content="Wombie" />

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

### Open Graph Type Reference

| Type | Use Case | Required Properties |
|------|----------|---------------------|
| `website` | General pages, city discovery | title, description, image, url |
| `event` | Event detail pages | title, description, image, url, event properties |
| `article` | Blog posts, news articles | title, description, image, url, published_time |
| `profile` | User profiles | title, description, image, url, first_name, last_name |
| `video.movie` | Movie listings | title, description, image, url, video properties |

### Common Meta Tag Mistakes

❌ **Don't:**
```elixir
# Generating raw HTML in LiveView
open_graph_html = """
<meta property="og:title" content="#{title}" />
"""
assign(socket, :open_graph, open_graph_html)
```

✅ **Do:**
```elixir
# Use individual assigns and SEOHelpers
socket
|> SEOHelpers.assign_meta_tags(
  title: title,
  description: description,
  image: image_url,
  type: "website",
  canonical_path: "/page"
)
```

❌ **Don't:**
```elixir
# Relative image URLs
image: "/images/card.png"
```

✅ **Do:**
```elixir
# Absolute image URLs
image: "https://wombie.com/images/card.png"
# Or use helpers that handle this
image: social_card_url  # Already absolute from SEOHelpers
```

---

## SEO Helper Modules

### SEOHelpers

**Location:** `lib/eventasaurus_web/helpers/seo_helpers.ex`

**Purpose:** Standardized SEO metadata assignment for LiveViews

**Key Functions:**

#### `assign_meta_tags/2`

Assigns all standard SEO meta tags to a LiveView socket.

```elixir
@spec assign_meta_tags(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()

# Usage
socket
|> SEOHelpers.assign_meta_tags(
  title: "Required: Page title",
  description: "Required: Meta description",
  image: "Optional: Social card URL",
  type: "Optional: og:type (default: website)",
  canonical_path: "Optional: Path for canonical URL",
  canonical_url: "Optional: Full canonical URL (overrides path)",
  json_ld: "Optional: JSON-LD structured data"
)
```

#### `build_social_card_url/3`

Generates social card URL with cache-busting hash.

```elixir
@spec build_social_card_url(map(), atom(), keyword()) :: String.t()

# For events
event_card = SEOHelpers.build_social_card_url(event, :event)
# => "https://wombie.com/summer-fest/social-card-a1b2c3d4.png"

# For polls (requires event)
poll_card = SEOHelpers.build_social_card_url(poll, :poll, event: event)
# => "https://wombie.com/summer-fest/polls/1/social-card-e5f6g7h8.png"

# For cities (requires stats)
city_card = SEOHelpers.build_social_card_url(city, :city, stats: stats)
# => "https://wombie.com/social-cards/city/warsaw/b2c3d4e5.png"
```

#### `build_canonical_url/1`

Converts relative path to absolute canonical URL.

```elixir
@spec build_canonical_url(String.t()) :: String.t()

SEOHelpers.build_canonical_url("/events/summer-festival")
# => "https://wombie.com/events/summer-festival"
```

### SocialCardHelpers

**Location:** `lib/eventasaurus_web/helpers/social_card_helpers.ex`

**Purpose:** Shared logic for social card controllers

**Key Functions:**

#### `parse_hash/2`

Parses hash from route parameters.

```elixir
@spec parse_hash(String.t(), list()) :: String.t()

# Route: /event/social-card-abc123.png
# params: %{"hash" => "abc123", "rest" => ["png"]}
final_hash = SocialCardHelpers.parse_hash("abc123", ["png"])
# => "abc123"
```

#### `validate_hash/3`

Validates hash matches current data.

```elixir
@spec validate_hash(map(), String.t(), atom()) :: boolean()

if SocialCardHelpers.validate_hash(event, hash, :event) do
  # Hash is valid, serve cached card
else
  # Hash mismatch, redirect to current URL
end
```

#### `generate_png/3`

Converts SVG to PNG and returns binary data.

```elixir
@spec generate_png(String.t(), String.t(), map()) :: {:ok, binary()} | {:error, atom()}

svg_content = render_event_card_svg(event)

case SocialCardHelpers.generate_png(svg_content, event.slug, event) do
  {:ok, png_data} ->
    # Serve PNG
  {:error, :dependency_missing} ->
    # rsvg-convert not installed
  {:error, _reason} ->
    # Other error
end
```

#### `send_png_response/3`

Sends PNG with optimal cache headers.

```elixir
@spec send_png_response(Plug.Conn.t(), binary(), String.t()) :: Plug.Conn.t()

conn
|> SocialCardHelpers.send_png_response(png_data, hash)
# Sets: Content-Type, Cache-Control (1 year), ETag
```

### UrlHelper

**Location:** `lib/eventasaurus_web/url_helper.ex`

**Purpose:** Centralized URL generation

**Key Functions:**

#### `get_base_url/0`

Gets application base URL from endpoint config.

```elixir
@spec get_base_url() :: String.t()

base_url = UrlHelper.get_base_url()
# => "https://wombie.com" (production)
# => "http://localhost:4000" (development)
```

#### `build_url/1`

Builds absolute URL from relative path.

```elixir
@spec build_url(String.t()) :: String.t()

UrlHelper.build_url("/events/summer-festival")
# => "https://wombie.com/events/summer-festival"
```

### HashGenerator

**Location:** `lib/eventasaurus/social_cards/hash_generator.ex`

**Purpose:** Content-based hashing for cache busting

**Key Functions:**

#### `generate_hash/2`

Generates content hash for entity.

```elixir
@spec generate_hash(map(), atom()) :: String.t()

hash = HashGenerator.generate_hash(event, :event)
# => "a1b2c3d4" (8-character hex)
```

#### `generate_url_path/2`

Generates full URL path with hash.

```elixir
@spec generate_url_path(map(), atom()) :: String.t()

path = HashGenerator.generate_url_path(event, :event)
# => "/summer-festival/social-card-a1b2c3d4.png"
```

#### `validate_hash/3`

Validates hash against current data.

```elixir
@spec validate_hash(map(), String.t(), atom()) :: boolean()

HashGenerator.validate_hash(event, "a1b2c3d4", :event)
# => true (hash matches)
# => false (hash mismatch, data changed)
```

---

## Testing & Validation

### Platform-Specific Validators

#### Google Rich Results Test
**URL:** https://search.google.com/test/rich-results

**Tests:**
- JSON-LD structured data validity
- Schema.org compliance
- Required/recommended properties
- Error detection and warnings

**Usage:**
1. Enter your page URL
2. Click "Test URL"
3. Review results for errors/warnings
4. Fix issues and re-test

#### Facebook Sharing Debugger
**URL:** https://developers.facebook.com/tools/debug/

**Tests:**
- Open Graph meta tags
- Social card image loading
- Cache status
- Scraper warnings

**Usage:**
1. Enter page URL
2. Click "Debug"
3. Review scraped data
4. Click "Scrape Again" to clear cache

**Common Issues:**
- Image too small (minimum 600x315px)
- Image doesn't load (check HTTPS, CORS)
- Cached old version (use "Scrape Again")

#### Twitter Card Validator
**URL:** https://cards-dev.twitter.com/validator

**Tests:**
- Twitter Card meta tags
- Card type validation
- Image requirements
- Preview rendering

**Usage:**
1. Enter page URL
2. Click "Preview card"
3. Review preview and warnings
4. Fix issues and re-test

#### LinkedIn Post Inspector
**URL:** https://www.linkedin.com/post-inspector/

**Tests:**
- Open Graph compliance
- Image specifications
- Title and description

**Usage:**
1. Enter page URL
2. Click "Inspect"
3. Review results
4. Clear cache if needed

### Manual Testing Checklist

#### Before Deployment

- [ ] **JSON-LD Validation**
  - [ ] Test with Google Rich Results Test
  - [ ] All required properties present
  - [ ] No validation errors
  - [ ] Preview looks correct

- [ ] **Social Cards**
  - [ ] Test on Facebook Sharing Debugger
  - [ ] Test on Twitter Card Validator
  - [ ] Test on LinkedIn Post Inspector
  - [ ] Images load correctly (HTTPS)
  - [ ] Dimensions correct (1200x630px)

- [ ] **Meta Tags**
  - [ ] Title tag present and correct
  - [ ] Meta description present (150-160 chars)
  - [ ] Canonical URL correct
  - [ ] Open Graph tags complete
  - [ ] Twitter Card tags present

- [ ] **Mobile Testing**
  - [ ] Preview in WhatsApp
  - [ ] Preview in Telegram
  - [ ] Preview in Discord
  - [ ] Preview in Slack

#### After Deployment

- [ ] Test production URLs in all validators
- [ ] Verify cache headers (1 year for social cards)
- [ ] Check analytics for improved CTR
- [ ] Monitor search console for rich results

### Automated Testing

```elixir
# test/eventasaurus_web/helpers/seo_helpers_test.exs
defmodule EventasaurusWeb.Helpers.SEOHelpersTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EventasaurusWeb.Helpers.SEOHelpers

  describe "assign_meta_tags/2" do
    test "assigns all required meta tag fields" do
      socket = %Phoenix.LiveView.Socket{assigns: %{}}

      socket = SEOHelpers.assign_meta_tags(socket,
        title: "Test Event",
        description: "Test description"
      )

      assert socket.assigns.page_title == "Test Event"
      assert socket.assigns.meta_title == "Test Event"
      assert socket.assigns.meta_description == "Test description"
      assert socket.assigns.meta_type == "website"
    end

    test "builds canonical URL from path" do
      socket = %Phoenix.LiveView.Socket{assigns: %{}}

      socket = SEOHelpers.assign_meta_tags(socket,
        title: "Test",
        description: "Test",
        canonical_path: "/events/test"
      )

      assert socket.assigns.canonical_url =~ "/events/test"
    end
  end
end
```

### Performance Testing

```bash
# Test social card generation time
time curl -I https://wombie.com/event/social-card-abc123.png

# Should be:
# - First request: < 500ms (generation)
# - Subsequent: < 100ms (cached)

# Test JSON-LD validation
curl https://wombie.com/events/summer-festival | \
  grep -o '<script type="application/ld+json">.*</script>' | \
  python -m json.tool
```

---

## Common Patterns

### Event Detail Page

```elixir
defmodule EventasaurusWeb.PublicEventShowLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.PublicEventSchema

  @impl true
  def handle_params(%{"slug" => slug}, _url, socket) do
    event = Events.get_event_by_slug!(slug)

    # Generate JSON-LD
    json_ld = PublicEventSchema.generate(event)

    # Get image URL
    image_url = event.cover_image_url || get_placeholder_image_url(event)

    # Build description
    description = event.display_description ||
                  truncate_for_description(event.display_title)

    # Assign SEO metadata
    socket =
      socket
      |> assign(:event, event)
      |> SEOHelpers.assign_meta_tags(
        title: event.display_title,
        description: description,
        image: image_url,
        type: "event",
        canonical_path: "/activities/#{event.slug}",
        json_ld: json_ld
      )

    {:noreply, socket}
  end
end
```

### City Discovery Page

```elixir
defmodule EventasaurusWeb.CityLive.Index do
  use EventasaurusWeb, :live_view

  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.CitySchema

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    city = Locations.get_city_by_slug!(city_slug)

    # Fetch city stats
    stats = fetch_city_stats(city)
    city_with_stats = Map.put(city, :stats, stats)

    # Generate JSON-LD
    json_ld = CitySchema.generate(city, stats)

    # Generate social card
    social_card_url = SEOHelpers.build_social_card_url(
      city_with_stats, :city, stats: stats
    )

    # Assign SEO metadata
    socket =
      socket
      |> assign(:city, city)
      |> SEOHelpers.assign_meta_tags(
        title: "Events in #{city.name}, #{city.country.name}",
        description: "Discover upcoming events in #{city.name}",
        image: social_card_url,
        type: "website",
        canonical_path: "/c/#{city.slug}",
        json_ld: json_ld
      )

    {:ok, socket}
  end
end
```

### Poll Detail Page

```elixir
defmodule EventasaurusWeb.PublicPollLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusWeb.Helpers.SEOHelpers

  @impl true
  def mount(%{"slug" => slug, "number" => number}, _session, socket) do
    event = Events.get_event_by_slug!(slug)
    poll = Events.get_poll_by_number!(number, event.id)

    # Generate social card URL
    poll_with_event = %{poll | event: event}
    social_card_url = SEOHelpers.build_social_card_url(
      poll_with_event, :poll, event: event
    )

    # Build description
    description = poll.description ||
                  "Participate in this poll for #{event.title}"

    # Assign SEO metadata
    socket =
      socket
      |> assign(:event, event)
      |> assign(:poll, poll)
      |> SEOHelpers.assign_meta_tags(
        title: "#{poll.title} - #{event.title}",
        description: description,
        image: social_card_url,
        type: "website",
        canonical_path: "/#{event.slug}/polls/#{poll.number}"
      )

    {:ok, socket}
  end
end
```

### Development & ngrok Support

**⚠️ CRITICAL:** All LiveViews using `SEOHelpers.assign_meta_tags/2` **must** capture and pass `request_uri` to avoid localhost URLs in development.

#### The Problem

Without `request_uri`, URLs fall back to static configuration:
- **Development:** Returns `localhost` → Social media crawlers **cannot** access localhost
- **Production:** Works fine (returns production domain)
- **ngrok/tunnels:** Broken (returns localhost instead of tunnel URL)

#### The Solution

**Step 1:** Capture `request_uri` in `mount/3`:

```elixir
def mount(_params, _session, socket) do
  # Capture request URI for correct URL generation
  raw_uri = get_connect_info(socket, :uri)
  request_uri =
    cond do
      match?(%URI{}, raw_uri) -> raw_uri
      is_binary(raw_uri) -> URI.parse(raw_uri)
      true -> nil
    end

  # ... rest of mount logic
end
```

**Step 2:** Pass `request_uri` to `SEOHelpers.assign_meta_tags/2`:

```elixir
socket
|> SEOHelpers.assign_meta_tags(
  title: "Page Title",
  description: "Page description",
  image: social_card_url,
  type: "website",
  canonical_path: "/page/path",
  json_ld: json_ld,
  request_uri: request_uri  # CRITICAL: Must pass this
)
```

#### How It Works

When `request_uri` is provided:
1. `SEOHelpers` passes it to `UrlHelper.build_url(path, request_uri)`
2. `UrlHelper` uses the **actual request host** (ngrok, production domain)
3. Meta tags show correct URLs that social media crawlers can access

Without `request_uri`:
1. `SEOHelpers` calls `UrlHelper.build_url(path, nil)`
2. Falls back to `UrlHelper.get_base_url()` (reads endpoint config)
3. Returns localhost in development → social cards broken

#### Testing with ngrok

```bash
# 1. Start Phoenix server
mix phx.server

# 2. Start ngrok tunnel
ngrok http 4000

# 3. Visit your page through ngrok
https://your-subdomain.ngrok.io/your-page

# 4. View page source and verify meta tags use ngrok URL
<meta property="og:url" content="https://your-subdomain.ngrok.io/your-page">
<meta property="og:image" content="https://your-subdomain.ngrok.io/path/to/social-card.png">
```

#### Checklist for All LiveViews

Before marking a LiveView SEO implementation complete:

- [ ] `get_connect_info(socket, :uri)` captured in `mount/3`
- [ ] `request_uri` parsed and stored in socket assigns (optional) or local variable
- [ ] `request_uri: request_uri` passed to `SEOHelpers.assign_meta_tags/2`
- [ ] Tested with ngrok - meta tags show ngrok URL, not localhost
- [ ] Tested with social media debuggers (Facebook, Twitter, LinkedIn)

#### Reference Implementation

See `lib/eventasaurus_web/live/public_event_show_live.ex:27-34` for the canonical implementation pattern.

---

## Troubleshooting

### SEO Metadata Missing from Crawler View (Async Timing Bug)

**Problem:** Social cards work in browser but crawlers see empty or default meta tags

**Symptoms:**
- Facebook Sharing Debugger shows generic/missing Open Graph tags
- Twitter Card Validator shows no card preview
- Browser "View Source" shows correct meta tags, but crawlers don't see them

**Root Cause:** SEO metadata set in `handle_info` (async) instead of `mount`/`handle_params` (sync)

**Why This Happens:**
```
Timeline for a social media crawler:

1. Crawler requests URL           →  Phoenix receives HTTP request
2. LiveView mount() runs          →  Initial HTML generated (THIS IS ALL CRAWLERS SEE)
3. HTML response sent to crawler  →  Crawler parses <meta> tags NOW
4. WebSocket connects             →  (Crawlers don't do this)
5. handle_info() runs             →  (Too late - crawler is gone!)
```

**Diagnosis:**
```bash
# Check what crawlers actually see (no JavaScript execution)
curl -s https://your-domain.com/your-page | grep -E "(og:|twitter:)"

# Compare to browser view-source (should match if correct)
# If curl shows empty/wrong tags but browser shows correct tags,
# you have an async timing bug
```

**Fix Pattern:**
```elixir
# ❌ WRONG: Async data loading with SEO
def mount(_params, _session, socket) do
  send(self(), :load_data)  # Async!
  {:ok, assign(socket, :loading, true)}
end

def handle_info(:load_data, socket) do
  data = load_data()
  socket = SEOHelpers.assign_meta_tags(socket, ...)  # TOO LATE!
  {:noreply, socket}
end

# ✅ CORRECT: Sync SEO, async non-critical data
def mount(_params, _session, socket) do
  # Load ONLY what's needed for SEO synchronously
  entity = load_entity_for_seo()

  socket =
    socket
    |> assign(:entity, entity)
    |> SEOHelpers.assign_meta_tags(title: entity.name, ...)

  # Async load for UI enhancements (not SEO-critical)
  send(self(), :load_additional_data)

  {:ok, socket}
end
```

**Empty String Gotcha:**
```elixir
# ❌ BUG: Empty string is truthy in Elixir!
assign(socket, :open_graph, "")  # Template: if @open_graph → TRUE!

# ✅ FIX: Use nil for "not set"
assign(socket, :open_graph, nil)  # Template: if @open_graph → FALSE
```

**Reference:** See [Critical: LiveView Lifecycle and SEO Timing](#-critical-liveview-lifecycle-and-seo-timing) in Quick Start section.

---

### Social Cards Not Appearing

**Problem:** Shared link doesn't show preview

**Checklist:**
1. ✅ Image URL is absolute (starts with https://)
2. ✅ Image is accessible publicly (not behind auth)
3. ✅ Image is correct size (1200x630px recommended)
4. ✅ Image file size < 8MB
5. ✅ Open Graph tags in page source
6. ✅ Test with Facebook Sharing Debugger
7. ✅ Clear platform cache

**Common Fixes:**
```bash
# Check if image is accessible
curl -I https://wombie.com/event/social-card-abc123.png

# Should return:
# HTTP/2 200
# content-type: image/png
# cache-control: public, max-age=31536000

# If 404, check:
# - Hash is correct
# - Route is configured
# - rsvg-convert is installed
```

### Social Card URLs Show localhost

**Problem:** Open Graph meta tags show `localhost` instead of actual domain (ngrok, production)

**Symptoms:**
```html
<!-- Bad: Shows localhost -->
<meta property="og:url" content="https://localhost/c/warsaw">
<meta property="og:image" content="https://localhost/social-cards/city/warsaw/hash.png">

<!-- Good: Shows actual domain -->
<meta property="og:url" content="https://wombie.ngrok.io/c/warsaw">
<meta property="og:image" content="https://wombie.ngrok.io/social-cards/city/warsaw/hash.png">
```

**Root Cause:** LiveView not capturing and passing `request_uri` to `SEOHelpers.assign_meta_tags/2`

**Fix:**

Step 1: Capture `request_uri` in LiveView's `mount/3`:
```elixir
def mount(_params, _session, socket) do
  # Capture request URI for correct URL generation (ngrok support)
  raw_uri = get_connect_info(socket, :uri)
  request_uri =
    cond do
      match?(%URI{}, raw_uri) -> raw_uri
      is_binary(raw_uri) -> URI.parse(raw_uri)
      true -> nil
    end

  # ... rest of mount logic
end
```

Step 2: Pass `request_uri` to `SEOHelpers.assign_meta_tags/2`:
```elixir
socket
|> SEOHelpers.assign_meta_tags(
  title: title,
  description: description,
  image: social_card_url,
  type: "website",
  canonical_path: "/path",
  json_ld: json_ld,
  request_uri: request_uri  # CRITICAL: Must include this
)
```

**Why this happens:**
- Without `request_uri`: URLs fall back to endpoint config (returns `localhost` in dev)
- With `request_uri`: URLs use actual request host (ngrok URL, production domain)
- Social media crawlers cannot access `localhost` URLs → cards fail to display

**Testing:**
```bash
# View page source and check meta tags
curl -s https://your-domain.ngrok.io/your-page | grep "og:url"
curl -s https://your-domain.ngrok.io/your-page | grep "og:image"

# Should show ngrok URL, not localhost
# Bad:  content="https://localhost/..."
# Good: content="https://your-domain.ngrok.io/..."
```

**Reference:** See [Development & ngrok Support](#development--ngrok-support) section and `lib/eventasaurus_web/live/public_event_show_live.ex:27-34` for the canonical implementation pattern.

### JSON-LD Not Recognized

**Problem:** Google Rich Results Test shows errors

**Common Errors:**

**Missing Required Property:**
```json
{
  "@type": "Event",
  "name": "My Event"
  // Missing: startDate, location
}
```

**Fix:** Add all required properties per schema type

**Invalid Date Format:**
```json
{
  "startDate": "2025-01-29"  // ❌ Date only
}
```

**Fix:** Use ISO 8601 with time:
```json
{
  "startDate": "2025-01-29T19:00:00"  // ✅ Date + time
}
```

**Relative URL:**
```json
{
  "url": "/events/my-event"  // ❌ Relative
}
```

**Fix:** Use absolute URL:
```json
{
  "url": "https://wombie.com/events/my-event"  // ✅ Absolute
}
```

### Hash Mismatch Issues

**Problem:** Social card redirects to different URL

**Cause:** Content changed, hash no longer matches

**Behavior:**
1. Platform requests old URL with old hash
2. Server validates hash against current data
3. Hash mismatch detected
4. Server responds with 301 redirect to new hash URL
5. Platform re-fetches with new URL

**This is expected behavior!** It ensures:
- Social platforms always fetch current version
- Stale cards don't persist
- No manual cache invalidation needed

**Monitoring:**
```bash
# Check for hash redirects
tail -f log/production.log | grep "Hash mismatch"

# Should see occasional redirects after content updates
# If frequent, investigate data stability
```

### rsvg-convert Not Found

**Problem:** Social cards return 503 error

**Error:** `rsvg-convert command not found`

**Fix:**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install librsvg2-bin

# macOS
brew install librsvg

# Verify installation
rsvg-convert --version

# Test conversion
echo '<svg width="100" height="100"><rect width="100" height="100" fill="red"/></svg>' | \
  rsvg-convert -o test.png
```

### Meta Tags Not Updating

**Problem:** Changes to SEO data not appearing

**Checklist:**
1. ✅ Cleared browser cache
2. ✅ Using incognito/private window
3. ✅ Recompiled after code changes (`mix compile`)
4. ✅ Restarted Phoenix server
5. ✅ Checked page source (not just preview)
6. ✅ Verified assigns are being set

**Debug:**
```elixir
# In LiveView
def handle_params(_params, _url, socket) do
  socket = SEOHelpers.assign_meta_tags(socket, ...)

  # Debug: Print assigns
  IO.inspect(socket.assigns.meta_title, label: "META TITLE")
  IO.inspect(socket.assigns.meta_image, label: "META IMAGE")

  {:noreply, socket}
end
```

---

## Resources

### Official Documentation

- **Schema.org**: https://schema.org/
- **Open Graph Protocol**: https://ogp.me/
- **Twitter Cards**: https://developer.twitter.com/en/docs/twitter-for-websites/cards
- **Google Search Central**: https://developers.google.com/search

### Validators & Tools

- **Google Rich Results Test**: https://search.google.com/test/rich-results
- **Facebook Sharing Debugger**: https://developers.facebook.com/tools/debug/
- **Twitter Card Validator**: https://cards-dev.twitter.com/validator
- **LinkedIn Post Inspector**: https://www.linkedin.com/post-inspector/
- **Schema Markup Validator**: https://validator.schema.org/

### Internal Documentation

- **ADR 001**: Meta Tag Pattern Standardization
- **Helper Module Source**: `lib/eventasaurus_web/helpers/`
- **JSON-LD Schemas**: `lib/eventasaurus_web/json_ld/`
- **Social Card Controllers**: `lib/eventasaurus_web/controllers/*_social_card_controller.ex`

### Learning Resources

- **JSON-LD Tutorial**: https://json-ld.org/learn.html
- **SEO Starter Guide**: https://developers.google.com/search/docs/beginner/seo-starter-guide
- **Structured Data Codelab**: https://developers.google.com/codelabs/structured-data

---

## Changelog

### Version 1.0.0 (2025-01-29)

- Initial documentation
- Documented SEO best practices
- Added JSON-LD schema guide
- Documented social card system
- Added testing & validation procedures
- Created troubleshooting guide

---

**Questions or Issues?**

Create an issue on GitHub or contact the development team.
