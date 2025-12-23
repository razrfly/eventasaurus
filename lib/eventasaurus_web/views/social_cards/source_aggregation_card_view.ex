defmodule EventasaurusWeb.SocialCards.SourceAggregationCardView do
  @moduledoc """
  Source Aggregation-specific social card SVG generation.

  Handles rendering of social cards for source aggregation pages with:
  - Source name (multi-line, auto-sized)
  - Hero image with gradient overlay
  - Category badge
  - Location count display
  - VIEW call-to-action button
  - Fixed indigo brand colors (professional, source-neutral)
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared
  alias EventasaurusWeb.SocialCards.ActivityCardView

  # Source aggregation card brand colors (indigo/blue - neutral, professional)
  @theme_colors %{
    primary: "#4f46e5",
    secondary: "#6366f1"
  }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders SVG social card for a source aggregation page.
  Shows events from a specific source/brand in a city.

  ## Parameters
    - aggregation: Map with :source_name, :city, :content_type, :location_count, :hero_image fields

  ## Returns
    Complete SVG markup as a string
  """
  def render_source_aggregation_card_svg(aggregation) do
    # Use Wombie brand theme with source-neutral palette (indigo/blue)
    city_slug = get_in(aggregation, [:city, :slug]) || "default"
    source_slug = Map.get(aggregation, :identifier, "source")
    theme_suffix = "source_#{city_slug}_#{source_slug}"

    # Build source aggregation content
    aggregation_content =
      render_source_aggregation_content(aggregation, theme_suffix, @theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, @theme_colors, aggregation_content)
  end

  @doc """
  Renders the source aggregation content for a social card.
  Includes hero image, logo, source name, city, location count, and category.

  ## Parameters
    - aggregation: Map with source aggregation data
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with source aggregation content
  """
  def render_source_aggregation_content(aggregation, theme_suffix, theme_colors) do
    # Extract and sanitize data
    source_name = Sanitizer.sanitize_text(Map.get(aggregation, :source_name, ""))
    city = Map.get(aggregation, :city, %{})
    city_name = Sanitizer.sanitize_text(Map.get(city, :name, ""))
    location_count = Map.get(aggregation, :location_count, 0)
    content_type = Map.get(aggregation, :content_type, "Event")

    # Prepare entity with hero image for image section
    hero_image = Map.get(aggregation, :hero_image)
    entity_with_image = %{cover_image_url: hero_image}

    # Format location count text
    location_text = format_location_count(location_count, city_name)

    # Format category/content type
    category_text = format_content_type_display(content_type)

    # Calculate font size for source name
    source_font_size = Shared.calculate_font_size(source_name)

    # Build title sections
    title_line_1 =
      if Shared.format_title(source_name, 0) != "" do
        y_pos = ActivityCardView.activity_title_y_position(0, source_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(source_name, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(source_name, 1) != "" do
        y_pos = ActivityCardView.activity_title_y_position(1, source_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(source_name, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(source_name, 2) != "" do
        y_pos = ActivityCardView.activity_title_y_position(2, source_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(source_name, 2)}</tspan>)
      else
        ""
      end

    """
    #{Shared.render_image_section(entity_with_image, theme_suffix)}

    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Source name (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{source_font_size}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Category badge (below title, y=310) -->
    #{render_source_category(category_text)}

    <!-- Location count (y=340 like activity location) -->
    #{render_source_location_count(location_text)}

    #{Shared.render_cta_bubble("VIEW", theme_suffix)}
    """
  end

  @doc """
  Sanitizes source aggregation data for safe use in social card generation.
  """
  def sanitize_source_aggregation(aggregation) do
    city = Map.get(aggregation, :city, %{})

    sanitized_city = %{
      name: Sanitizer.sanitize_text(Map.get(city, :name, "")),
      slug: Map.get(city, :slug, "")
    }

    %{
      source_name: Sanitizer.sanitize_text(Map.get(aggregation, :source_name, "")),
      identifier: Map.get(aggregation, :identifier, ""),
      city: sanitized_city,
      content_type: Map.get(aggregation, :content_type, ""),
      location_count: Map.get(aggregation, :location_count, 0),
      hero_image: Map.get(aggregation, :hero_image),
      updated_at: Map.get(aggregation, :updated_at)
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Format location count for display
  defp format_location_count(0, _city_name), do: ""
  defp format_location_count(count, "") when count == 1, do: "1 location"
  defp format_location_count(count, "") when count > 1, do: "#{count} locations"
  defp format_location_count(count, city_name) when count == 1, do: "1 location in #{city_name}"
  defp format_location_count(count, city_name), do: "#{count} locations in #{city_name}"

  # Format content type for display
  defp format_content_type_display("SocialEvent"), do: "Social Events"
  defp format_content_type_display("FoodEvent"), do: "Food & Dining"
  defp format_content_type_display("MusicEvent"), do: "Music Events"
  defp format_content_type_display("ComedyEvent"), do: "Comedy Shows"
  defp format_content_type_display("DanceEvent"), do: "Dance Events"
  defp format_content_type_display("EducationEvent"), do: "Classes & Workshops"
  defp format_content_type_display("SportsEvent"), do: "Sports Events"
  defp format_content_type_display("TheaterEvent"), do: "Theater"
  defp format_content_type_display("Festival"), do: "Festival"
  defp format_content_type_display("ScreeningEvent"), do: "Movie Screenings"
  defp format_content_type_display(type) when is_binary(type), do: type
  defp format_content_type_display(_), do: "Events"

  # Render category badge for source aggregation card
  defp render_source_category(""), do: ""

  defp render_source_category(category_text) do
    """
    <text x="32" y="310" font-family="Arial, sans-serif" font-weight="600"
          font-size="20" fill="white" opacity="0.95">
      #{Shared.svg_escape(category_text)}
    </text>
    """
  end

  # Render location count for source aggregation card
  defp render_source_location_count(""), do: ""

  defp render_source_location_count(location_text) do
    """
    <text x="32" y="340" font-family="Arial, sans-serif" font-weight="400"
          font-size="18" fill="white" opacity="0.85">
      #{Shared.svg_escape(location_text)}
    </text>
    """
  end
end
