defmodule EventasaurusWeb.SocialCards.EventCardView do
  @moduledoc """
  Event-specific social card SVG generation.

  Handles rendering of social cards for events with:
  - Event title (multi-line, auto-sized)
  - Cover image with gradient overlay
  - Theme-based colors
  - RSVP call-to-action button
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders a complete SVG social card for an event.
  This is a public function that can be used by both the controller and preview tools.

  ## Parameters
    - event: Map with :title, :cover_image_url, :theme fields

  ## Returns
    Complete SVG markup as a string
  """
  def render_social_card_svg(event) do
    # Sanitize event data first
    sanitized_event = sanitize_event(event)

    # Get theme name for unique IDs
    theme_name = sanitized_event.theme || :minimal
    # Use to_string/1 instead of Atom.to_string/1 to handle both atoms and strings safely
    theme_suffix = to_string(theme_name)

    # Get theme colors from event's theme with error handling
    theme_colors =
      case Shared.get_theme_colors(theme_name) do
        %{primary: primary, secondary: secondary} = colors
        when is_binary(primary) and is_binary(secondary) ->
          colors

        _ ->
          %{primary: "#1a1a1a", secondary: "#333333"}
      end

    # Build event-specific content
    event_content = render_event_content(sanitized_event, theme_suffix, theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, theme_colors, event_content)
  end

  @doc """
  Renders the event-specific content for a social card.
  This includes the image, logo, title, and RSVP button.

  ## Parameters
    - event: Sanitized event map with :title, :cover_image_url fields
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with event-specific content
  """
  def render_event_content(event, theme_suffix, theme_colors) do
    # Build title sections - positioned lower for better balance
    title_line_1 =
      if Shared.format_title(event.title, 0) != "" do
        y_pos = Shared.title_line_y_position(0, Shared.calculate_font_size(event.title))
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(event.title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(event.title, 1) != "" do
        y_pos = Shared.title_line_y_position(1, Shared.calculate_font_size(event.title))
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(event.title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(event.title, 2) != "" do
        y_pos = Shared.title_line_y_position(2, Shared.calculate_font_size(event.title))
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(event.title, 2)}</tspan>)
      else
        ""
      end

    """
    #{Shared.render_image_section(event, theme_suffix)}

    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Event title (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{Shared.calculate_font_size(event.title)}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    #{Shared.render_cta_bubble("RSVP", theme_suffix)}
    """
  end

  @doc """
  Sanitizes event data for safe use in social card generation.
  Delegates to the centralized Sanitizer module.
  """
  def sanitize_event(event) do
    Sanitizer.sanitize_event_data(event)
  end
end
