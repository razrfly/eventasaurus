# Developer Guide: Adding New Social Card Types

This guide walks through adding social card support for a new entity type in the Eventasaurus application.

## Overview

The social card system uses a unified architecture with hash-based cache busting. All entity types follow the same pattern, making it straightforward to add new types.

## Prerequisites

- Familiarity with Phoenix LiveView
- Understanding of Elixir pattern matching
- Basic knowledge of SVG generation
- Read [ADR-001: Social Card URL Patterns](../architecture/adr-001-social-card-url-patterns.md)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    UrlBuilder                            │
│  Unified interface for all entity types                 │
│  - build_path(entity_type, entity, opts)                │
│  - build_url(entity_type, entity, opts)                 │
│  - extract_hash(path)                                    │
│  - validate_hash(entity_type, entity, hash)             │
└─────────────────────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
┌─────────▼────────┐ ┌───▼──────────┐ ┌─▼────────────┐
│ HashGenerator    │ │PollHashGen   │ │GroupHashGen  │
│ (Events)         │ │ (Polls)      │ │ (New!)       │
└──────────────────┘ └──────────────┘ └──────────────┘
```

## Step-by-Step Implementation

### Example: Adding Group Social Cards

Let's walk through adding social cards for a "groups" entity type.

### Step 1: Create Hash Generator Module

Create `lib/eventasaurus/social_cards/group_hash_generator.ex`:

```elixir
defmodule Eventasaurus.SocialCards.GroupHashGenerator do
  @moduledoc """
  Generates content-based hashes and URL paths for group social cards.

  Hash changes when group content changes, enabling automatic cache invalidation
  for social media platforms.
  """

  @doc """
  Generates URL path for group social card.

  ## Examples

      iex> group = %{slug: "tech-enthusiasts", name: "Tech Enthusiasts", updated_at: ~N[2023-01-01 12:00:00]}
      iex> GroupHashGenerator.generate_url_path(group)
      "/tech-enthusiasts/social-card-abc12345.png"
  """
  def generate_url_path(group) do
    hash = generate_hash(group)
    slug = get_slug(group)
    "/#{slug}/social-card-#{hash}.png"
  end

  @doc """
  Generates content-based hash for a group.

  Hash inputs: slug, name, updated_at

  ## Examples

      iex> group = %{slug: "tech-enthusiasts", name: "Tech Enthusiasts", updated_at: ~N[2023-01-01 12:00:00]}
      iex> hash = GroupHashGenerator.generate_hash(group)
      iex> String.length(hash)
      8
  """
  def generate_hash(group) do
    # Include all fields that should trigger cache invalidation
    content = "#{group.slug}-#{group.name}-#{group.updated_at}"

    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  @doc """
  Extracts hash from a group social card URL path.

  ## Examples

      iex> GroupHashGenerator.extract_hash_from_path("/tech-enthusiasts/social-card-abc12345.png")
      "abc12345"

      iex> GroupHashGenerator.extract_hash_from_path("/invalid/path")
      nil
  """
  def extract_hash_from_path(path) when is_binary(path) do
    case Regex.run(~r/\/([^\/]+)\/social-card-([a-f0-9]{8})(?:\.png)?$/, path) do
      [_full, _slug, hash] -> hash
      _ -> nil
    end
  end

  @doc """
  Validates that a hash matches the current group data.

  ## Examples

      iex> group = %{slug: "tech-enthusiasts", name: "Tech Enthusiasts", updated_at: ~N[2023-01-01 12:00:00]}
      iex> hash = GroupHashGenerator.generate_hash(group)
      iex> GroupHashGenerator.validate_hash(group, hash)
      true

      iex> GroupHashGenerator.validate_hash(group, "invalid")
      false
  """
  def validate_hash(group, hash) do
    generate_hash(group) == hash
  end

  # Private helper to get slug with fallback to ID
  defp get_slug(group) do
    case Map.get(group, :slug) do
      nil -> "group-#{Map.get(group, :id)}"
      slug -> slug
    end
  end
