defmodule EventasaurusWeb.SocialCards.PerformerCardView do
  @moduledoc """
  Performer-specific social card SVG generation.

  Handles rendering of social cards for performers/artists with:
  - Performer name (multi-line, auto-sized)
  - Performer image with gradient overlay
  - Event count display
  - VIEW call-to-action button
  - Fixed rose/pink brand colors (artistic, performance-focused)
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared
  alias EventasaurusWeb.SocialCards.ActivityCardView

  # Performer card brand colors (rose/pink - artistic, performance-focused)
  @theme_colors %{
    primary: "#be185d",
    secondary: "#ec4899"
  }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders SVG social card for a performer/artist page.
  Shows performer name, event count, and performer image with Wombie branding.

  ## Parameters
    - performer: Map with :name, :slug, :image_url, :event_count fields

  ## Returns
    Complete SVG markup as a string
  """
  def render_performer_card_svg(performer) do
    # Use Wombie brand theme with performer-focused palette (rose/pink - artistic)
    performer_slug = Map.get(performer, :slug, "performer")
    theme_suffix = "performer_#{performer_slug}"

    # Build performer-specific content
    performer_content = render_performer_content(performer, theme_suffix, @theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, @theme_colors, performer_content)
  end

  @doc """
  Renders the performer-specific content for a social card.
  Includes performer image, logo, performer name, and event count.

  ## Parameters
    - performer: Map with performer data
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with performer-specific content
  """
  def render_performer_content(performer, theme_suffix, theme_colors) do
    # Extract and sanitize data
    performer_name = Sanitizer.sanitize_text(Map.get(performer, :name, ""))
    event_count = Map.get(performer, :event_count, 0)
    image_url = Map.get(performer, :image_url)

    # Prepare entity with image for image section (use image_url as cover_image_url)
    entity_with_image = %{cover_image_url: image_url}

    # Format event count text
    event_count_text = format_performer_event_count(event_count)

    # Calculate font size for performer name
    performer_font_size = Shared.calculate_font_size(performer_name)

    # Build title sections
    title_line_1 =
      if Shared.format_title(performer_name, 0) != "" do
        y_pos = ActivityCardView.activity_title_y_position(0, performer_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(performer_name, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(performer_name, 1) != "" do
        y_pos = ActivityCardView.activity_title_y_position(1, performer_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(performer_name, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(performer_name, 2) != "" do
        y_pos = ActivityCardView.activity_title_y_position(2, performer_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(performer_name, 2)}</tspan>)
      else
        ""
      end

    """
    #{Shared.render_image_section(entity_with_image, theme_suffix)}

    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Performer name (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{performer_font_size}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Event count (below title, y=310) -->
    #{render_performer_event_count(event_count_text)}

    #{Shared.render_cta_bubble("VIEW", theme_suffix)}
    """
  end

  @doc """
  Sanitizes performer data for safe use in social card generation.
  """
  def sanitize_performer(performer) do
    %{
      name: Sanitizer.sanitize_text(Map.get(performer, :name, "")),
      slug: Map.get(performer, :slug, ""),
      image_url: Map.get(performer, :image_url),
      event_count: Map.get(performer, :event_count, 0),
      updated_at: Map.get(performer, :updated_at)
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Format event count for performer card display
  defp format_performer_event_count(0), do: ""
  defp format_performer_event_count(1), do: "1 upcoming event"
  defp format_performer_event_count(count) when count > 1, do: "#{count} upcoming events"
  defp format_performer_event_count(_), do: ""

  # Render event count for performer card
  defp render_performer_event_count(""), do: ""

  defp render_performer_event_count(event_count_text) do
    """
    <text x="32" y="310" font-family="Arial, sans-serif" font-weight="600"
          font-size="20" fill="white" opacity="0.95">
      #{Shared.svg_escape(event_count_text)}
    </text>
    """
  end
end
