defmodule EventasaurusWeb.SocialCards.MovieCardView do
  @moduledoc """
  Movie-specific social card SVG generation.

  Handles rendering of social cards for movies with:
  - Movie title (multi-line, auto-sized)
  - Backdrop/poster image with gradient overlay
  - Release year and runtime
  - Rating display
  - VIEW call-to-action button
  - Fixed purple brand colors (cinema-themed)
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared
  alias EventasaurusWeb.SocialCards.ActivityCardView

  # Movie card brand colors (purple/violet - cinema theme)
  @theme_colors %{
    primary: "#7c3aed",
    secondary: "#a855f7"
  }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders SVG social card for a movie.
  Uses Wombie brand colors with a cinema-themed design showing poster,
  title, release year, and runtime.

  ## Parameters
    - movie: Map with :title, :poster_url, :backdrop_url, :release_date, :runtime, :overview fields

  ## Returns
    Complete SVG markup as a string
  """
  def render_movie_card_svg(movie) do
    # Use Wombie brand theme with cinema-inspired palette (deep purple/indigo)
    theme_suffix = "movie_#{movie[:slug] || movie[:tmdb_id] || "default"}"

    # Build movie-specific content
    movie_content = render_movie_content(movie, theme_suffix, @theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, @theme_colors, movie_content)
  end

  @doc """
  Renders the movie-specific content for a social card.
  Includes poster image, logo, title, year, runtime, and rating.

  ## Parameters
    - movie: Map with :title, :poster_url, :backdrop_url, :release_date, :runtime fields
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with movie-specific content
  """
  def render_movie_content(movie, theme_suffix, theme_colors) do
    # Sanitize movie data
    safe_title = Sanitizer.sanitize_text(Map.get(movie, :title, ""))

    # Extract movie metadata
    release_date = Map.get(movie, :release_date)
    year = if release_date, do: release_date.year, else: nil
    runtime = Map.get(movie, :runtime)
    screening_dates = Map.get(movie, :screening_dates, [])

    # Format metadata line - prefer screening dates if available, fallback to year/runtime
    meta_text =
      if Enum.any?(screening_dates) do
        format_screening_dates(screening_dates)
      else
        format_movie_meta(year, runtime)
      end

    # Get rating from metadata if available
    rating = get_movie_rating(movie)

    # Calculate font sizes
    title_font_size = Shared.calculate_font_size(safe_title)

    # Build title sections (using activity title positioning for consistency)
    title_line_1 =
      if Shared.format_title(safe_title, 0) != "" do
        y_pos = ActivityCardView.activity_title_y_position(0, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(safe_title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(safe_title, 1) != "" do
        y_pos = ActivityCardView.activity_title_y_position(1, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(safe_title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(safe_title, 2) != "" do
        y_pos = ActivityCardView.activity_title_y_position(2, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(safe_title, 2)}</tspan>)
      else
        ""
      end

    # Prepare movie entity with cover_image_url for standard image section
    # Prefer backdrop for social cards (wider format), fallback to poster
    movie_with_cover =
      Map.put(
        movie,
        :cover_image_url,
        Map.get(movie, :backdrop_url) || Map.get(movie, :poster_url)
      )

    """
    #{Shared.render_image_section(movie_with_cover, theme_suffix)}

    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Movie title (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{title_font_size}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Year • Runtime info (below title, y=310 like activity date) -->
    #{render_movie_meta(meta_text)}

    <!-- Rating (y=340 like activity location) -->
    #{render_movie_rating(rating)}

    #{Shared.render_cta_bubble("VIEW", theme_suffix)}
    """
  end

  @doc """
  Sanitizes movie data for safe use in social card generation.
  """
  def sanitize_movie(movie) do
    metadata = Map.get(movie, :metadata, %{})

    %{
      title: Sanitizer.sanitize_text(Map.get(movie, :title, "")),
      slug: Map.get(movie, :slug, ""),
      tmdb_id: Map.get(movie, :tmdb_id),
      poster_url: Map.get(movie, :poster_url),
      backdrop_url: Map.get(movie, :backdrop_url),
      release_date: Map.get(movie, :release_date),
      runtime: Map.get(movie, :runtime),
      overview: Sanitizer.sanitize_text(Map.get(movie, :overview, "")),
      metadata: metadata,
      screening_dates: sanitize_screening_dates(Map.get(movie, :screening_dates)),
      updated_at: Map.get(movie, :updated_at)
    }
  end

  # Sanitize screening dates - ensure they are valid Date structs
  defp sanitize_screening_dates(dates) when is_list(dates) do
    Enum.filter(dates, &is_struct(&1, Date))
  end

  defp sanitize_screening_dates(_), do: []

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Format screening dates for display
  # Shows up to 3 dates in a compact format: "Jan 25, 26, 27" or "Jan 25 • Feb 1"
  defp format_screening_dates([]), do: ""

  defp format_screening_dates(dates) when is_list(dates) do
    case dates do
      [single_date] ->
        # Single date: "Sat, Jan 25"
        format_single_date(single_date)

      multiple_dates ->
        # Multiple dates - group by month for compact display
        format_multiple_dates(multiple_dates)
    end
  end

  defp format_single_date(date) do
    day_name = Calendar.strftime(date, "%a")
    month_day = Calendar.strftime(date, "%b %d")
    "#{day_name}, #{month_day}"
  end

  defp format_multiple_dates(dates) do
    # Group dates by month
    grouped =
      dates
      |> Enum.group_by(fn date -> {date.year, date.month} end)
      |> Enum.sort_by(fn {{year, month}, _} -> {year, month} end)

    # Format each group
    formatted =
      Enum.map(grouped, fn {{_year, _month}, month_dates} ->
        first_date = List.first(month_dates)
        month_abbr = Calendar.strftime(first_date, "%b")
        days = Enum.map(month_dates, fn d -> d.day end) |> Enum.join(", ")
        "#{month_abbr} #{days}"
      end)

    Enum.join(formatted, " • ")
  end

  # Format movie metadata line (year • runtime)
  defp format_movie_meta(nil, nil), do: ""
  defp format_movie_meta(year, nil), do: "#{year}"
  defp format_movie_meta(nil, runtime), do: format_runtime(runtime)
  defp format_movie_meta(year, runtime), do: "#{year} • #{format_runtime(runtime)}"

  # Format runtime in hours and minutes
  defp format_runtime(nil), do: ""

  defp format_runtime(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 and mins > 0 -> "#{hours}h #{mins}m"
      hours > 0 -> "#{hours}h"
      mins > 0 -> "#{mins}m"
      true -> ""
    end
  end

  defp format_runtime(_), do: ""

  # Get movie rating from metadata
  defp get_movie_rating(movie) do
    metadata = Map.get(movie, :metadata, %{})

    # Try to get vote_average from TMDb metadata
    vote_average =
      Map.get(metadata, "vote_average") ||
        Map.get(metadata, :vote_average) ||
        get_in(metadata, ["tmdb", "vote_average"])

    if vote_average && is_number(vote_average) && vote_average > 0 do
      Float.round(vote_average, 1)
    else
      nil
    end
  end

  # Render metadata section for movie card
  defp render_movie_meta(""), do: ""

  defp render_movie_meta(meta_text) do
    """
    <text x="32" y="310" font-family="Arial, sans-serif" font-weight="600"
          font-size="20" fill="white" opacity="0.95">
      #{Shared.svg_escape(meta_text)}
    </text>
    """
  end

  # Render rating section for movie card (positioned at y=340 like activity location)
  defp render_movie_rating(nil), do: ""

  defp render_movie_rating(rating) do
    """
    <text x="32" y="340" font-family="Arial, sans-serif" font-weight="400"
          font-size="18" fill="white" opacity="0.85">★ #{rating}/10</text>
    """
  end
end
