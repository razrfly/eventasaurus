defmodule EventasaurusWeb.SocialCards.EventCardView do
  @moduledoc """
  Event-specific social card SVG generation.

  Handles rendering of social cards for events with:
  - Event title (multi-line, auto-sized)
  - Date and time display
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
  This includes the image, logo, title, date/time, and RSVP button.

  ## Parameters
    - event: Sanitized event map with :title, :cover_image_url, :start_at, :timezone fields
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with event-specific content
  """
  def render_event_content(event, theme_suffix, theme_colors) do
    # Format date/time from event start_at
    date_time_text = format_event_date_time(event)

    # Calculate font size for title
    title_font_size = Shared.calculate_font_size(event.title)

    # Build title sections - positioned higher to make room for date/time below
    title_line_1 =
      if Shared.format_title(event.title, 0) != "" do
        y_pos = event_title_y_position(0, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(event.title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(event.title, 1) != "" do
        y_pos = event_title_y_position(1, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(event.title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(event.title, 2) != "" do
        y_pos = event_title_y_position(2, title_font_size)
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
          font-size="#{title_font_size}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Date/Time info (below title) -->
    #{render_event_date_time(date_time_text)}

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

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Format date and time for event card display
  # Converts UTC datetime to event's local timezone for display
  defp format_event_date_time(%{start_at: nil}), do: ""

  defp format_event_date_time(%{start_at: start_at, timezone: timezone})
       when not is_nil(start_at) do
    # Convert to local time if timezone is available
    local_datetime =
      if timezone do
        case DateTime.shift_zone(start_at, timezone) do
          {:ok, local} -> local
          {:error, _} -> start_at
        end
      else
        start_at
      end

    # Format: "Sat, Jan 25 • 8:00 PM"
    day_name = Calendar.strftime(local_datetime, "%a")
    month_day = Calendar.strftime(local_datetime, "%b %d")
    time = Calendar.strftime(local_datetime, "%-I:%M %p")
    "#{day_name}, #{month_day} • #{time}"
  end

  defp format_event_date_time(_), do: ""

  # Render date/time section for event card
  defp render_event_date_time(""), do: ""

  defp render_event_date_time(date_time_text) do
    """
    <text x="32" y="310" font-family="Arial, sans-serif" font-weight="600"
          font-size="20" fill="white" opacity="0.95">
      #{Shared.svg_escape(date_time_text)}
    </text>
    """
  end

  # Calculate Y position for event title lines (positioned higher to make room for date)
  defp event_title_y_position(line_number, font_size) when is_binary(font_size) do
    event_title_y_position(line_number, String.to_integer(font_size))
  end

  defp event_title_y_position(line_number, font_size) when is_integer(font_size) do
    # Start at y=180 (lower than event cards to leave room for logo)
    # Then add spacing based on font size for each line
    base_y = 180
    line_spacing = font_size + 8
    base_y + line_number * line_spacing
  end
end
