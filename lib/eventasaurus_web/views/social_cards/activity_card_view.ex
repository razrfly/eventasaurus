defmodule EventasaurusWeb.SocialCards.ActivityCardView do
  @moduledoc """
  Activity-specific social card SVG generation (Public Events).

  Handles rendering of social cards for public activities with:
  - Activity title (multi-line, auto-sized)
  - Cover image with gradient overlay
  - Date/time display
  - Venue and city location
  - VIEW call-to-action button
  - Fixed teal brand colors (no theme selection)
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared

  # Activity card brand colors (teal gradient)
  @theme_colors %{
    primary: "#0d9488",
    secondary: "#14b8a6"
  }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders SVG social card for a public activity (event).
  Uses Wombie brand colors and includes title, date, venue, and city.

  ## Parameters
    - activity: Map with :title, :cover_image_url, :venue, :occurrence_list fields

  ## Returns
    Complete SVG markup as a string
  """
  def render_activity_card_svg(activity) do
    # Use Wombie brand theme for activities (teal/cyan palette)
    theme_suffix = "activity_#{activity.slug || "default"}"

    # Build activity-specific content
    activity_content = render_activity_content(activity, theme_suffix, @theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, @theme_colors, activity_content)
  end

  @doc """
  Renders the activity-specific content for a social card.
  Includes image, logo, title, date/time, venue, and city.

  ## Parameters
    - activity: Map with :title, :cover_image_url, :venue, :occurrence_list fields
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with activity-specific content
  """
  def render_activity_content(activity, theme_suffix, theme_colors) do
    # Sanitize activity data
    safe_title = Sanitizer.sanitize_text(Map.get(activity, :title, ""))

    # Extract venue and city info
    venue = Map.get(activity, :venue)
    venue_name = if venue, do: Sanitizer.sanitize_text(Map.get(venue, :name, "")), else: ""

    city_name =
      if venue do
        city_ref = Map.get(venue, :city_ref)
        if city_ref, do: Sanitizer.sanitize_text(Map.get(city_ref, :name, "")), else: ""
      else
        ""
      end

    # Get first occurrence for date/time display
    occurrence_list = Map.get(activity, :occurrence_list) || []
    first_occurrence = List.first(occurrence_list)
    date_time_text = format_activity_date_time(first_occurrence)

    # Build location text (venue + city)
    location_text = build_location_text(venue_name, city_name)

    # Calculate font sizes
    title_font_size = Shared.calculate_font_size(safe_title)

    # Build title sections
    title_line_1 =
      if Shared.format_title(safe_title, 0) != "" do
        y_pos = activity_title_y_position(0, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(safe_title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(safe_title, 1) != "" do
        y_pos = activity_title_y_position(1, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(safe_title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(safe_title, 2) != "" do
        y_pos = activity_title_y_position(2, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(safe_title, 2)}</tspan>)
      else
        ""
      end

    """
    #{Shared.render_image_section(activity, theme_suffix)}

    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Activity title (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{title_font_size}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Date/Time info (below title) -->
    #{render_activity_date_time(date_time_text)}

    <!-- Location info (venue + city) -->
    #{render_activity_location(location_text)}

    #{Shared.render_cta_bubble("VIEW", theme_suffix)}
    """
  end

  @doc """
  Sanitizes activity data for safe use in social card generation.
  """
  def sanitize_activity(activity) do
    venue = Map.get(activity, :venue)

    sanitized_venue =
      if venue do
        city_ref = Map.get(venue, :city_ref)

        sanitized_city =
          if city_ref do
            %{name: Sanitizer.sanitize_text(Map.get(city_ref, :name, ""))}
          else
            nil
          end

        %{
          name: Sanitizer.sanitize_text(Map.get(venue, :name, "")),
          city_ref: sanitized_city
        }
      else
        nil
      end

    %{
      title: Sanitizer.sanitize_text(Map.get(activity, :title, "")),
      slug: Map.get(activity, :slug, ""),
      cover_image_url: Map.get(activity, :cover_image_url),
      venue: sanitized_venue,
      occurrence_list: Map.get(activity, :occurrence_list, []),
      updated_at: Map.get(activity, :updated_at)
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Format date and time for activity card display
  defp format_activity_date_time(nil), do: ""

  defp format_activity_date_time(%{datetime: datetime}) when not is_nil(datetime) do
    # Format: "Sat, Jan 25 • 8:00 PM"
    day_name = Calendar.strftime(datetime, "%a")
    month_day = Calendar.strftime(datetime, "%b %d")
    time = Calendar.strftime(datetime, "%-I:%M %p")
    "#{day_name}, #{month_day} • #{time}"
  end

  defp format_activity_date_time(%{date: date, time: time})
       when not is_nil(date) and not is_nil(time) do
    # Format: "Sat, Jan 25 • 8:00 PM"
    day_name = Calendar.strftime(date, "%a")
    month_day = Calendar.strftime(date, "%b %d")
    time_str = Calendar.strftime(time, "%-I:%M %p")
    "#{day_name}, #{month_day} • #{time_str}"
  end

  defp format_activity_date_time(%{date: date}) when not is_nil(date) do
    # Format: "Sat, Jan 25"
    day_name = Calendar.strftime(date, "%a")
    month_day = Calendar.strftime(date, "%b %d")
    "#{day_name}, #{month_day}"
  end

  defp format_activity_date_time(_), do: ""

  # Build location text from venue and city
  defp build_location_text("", ""), do: ""
  defp build_location_text(venue_name, ""), do: venue_name
  defp build_location_text("", city_name), do: city_name
  defp build_location_text(venue_name, city_name), do: "#{venue_name} • #{city_name}"

  # Render date/time section for activity card
  defp render_activity_date_time(""), do: ""

  defp render_activity_date_time(date_time_text) do
    """
    <text x="32" y="310" font-family="Arial, sans-serif" font-weight="600"
          font-size="20" fill="white" opacity="0.95">
      #{Shared.svg_escape(date_time_text)}
    </text>
    """
  end

  # Render location section for activity card
  defp render_activity_location(""), do: ""

  defp render_activity_location(location_text) do
    # Truncate if too long
    truncated = Shared.truncate_title(location_text, 45)

    """
    <text x="32" y="340" font-family="Arial, sans-serif" font-weight="400"
          font-size="18" fill="white" opacity="0.85">
      #{Shared.svg_escape(truncated)}
    </text>
    """
  end

  # Calculate Y position for activity title lines (positioned higher to make room for date/location)
  @doc false
  def activity_title_y_position(line_number, font_size) when is_binary(font_size) do
    activity_title_y_position(line_number, String.to_integer(font_size))
  end

  def activity_title_y_position(line_number, font_size) when is_integer(font_size) do
    # Start at y=180 (lower than event cards to leave room for logo)
    # Then add spacing based on font size for each line
    base_y = 180
    line_spacing = font_size + 8
    base_y + line_number * line_spacing
  end
end