end
```

### Step 2: Update UrlBuilder

Edit `lib/eventasaurus/social_cards/url_builder.ex`:

```elixir
defmodule Eventasaurus.SocialCards.UrlBuilder do
  # Add to module aliases
  alias Eventasaurus.SocialCards.{HashGenerator, PollHashGenerator, GroupHashGenerator}

  # Add new entity type to build_path/3
  def build_path(:group, group, _opts) do
    GroupHashGenerator.generate_url_path(group)
  end

  # Add new entity type to validate_hash/4
  def validate_hash(:group, group, hash, _opts) do
    GroupHashGenerator.validate_hash(group, hash)
  end

  # Update detect_entity_type/1 to recognize group URLs
  def detect_entity_type(path) when is_binary(path) do
    cond do
      # Poll pattern: contains /polls/ segment
      String.contains?(path, "/polls/") && PollHashGenerator.extract_hash_from_path(path) ->
        :poll

      # Event pattern: simpler structure (keep existing logic)
      HashGenerator.extract_hash_from_path(path) ->
        :event

      # Group pattern: check for group-specific pattern
      GroupHashGenerator.extract_hash_from_path(path) ->
        :group

      true ->
        nil
    end
  end

  # Update parse_path/1 to handle group URLs
  def parse_path(path) when is_binary(path) do
    entity_type = detect_entity_type(path)
    hash = extract_hash(path)

    case entity_type do
      :poll ->
        # ... existing poll logic ...

      :event ->
        # ... existing event logic ...

      :group ->
        # Extract: /:group_slug/social-card-:hash.png
        case Regex.run(~r/\/([^\/]+)\/social-card-[a-f0-9]{8}(?:\.png)?$/, path) do
          [_full, group_slug] ->
            %{
              entity_type: :group,
              group_slug: group_slug,
              hash: hash
            }

          _ ->
            nil
        end

      nil ->
        nil
    end
  end
end
```

### Step 3: Add Router Routes

Edit `lib/eventasaurus_web/router.ex`:

```elixir
scope "/", EventasaurusWeb do
  pipe_through :browser

  # ... existing routes ...

  # Group social card route
  get "/:group_slug/social-card-:hash/*rest", GroupSocialCardController, :show
end
```

### Step 4: Create Controller

Create `lib/eventasaurus_web/controllers/group_social_card_controller.ex`:

```elixir
defmodule EventasaurusWeb.GroupSocialCardController do
  use EventasaurusWeb, :controller

  alias Eventasaurus.Groups
  alias Eventasaurus.SocialCards.{UrlBuilder, GroupHashGenerator}
  alias EventasaurusWeb.SocialCardView

  @doc """
  Serves social card PNG for a group.

  URL Pattern: /:group_slug/social-card-:hash.png
  """
  def show(conn, %{"group_slug" => slug, "hash" => hash}) do
    case Groups.get_group_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("Group not found")

      group ->
        # Validate hash matches current group data
        if UrlBuilder.validate_hash(:group, group, hash) do
          # Generate SVG
          svg_content = SocialCardView.render_group_card_svg(group)

          # Convert SVG to PNG
          case Eventasaurus.Services.SvgConverter.svg_to_png(svg_content) do
            {:ok, png_binary} ->
              conn
              |> put_resp_content_type("image/png")
              |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
              |> send_resp(200, png_binary)

            {:error, reason} ->
              require Logger
              Logger.error("Failed to generate group social card: #{inspect(reason)}")

              conn
              |> put_status(:internal_server_error)
              |> text("Failed to generate social card")
          end
        else
          # Hash mismatch - group data has changed
          # Redirect to current URL with new hash
          new_path = UrlBuilder.build_path(:group, group)

          conn
          |> put_status(:moved_permanently)
          |> redirect(to: new_path)
        end
    end
  end
