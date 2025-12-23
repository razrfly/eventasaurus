defmodule EventasaurusWeb.SocialCards.CityCardView do
  @moduledoc """
  City-specific social card SVG generation.

  Handles rendering of social cards for city pages with:
  - City name (large, centered)
  - Stats display (Events • Venues • Categories)
  - Tagline
  - EXPLORE call-to-action button
  - Fixed blue brand colors (no theme selection)
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared

  # City card brand colors (deep blue to bright blue)
  @theme_colors %{
    primary: "#1e40af",
    secondary: "#3b82f6"
  }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders a complete SVG social card for a city page with stats.
  Stats-heavy design: City name + event/venue/category counts.

  ## Parameters
    - city: Map with :name, :slug fields
    - stats: Map with :events_count, :venues_count, :categories_count

  ## Returns
    Complete SVG markup as a string
  """
  def render_city_card_svg(city, stats \\ %{}) do
    # Use minimal theme for city cards (clean, professional look)
    theme_suffix = "city_#{city.slug}"

    # Build city-specific content
    city_content = render_city_content(city, stats, theme_suffix, @theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, @theme_colors, city_content)
  end

  @doc """
  Renders the city-specific content for a social card.
  Includes logo, city name, and stats (Events • Venues • Categories).

  ## Parameters
    - city: Map with :name field
    - stats: Map with :events_count, :venues_count, :categories_count
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with city-specific content
  """
  def render_city_content(city, stats, theme_suffix, theme_colors) do
    # Sanitize city name
    safe_city_name = Sanitizer.sanitize_text(city.name)

    # Build stats string: "127 Events • 45 Venues • 12 Categories"
    events_count = Map.get(stats, :events_count, 0)
    venues_count = Map.get(stats, :venues_count, 0)
    categories_count = Map.get(stats, :categories_count, 0)

    stats_text = build_stats_text(events_count, venues_count, categories_count)

    # Calculate font size for city name based on length
    city_font_size = calculate_city_name_font_size(safe_city_name)

    """
    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- City name (large, centered) -->
    <text x="400" y="180" text-anchor="middle"
          font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{city_font_size}" fill="white">
      #{Shared.svg_escape(safe_city_name)}
    </text>

    <!-- Stats line (centered below city name) -->
    <text x="400" y="240" text-anchor="middle"
          font-family="Arial, sans-serif" font-weight="600"
          font-size="32" fill="white" opacity="0.95">
      #{Shared.svg_escape(stats_text)}
    </text>

    <!-- Tagline (centered below stats) -->
    <text x="400" y="290" text-anchor="middle"
          font-family="Arial, sans-serif" font-weight="400"
          font-size="24" fill="white" opacity="0.85">
      Your event discovery platform
    </text>

    #{Shared.render_cta_bubble("EXPLORE", theme_suffix)}
    """
  end

  @doc """
  Sanitizes city data for safe use in social card generation.
  """
  def sanitize_city(city) do
    %{
      name: Sanitizer.sanitize_text(Map.get(city, :name, "")),
      slug: Map.get(city, :slug, "")
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Build stats text: "127 Events • 45 Venues • 12 Categories"
  defp build_stats_text(events_count, venues_count, categories_count) do
    parts = []

    parts =
      if events_count > 0 do
        event_text = if events_count == 1, do: "Event", else: "Events"
        parts ++ ["#{events_count} #{event_text}"]
      else
        parts
      end

    parts =
      if venues_count > 0 do
        venue_text = if venues_count == 1, do: "Venue", else: "Venues"
        parts ++ ["#{venues_count} #{venue_text}"]
      else
        parts
      end

    parts =
      if categories_count > 0 do
        category_text = if categories_count == 1, do: "Category", else: "Categories"
        parts ++ ["#{categories_count} #{category_text}"]
      else
        parts
      end

    if Enum.any?(parts) do
      Enum.join(parts, " • ")
    else
      "Discover upcoming events"
    end
  end

  # Calculate appropriate font size for city name based on length
  defp calculate_city_name_font_size(city_name) when is_binary(city_name) do
    length = String.length(city_name)

    cond do
      # Short city names: Large font
      length <= 8 -> "72"
      # Medium city names
      length <= 12 -> "60"
      # Longer city names
      length <= 16 -> "48"
      # Very long city names
      true -> "36"
    end
  end

  defp calculate_city_name_font_size(_), do: "60"
end
