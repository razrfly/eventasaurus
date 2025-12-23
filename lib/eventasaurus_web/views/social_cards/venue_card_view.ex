defmodule EventasaurusWeb.SocialCards.VenueCardView do
  @moduledoc """
  Venue-specific social card SVG generation.

  Handles rendering of social cards for venues with:
  - Venue name (multi-line, auto-sized)
  - Cover image with gradient overlay
  - Event count display
  - Location/address
  - VIEW call-to-action button
  - Fixed emerald brand colors (location-focused)
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared
  alias EventasaurusWeb.SocialCards.ActivityCardView

  # Venue card brand colors (emerald/green - welcoming, location-focused)
  @theme_colors %{
    primary: "#059669",
    secondary: "#10b981"
  }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders SVG social card for a venue page.
  Shows venue name, city/location, event count, and venue image with Wombie branding.

  ## Parameters
    - venue: Map with :name, :slug, :city_ref, :cover_image_url, :event_count, :address fields

  ## Returns
    Complete SVG markup as a string
  """
  def render_venue_card_svg(venue) do
    # Use Wombie brand theme with venue-focused palette (emerald/green)
    city_slug = get_in(venue, [:city_ref, :slug]) || "default"
    venue_slug = Map.get(venue, :slug, "venue")
    theme_suffix = "venue_#{city_slug}_#{venue_slug}"

    # Build venue-specific content
    venue_content = render_venue_content(venue, theme_suffix, @theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, @theme_colors, venue_content)
  end

  @doc """
  Renders the venue-specific content for a social card.
  Includes venue image, logo, venue name, city, event count, and address.

  ## Parameters
    - venue: Map with venue data
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with venue-specific content
  """
  def render_venue_content(venue, theme_suffix, theme_colors) do
    # Extract and sanitize data
    venue_name = Sanitizer.sanitize_text(Map.get(venue, :name, ""))
    city_ref = Map.get(venue, :city_ref, %{})
    city_name = Sanitizer.sanitize_text(Map.get(city_ref, :name, ""))
    event_count = Map.get(venue, :event_count, 0)
    address = Sanitizer.sanitize_text(Map.get(venue, :address, ""))

    # Prepare entity with cover image for image section
    cover_image = Map.get(venue, :cover_image_url)
    entity_with_image = %{cover_image_url: cover_image}

    # Format event count text
    event_count_text = format_venue_event_count(event_count)

    # Format location text (address or city)
    location_text = format_venue_location(address, city_name)

    # Calculate font size for venue name
    venue_font_size = Shared.calculate_font_size(venue_name)

    # Build title sections
    title_line_1 =
      if Shared.format_title(venue_name, 0) != "" do
        y_pos = ActivityCardView.activity_title_y_position(0, venue_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(venue_name, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(venue_name, 1) != "" do
        y_pos = ActivityCardView.activity_title_y_position(1, venue_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(venue_name, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(venue_name, 2) != "" do
        y_pos = ActivityCardView.activity_title_y_position(2, venue_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(venue_name, 2)}</tspan>)
      else
        ""
      end

    """
    #{Shared.render_image_section(entity_with_image, theme_suffix)}

    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Venue name (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{venue_font_size}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Event count (below title, y=310) -->
    #{render_venue_event_count(event_count_text)}

    <!-- Location/Address (y=340 like activity location) -->
    #{render_venue_location(location_text)}

    #{Shared.render_cta_bubble("VIEW", theme_suffix)}
    """
  end

  @doc """
  Sanitizes venue data for safe use in social card generation.
  """
  def sanitize_venue(venue) do
    city_ref = Map.get(venue, :city_ref, %{})

    sanitized_city = %{
      name: Sanitizer.sanitize_text(Map.get(city_ref, :name, "")),
      slug: Map.get(city_ref, :slug, "")
    }

    %{
      name: Sanitizer.sanitize_text(Map.get(venue, :name, "")),
      slug: Map.get(venue, :slug, ""),
      city_ref: sanitized_city,
      cover_image_url: Map.get(venue, :cover_image_url),
      event_count: Map.get(venue, :event_count, 0),
      address: Sanitizer.sanitize_text(Map.get(venue, :address, "")),
      updated_at: Map.get(venue, :updated_at)
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Format event count for venue card display
  defp format_venue_event_count(0), do: ""
  defp format_venue_event_count(1), do: "1 upcoming event"
  defp format_venue_event_count(count) when count > 1, do: "#{count} upcoming events"
  defp format_venue_event_count(_), do: ""

  # Format venue location for display (prefer address, fallback to city)
  defp format_venue_location("", ""), do: ""
  defp format_venue_location("", city_name), do: city_name
  defp format_venue_location(address, _city_name), do: address

  # Render event count for venue card
  defp render_venue_event_count(""), do: ""

  defp render_venue_event_count(event_count_text) do
    """
    <text x="32" y="310" font-family="Arial, sans-serif" font-weight="600"
          font-size="20" fill="white" opacity="0.95">
      #{Shared.svg_escape(event_count_text)}
    </text>
    """
  end

  # Render location for venue card
  defp render_venue_location(""), do: ""

  defp render_venue_location(location_text) do
    # Truncate if too long
    truncated = Shared.truncate_title(location_text, 45)

    """
    <text x="32" y="340" font-family="Arial, sans-serif" font-weight="400"
          font-size="18" fill="white" opacity="0.85">
      #{Shared.svg_escape(truncated)}
    </text>
    """
  end
end