end
```

### Step 5: Add SVG Rendering to SocialCardView

Edit `lib/eventasaurus_web/views/social_card_view.ex`:

```elixir
defmodule EventasaurusWeb.SocialCardView do
  # ... existing code ...

  @doc """
  Renders SVG social card for a group.
  Uses the same component-based architecture as event and poll cards.
  """
  def render_group_card_svg(group) do
    # Sanitize group data first
    sanitized_group = sanitize_group(group)

    # Get theme name for unique IDs
    theme_name = sanitized_group.theme || :minimal
    theme_suffix = to_string(theme_name)

    # Get theme colors
    theme_colors = get_theme_colors(theme_name)

    # Build group-specific content
    group_content = render_group_content(sanitized_group, theme_suffix, theme_colors)

    # Use the base function to create complete SVG
    render_social_card_base(theme_suffix, theme_colors, group_content)
  end

  @doc """
  Renders the group-specific content for a social card.
  """
  def render_group_content(group, theme_suffix, theme_colors) do
    # Format group name (max 3 lines)
    title_line_1 =
      if format_title(group.name, 0) != "" do
        y_pos = title_line_y_position(0, calculate_font_size(group.name))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(group.name, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if format_title(group.name, 1) != "" do
        y_pos = title_line_y_position(1, calculate_font_size(group.name))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(group.name, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if format_title(group.name, 2) != "" do
        y_pos = title_line_y_position(2, calculate_font_size(group.name))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(group.name, 2)}</tspan>)
      else
        ""
      end

    # Member count or other group stats
    member_text =
      if Map.has_key?(group, :member_count) do
        count = group.member_count
        plural = if count == 1, do: "member", else: "members"
        "#{count} #{plural}"
      else
        ""
      end

    """
    #{render_image_section(group, theme_suffix)}

    <!-- Logo (top-left) -->
    #{get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Group name (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{calculate_font_size(group.name)}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Member count (bottom-left area) -->
    <text x="32" y="320" font-family="Arial, sans-serif"
          font-size="24" font-weight="500" fill="white" opacity="0.9">
      #{member_text}
    </text>

    #{render_cta_bubble("JOIN", theme_suffix)}
    """
  end

  @doc """
  Sanitizes group data for safe use in social card generation.
  """
  def sanitize_group(group) do
    %{
      name: Sanitizer.sanitize_text(Map.get(group, :name, "")),
      cover_image_url: Map.get(group, :cover_image_url),
      theme: Map.get(group, :theme, :minimal),
      member_count: Map.get(group, :member_count, 0)
    }
  end
