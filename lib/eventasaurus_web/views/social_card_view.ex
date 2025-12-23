defmodule EventasaurusWeb.SocialCardView do
  @moduledoc """
  Facade for social card SVG generation.

  This module provides a unified API for social card generation, delegating to
  type-specific modules for implementation. Controllers use selective imports:

      import EventasaurusWeb.SocialCardView, only: [sanitize_event: 1, render_social_card_svg: 1]

  ## Module Architecture

  Card generation is split into type-specific modules:
  - `EventasaurusWeb.SocialCards.EventCardView` - Private group event cards
  - `EventasaurusWeb.SocialCards.PollCardView` - Poll voting cards
  - `EventasaurusWeb.SocialCards.CityCardView` - City page cards
  - `EventasaurusWeb.SocialCards.ActivityCardView` - Public activity cards
  - `EventasaurusWeb.SocialCards.MovieCardView` - Movie cards
  - `EventasaurusWeb.SocialCards.VenueCardView` - Venue cards
  - `EventasaurusWeb.SocialCards.PerformerCardView` - Performer/artist cards
  - `EventasaurusWeb.SocialCards.SourceAggregationCardView` - Source aggregation cards

  Shared utilities are in `EventasaurusWeb.SocialCards.Shared`.

  ## Entity-Specific Functions

  Each entity type has three primary functions:
  - `sanitize_*` - Sanitize input data for safe SVG rendering
  - `render_*_card_svg` - Generate complete SVG card
  - `render_*_content` - Render entity-specific content section
  """

  # Delegate to type-specific modules
  alias EventasaurusWeb.SocialCards.{
    EventCardView,
    PollCardView,
    CityCardView,
    ActivityCardView,
    MovieCardView,
    VenueCardView,
    PerformerCardView,
    SourceAggregationCardView,
    Shared
  }

  alias Eventasaurus.SocialCards.UrlBuilder

  # ===========================================================================
  # Shared Utilities (delegated to Shared module)
  # ===========================================================================

  @doc """
  Helper function to ensure text fits within specified line limits.
  Truncates text if it exceeds the maximum length for proper display in social cards.
  """
  defdelegate truncate_title(title, max_length \\ 60), to: Shared

  @doc """
  Formats event title for multi-line display in SVG.
  Returns a specific line (0, 1, or 2) of the title.
  """
  defdelegate format_title(title, line_number), to: Shared

  @doc """
  Calculates appropriate font size based on title length.
  """
  defdelegate calculate_font_size(title), to: Shared

  @doc """
  Calculates the Y position for a title line based on line number and font size.
  """
  defdelegate title_line_y_position(line_number, font_size), to: Shared

  @doc """
  Escapes text content for safe use in SVG templates.
  Prevents SVG injection by properly encoding special characters.
  """
  defdelegate svg_escape(text), to: Shared

  @doc """
  Formats color values for safe use in SVG.
  """
  defdelegate format_color(color), to: Shared

  @doc """
  Sanitizes an ID suffix for safe use in SVG element IDs.
  """
  defdelegate safe_svg_id(id_suffix), to: Shared

  @doc """
  Determines if an entity has a valid image URL.
  """
  defdelegate has_image?(entity), to: Shared

  @doc """
  Gets a base64 data URL for local images to embed directly in SVG.
  """
  defdelegate local_image_data_url(entity), to: Shared

  @doc """
  Gets theme colors for a given theme name.
  """
  defdelegate get_theme_colors(theme_name), to: Shared

  @doc """
  Gets the logo as an SVG element.
  """
  defdelegate get_logo_svg_element(theme_suffix, theme_colors), to: Shared

  @doc """
  Renders the background gradient SVG definition and rectangle.
  """
  defdelegate render_background_gradient(theme_suffix, theme_colors), to: Shared

  @doc """
  Renders the background gradient with options.
  """
  defdelegate render_background_gradient(theme_suffix, theme_colors, opts), to: Shared

  @doc """
  Renders the image section for a social card with proper fallback.
  """
  defdelegate render_image_section(entity, theme_suffix), to: Shared

  @doc """
  Renders a call-to-action bubble (e.g., "RSVP", "VOTE").
  """
  defdelegate render_cta_bubble(cta_text, theme_suffix), to: Shared

  @doc """
  Renders the base SVG structure for a social card with a content block.
  """
  defdelegate render_social_card_base(theme_suffix, theme_colors, content_block), to: Shared

  # ===========================================================================
  # Event Social Cards (delegated to EventCardView)
  # ===========================================================================

  @doc """
  Sanitizes complete event data for safe use in social card generation.
  """
  defdelegate sanitize_event(event), to: EventCardView

  @doc """
  Renders a complete SVG social card for an event.
  """
  defdelegate render_social_card_svg(event), to: EventCardView

  @doc """
  Renders the event-specific content for a social card.
  """
  defdelegate render_event_content(event, theme_suffix, theme_colors), to: EventCardView

  @doc """
  Generates the social card URL path for an event using the unified UrlBuilder.
  Returns just the path component; use with UrlHelper.build_url/1 for full URL.
  """
  def social_card_url(event) do
    UrlBuilder.build_path(:event, event)
  end

  # ===========================================================================
  # Poll Social Cards (delegated to PollCardView)
  # ===========================================================================

  @doc """
  Sanitizes poll data for safe use in social card generation.
  """
  defdelegate sanitize_poll(poll), to: PollCardView

  @doc """
  Renders SVG social card for a poll.
  """
  defdelegate render_poll_card_svg(poll), to: PollCardView

  @doc """
  Renders the poll-specific content for a social card.
  """
  defdelegate render_poll_content(poll, event, theme_suffix, theme_colors), to: PollCardView

  # ===========================================================================
  # City Social Cards (delegated to CityCardView)
  # ===========================================================================

  @doc """
  Sanitizes city data for safe use in social card generation.
  """
  defdelegate sanitize_city(city), to: CityCardView

  @doc """
  Renders SVG social card for a city page.
  """
  defdelegate render_city_card_svg(city, stats), to: CityCardView

  @doc """
  Renders the city-specific content for a social card.
  """
  defdelegate render_city_content(city, stats, theme_suffix, theme_colors), to: CityCardView

  # ===========================================================================
  # Activity Social Cards (delegated to ActivityCardView)
  # ===========================================================================

  @doc """
  Sanitizes activity data for safe use in social card generation.
  """
  defdelegate sanitize_activity(activity), to: ActivityCardView

  @doc """
  Renders SVG social card for a public activity (event).
  """
  defdelegate render_activity_card_svg(activity), to: ActivityCardView

  @doc """
  Renders the activity-specific content for a social card.
  """
  defdelegate render_activity_content(activity, theme_suffix, theme_colors), to: ActivityCardView

  # ===========================================================================
  # Movie Social Cards (delegated to MovieCardView)
  # ===========================================================================

  @doc """
  Sanitizes movie data for safe use in social card generation.
  """
  defdelegate sanitize_movie(movie), to: MovieCardView

  @doc """
  Renders SVG social card for a movie.
  """
  defdelegate render_movie_card_svg(movie), to: MovieCardView

  @doc """
  Renders the movie-specific content for a social card.
  """
  defdelegate render_movie_content(movie, theme_suffix, theme_colors), to: MovieCardView

  # ===========================================================================
  # Venue Social Cards (delegated to VenueCardView)
  # ===========================================================================

  @doc """
  Sanitizes venue data for safe use in social card generation.
  """
  defdelegate sanitize_venue(venue), to: VenueCardView

  @doc """
  Renders SVG social card for a venue page.
  """
  defdelegate render_venue_card_svg(venue), to: VenueCardView

  @doc """
  Renders the venue-specific content for a social card.
  """
  defdelegate render_venue_content(venue, theme_suffix, theme_colors), to: VenueCardView

  # ===========================================================================
  # Performer Social Cards (delegated to PerformerCardView)
  # ===========================================================================

  @doc """
  Sanitizes performer data for safe use in social card generation.
  """
  defdelegate sanitize_performer(performer), to: PerformerCardView

  @doc """
  Renders SVG social card for a performer/artist page.
  """
  defdelegate render_performer_card_svg(performer), to: PerformerCardView

  @doc """
  Renders the performer-specific content for a social card.
  """
  defdelegate render_performer_content(performer, theme_suffix, theme_colors),
    to: PerformerCardView

  # ===========================================================================
  # Source Aggregation Social Cards (delegated to SourceAggregationCardView)
  # ===========================================================================

  @doc """
  Sanitizes source aggregation data for safe use in social card generation.
  """
  defdelegate sanitize_source_aggregation(aggregation), to: SourceAggregationCardView

  @doc """
  Renders SVG social card for a source aggregation page.
  """
  defdelegate render_source_aggregation_card_svg(aggregation), to: SourceAggregationCardView

  @doc """
  Renders the source aggregation-specific content for a social card.
  """
  defdelegate render_source_aggregation_content(aggregation, theme_suffix, theme_colors),
    to: SourceAggregationCardView

  # ===========================================================================
  # Legacy Functions (kept for backward compatibility)
  # ===========================================================================

  @doc """
  Gets a safe image URL for SVG rendering.
  Returns the validated URL if valid, otherwise returns nil.
  """
  def safe_image_url(%{cover_image_url: url}) do
    Eventasaurus.SocialCards.Sanitizer.validate_image_url(url)
  end

  def safe_image_url(_), do: nil

  @doc """
  Gets sanitized event title for safe SVG rendering.
  """
  def safe_title(event) do
    title = Map.get(event, :title, "")
    Eventasaurus.SocialCards.Sanitizer.sanitize_text(title)
  end

  @doc """
  Gets sanitized event description for safe SVG rendering.
  """
  def safe_description(event) do
    description = Map.get(event, :description, "")
    Eventasaurus.SocialCards.Sanitizer.sanitize_text(description)
  end
end