end
```

### Step 6: Add to LiveView Meta Tags

Edit the LiveView that displays groups (e.g., `lib/eventasaurus_web/live/public_group_live.ex`):

```elixir
defmodule EventasaurusWeb.PublicGroupLive do
  use EventasaurusWeb, :live_view

  alias Eventasaurus.SocialCards.UrlBuilder

  def mount(%{"group_slug" => slug}, _session, socket) do
    case Groups.get_group_by_slug(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Group not found") |> redirect(to: "/")}

      group ->
        {:ok,
         socket
         |> assign(:group, group)
         |> assign(:meta_title, group.name)
         |> assign(:meta_description, group.description || "Join #{group.name}")
         |> assign(:meta_image, social_card_url(group))
         |> assign(:canonical_url, "#{EventasaurusWeb.Endpoint.url()}/#{group.slug}")}
    end
  end

  # Generate social card URL with external domain
  defp social_card_url(group) do
    path = UrlBuilder.build_path(:group, group)
    EventasaurusWeb.UrlHelper.build_url(path)
  end
end
```

### Step 7: Add Tests

Create `test/eventasaurus/social_cards/group_hash_generator_test.exs`:

```elixir
defmodule Eventasaurus.SocialCards.GroupHashGeneratorTest do
  use ExUnit.Case, async: true

  alias Eventasaurus.SocialCards.GroupHashGenerator

  describe "generate_hash/1" do
    test "generates consistent hash for same group data" do
      group = %{
        slug: "tech-enthusiasts",
        name: "Tech Enthusiasts",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash1 = GroupHashGenerator.generate_hash(group)
      hash2 = GroupHashGenerator.generate_hash(group)

      assert hash1 == hash2
      assert String.length(hash1) == 8
    end

    test "generates different hash when data changes" do
      group1 = %{
        slug: "tech-enthusiasts",
        name: "Tech Enthusiasts",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      group2 = %{group1 | name: "Tech Enthusiasts Updated"}

      hash1 = GroupHashGenerator.generate_hash(group1)
      hash2 = GroupHashGenerator.generate_hash(group2)

      assert hash1 != hash2
    end
  end

  describe "generate_url_path/1" do
    test "generates URL path with slug and hash" do
      group = %{
        slug: "tech-enthusiasts",
        name: "Tech Enthusiasts",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = GroupHashGenerator.generate_url_path(group)

      assert String.starts_with?(path, "/tech-enthusiasts/social-card-")
      assert String.ends_with?(path, ".png")
      assert Regex.match?(~r/\/tech-enthusiasts\/social-card-[a-f0-9]{8}\.png$/, path)
    end

    test "falls back to ID when slug is nil" do
      group = %{
        id: 42,
        name: "Tech Enthusiasts",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = GroupHashGenerator.generate_url_path(group)

      assert String.starts_with?(path, "/group-42/social-card-")
    end
  end

  describe "extract_hash_from_path/1" do
    test "extracts hash from valid path" do
      path = "/tech-enthusiasts/social-card-abc12345.png"

      hash = GroupHashGenerator.extract_hash_from_path(path)

      assert hash == "abc12345"
    end

    test "returns nil for invalid paths" do
      assert GroupHashGenerator.extract_hash_from_path("/invalid/path") == nil
      assert GroupHashGenerator.extract_hash_from_path("") == nil
    end
  end

  describe "validate_hash/2" do
    test "validates correct hash" do
      group = %{
        slug: "tech-enthusiasts",
        name: "Tech Enthusiasts",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash = GroupHashGenerator.generate_hash(group)

      assert GroupHashGenerator.validate_hash(group, hash) == true
    end

    test "rejects incorrect hash" do
      group = %{
        slug: "tech-enthusiasts",
        name: "Tech Enthusiasts",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      assert GroupHashGenerator.validate_hash(group, "invalid") == false
    end
  end
end
```

Update `test/eventasaurus/social_cards/url_builder_test.exs` to include group tests:

```elixir
describe "build_path/3 for groups" do
  test "generates path with group slug and hash" do
    group = %{
      slug: "tech-enthusiasts",
      name: "Tech Enthusiasts",
      updated_at: ~N[2023-01-01 12:00:00]
    }

    path = UrlBuilder.build_path(:group, group)

    assert String.starts_with?(path, "/tech-enthusiasts/social-card-")
    assert String.ends_with?(path, ".png")
    assert Regex.match?(~r/\/tech-enthusiasts\/social-card-[a-f0-9]{8}\.png$/, path)
  end
end

describe "detect_entity_type/1" do
  test "detects group type" do
    path = "/tech-enthusiasts/social-card-abc12345.png"

    assert UrlBuilder.detect_entity_type(path) == :group
  end
end

describe "parse_path/1" do
  test "parses group URL completely" do
    path = "/tech-enthusiasts/social-card-abc12345.png"

    result = UrlBuilder.parse_path(path)

    assert result == %{
             entity_type: :group,
             group_slug: "tech-enthusiasts",
             hash: "abc12345"
           }
  end
end
```

### Step 8: Run Tests

```bash
# Run all social card tests
mix test test/eventasaurus/social_cards/

# Run specific test files
mix test test/eventasaurus/social_cards/group_hash_generator_test.exs
mix test test/eventasaurus/social_cards/url_builder_test.exs
```

### Step 9: Manual Testing

1. **Start development server with ngrok**:
```bash
mix phx.server
ngrok http 4000  # In separate terminal
export BASE_URL="https://your-subdomain.ngrok.io"
BASE_URL="https://your-subdomain.ngrok.io" mix phx.server
```

2. **Visit group page**:
```
https://your-subdomain.ngrok.io/tech-enthusiasts
```

3. **Check social card URL in HTML**:
```html
<meta property="og:image" content="https://your-subdomain.ngrok.io/tech-enthusiasts/social-card-abc12345.png">
```

4. **Test with social media debuggers**:
   - Facebook: https://developers.facebook.com/tools/debug/
   - Twitter: https://cards-dev.twitter.com/validator
   - LinkedIn: https://www.linkedin.com/post-inspector/

## Best Practices

### Hash Input Selection

**Include in hash**:
- Slug (for URL uniqueness)
- Title/name (content changes)
- Updated timestamp (modification tracking)
- Any field that should trigger cache invalidation

**Don't include in hash**:
- View counts
- Like counts
- Temporary states
- Fields that change frequently without visual impact

### Error Handling

```elixir
# Always validate hash in controller
if UrlBuilder.validate_hash(:group, group, hash) do
  # Serve cached image
else
  # Redirect to new URL with updated hash
  new_path = UrlBuilder.build_path(:group, group)
  redirect(conn, to: new_path)
end
```

### URL Pattern Design

**Good patterns** (clean, readable):
- `/:slug/social-card-:hash.png`
- `/:parent/:child/social-card-:hash.png`

**Avoid**:
- Query parameters: `/:slug/social-card.png?hash=abc` (ignored by crawlers)
- Database IDs: `/:id/social-card.png` (requires DB lookup)
- No cache busting: `/:slug/social-card.png` (no invalidation)

## Troubleshooting

### Social Card Returns 404

1. **Check router pattern**:
```elixir
# Ensure route matches your URL pattern
get "/:group_slug/social-card-:hash/*rest", GroupSocialCardController, :show
```

2. **Verify hash generation**:
```elixir
iex> group = Groups.get_group_by_slug("tech-enthusiasts")
iex> GroupHashGenerator.generate_url_path(group)
"/tech-enthusiasts/social-card-abc12345.png"
```

3. **Check slug format**:
```elixir
# Ensure slug doesn't contain special characters
# that might break URL matching
```

### Hash Mismatch (Constant Redirects)

**Symptom**: Social card keeps redirecting

**Cause**: Hash inputs include frequently changing fields

**Fix**: Remove volatile fields from hash generation:
```elixir
# Bad: includes view_count which changes frequently
content = "#{group.slug}-#{group.name}-#{group.view_count}"

# Good: only includes stable content
content = "#{group.slug}-#{group.name}-#{group.updated_at}"
```

### SVG Generation Fails

**Check**:
1. All required fields present in sanitized data
2. Image URLs are valid and accessible
3. SVG syntax is well-formed
4. Theme colors are valid hex codes

### Social Media Platform Not Showing Card

**Check**:
1. `BASE_URL` environment variable is set correctly
2. Meta tags include external domain, not localhost
3. Social card URL returns 200 status
4. Image size meets platform requirements (800x419px)
5. Cache-Control headers are set correctly

## Additional Resources

- [ADR-001: Social Card URL Patterns](../architecture/adr-001-social-card-url-patterns.md)
- [Social Cards Development Guide](../../SOCIAL_CARDS_DEV.md)
- [UrlBuilder API Documentation](../../lib/eventasaurus/social_cards/url_builder.ex)
- [Phoenix Router Guide](https://hexdocs.pm/phoenix/routing.html)
- [Open Graph Protocol Specification](https://ogp.me/)

## Support

For questions or issues:
1. Check existing ADRs and guides
2. Review test examples for similar entity types
3. Consult with the team in #engineering-social-cards
4. Create a detailed issue with reproduction steps
