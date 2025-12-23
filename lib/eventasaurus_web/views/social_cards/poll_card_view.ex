defmodule EventasaurusWeb.SocialCards.PollCardView do
  @moduledoc """
  Poll-specific social card SVG generation.

  Handles rendering of social cards for polls with:
  - Poll title (multi-line, auto-sized)
  - Poll type badge with Twemoji icons
  - Poll options list (top 4 options)
  - Theme-based colors from parent event
  - VOTE call-to-action button
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias EventasaurusWeb.SocialCards.Shared

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Renders SVG social card for a poll.
  Uses the same component-based architecture as event cards.

  ## Parameters
    - poll: Map with :title, :poll_type, :event (with :theme) fields

  ## Returns
    Complete SVG markup as a string
  """
  def render_poll_card_svg(poll) do
    # Get parent event for theme (handle nil/NotLoaded)
    event =
      case Map.get(poll, :event) do
        %Ecto.Association.NotLoaded{} -> %{theme: :minimal}
        nil -> %{theme: :minimal}
        ev when is_map(ev) -> ev
        _ -> %{theme: :minimal}
      end

    # Sanitize poll data
    sanitized_poll = sanitize_poll(poll)

    # Get theme from parent event
    theme_name = event.theme || :minimal
    theme_suffix = to_string(theme_name)

    # Get theme colors
    theme_colors =
      case Shared.get_theme_colors(theme_name) do
        %{primary: primary, secondary: secondary} = colors
        when is_binary(primary) and is_binary(secondary) ->
          colors

        _ ->
          %{primary: "#1a1a1a", secondary: "#333333"}
      end

    # Build poll-specific content
    poll_content = render_poll_content(sanitized_poll, event, theme_suffix, theme_colors)

    # Use the base function to create complete SVG
    Shared.render_social_card_base(theme_suffix, theme_colors, poll_content)
  end

  @doc """
  Renders the poll-specific content for a social card.
  This includes the logo, poll title, poll type indicator, and VOTE button.

  ## Parameters
    - poll: Sanitized poll map with :title, :poll_type fields
    - event: Parent event map (for potential future use)
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with theme color information

  ## Returns
    SVG markup string with poll-specific content
  """
  def render_poll_content(poll, _event, theme_suffix, theme_colors) do
    # Format poll title (max 3 lines)
    title_line_1 =
      if Shared.format_title(poll.title, 0) != "" do
        y_pos = Shared.title_line_y_position(0, Shared.calculate_font_size(poll.title))
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(poll.title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if Shared.format_title(poll.title, 1) != "" do
        y_pos = Shared.title_line_y_position(1, Shared.calculate_font_size(poll.title))
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(poll.title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if Shared.format_title(poll.title, 2) != "" do
        y_pos = Shared.title_line_y_position(2, Shared.calculate_font_size(poll.title))
        ~s(<tspan x="32" y="#{y_pos}">#{Shared.format_title(poll.title, 2)}</tspan>)
      else
        ""
      end

    """
    <!-- Logo (top-left) -->
    #{Shared.get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Poll type indicator (right side, below logo) -->
    #{render_poll_type_badge(poll.poll_type)}

    <!-- Poll title (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{Shared.calculate_font_size(poll.title)}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Poll options list or ballot box fallback (right side) -->
    #{render_poll_options_list(poll, theme_suffix)}

    #{Shared.render_cta_bubble("VOTE", theme_suffix)}
    """
  end

  @doc """
  Sanitizes poll data for safe use in social card generation.
  Similar to sanitize_event but for poll-specific fields.
  """
  def sanitize_poll(poll) do
    %{
      title: Sanitizer.sanitize_text(Map.get(poll, :title, "")),
      poll_type: Map.get(poll, :poll_type, "custom"),
      poll_options: Map.get(poll, :poll_options, [])
    }
  end

  # ===========================================================================
  # Poll Type Badge Rendering
  # ===========================================================================

  # Renders a colorful badge for poll type indicator
  # Left-justified layout with larger icon (30x30) and no background
  defp render_poll_type_badge(poll_type) do
    {icon_svg, badge_text} = get_poll_type_badge_info(poll_type)

    """
    <g>
      <!-- Icon with color (50% larger: 30x30 instead of 20x20) -->
      <g transform="translate(450, 88)">
        #{icon_svg}
      </g>

      <!-- Badge text (left-aligned next to icon) -->
      <text x="490" y="110" text-anchor="start"
            font-family="Arial, sans-serif" font-size="29"
            font-weight="600" fill="white" opacity="0.95">
        #{badge_text}
      </text>
    </g>
    """
  end

  # ===========================================================================
  # Poll Type Badge Icons - Twemoji Integration
  # ===========================================================================
  #
  # Icon source: Twitter Twemoji (https://github.com/twitter/twemoji)
  # License: MIT License - Copyright 2019 Twitter, Inc and other contributors
  # Graphics licensed under CC-BY 4.0: https://creativecommons.org/licenses/by/4.0/
  #
  # These SVG paths are extracted from Twemoji and scaled to fit 30x30 icon space.
  # Original Twemoji viewBox is 0 0 36 36, scaled here with transform to ~0.834x (30/36).

  # Returns {icon_svg, text} for each poll type
  defp get_poll_type_badge_info("movie") do
    {
      """
      <g transform="scale(0.834)">
        <path fill="#3F7123" d="M35.845 32c0 2.2-1.8 4-4 4h-26c-2.2 0-4-1.8-4-4V19c0-2.2 1.8-4 4-4h26c2.2 0 4 1.8 4 4v13z"/>
        <path fill="#3F7123" d="M1.845 15h34v6h-34z"/>
        <path fill="#CCD6DD" d="M1.845 15h34v7h-34z"/>
        <path fill="#292F33" d="M1.845 15h4l-4 7v-7zm11 0l-4 7h7l4-7h-7zm14 0l-4 7h7l4-7h-7z"/>
        <path fill="#CCD6DD" d="M.155 8.207L33.148 0l1.69 6.792L1.845 15z"/>
        <path fill="#292F33" d="M.155 8.207l5.572 5.827L1.845 15 .155 8.207zm19.158 2.448l-5.572-5.828-6.793 1.69 5.572 5.828 6.793-1.69zm13.586-3.38l-5.572-5.828-6.793 1.69 5.572 5.827 6.793-1.689z"/>
      </g>
      """,
      "Movie Poll"
    }
  end

  defp get_poll_type_badge_info("places") do
    {
      """
      <g transform="scale(0.834)">
        <ellipse fill="#292F33" cx="18" cy="34.5" rx="4" ry="1.5"/>
        <path fill="#99AAB5" d="M14.339 10.725S16.894 34.998 18.001 35c1.106.001 3.66-24.275 3.66-24.275h-7.322z"/>
        <circle fill="#DD2E44" cx="18" cy="8" r="8"/>
      </g>
      """,
      "Places Poll"
    }
  end

  defp get_poll_type_badge_info("venue") do
    {
      """
      <g transform="scale(0.834)">
        <path fill="#DAC8B1" d="M34 13c0 1.104-.896 2-2 2h-6c-1.104 0-2-.896-2-2v-2c0-1.104.896-2 2-2h6c1.104 0 2 .896 2 2v2zm-22 0c0 1.104-.896 2-2 2H4c-1.104 0-2-.896-2-2v-2c0-1.104.896-2 2-2h6c1.104 0 2 .896 2 2v2z"/>
        <path fill="#F1DCC1" d="M36 34c0 1.104-.896 2-2 2H2c-1.104 0-2-.896-2-2V13c0-1.104.896-2 2-2h32c1.104 0 2 .896 2 2v21z"/>
        <path fill="#DAC8B1" d="M22 9V7c0-.738-.404-1.376-1-1.723V5c0-1.104-.896-2-2-2h-2c-1.104 0-2 .896-2 2v.277c-.595.347-1 .985-1 1.723v2h-1v27h10V9h-1z"/>
        <path fill="#55ACEE" d="M14 7h2v2h-2zm6 0h2v2h-2zm-3 0h2v2h-2z"/>
        <path fill="#3B88C3" d="M15 15h2v14h-2zm4 0h2v14h-2z"/>
        <path fill="#55ACEE" d="M24 17h2v12h-2zm4 0h2v12h-2zm4 0h2v12h-2zM2 17h2v12H2zm4 0h2v12H6zm4 0h2v12h-2zM2 30h2v2H2zm4 0h2v2H6zm4 0h2v2h-2z"/>
        <path fill="#3B88C3" d="M15 30h2v2h-2zm4 0h2v2h-2z"/>
        <path fill="#55ACEE" d="M24 30h2v2h-2zm4 0h2v2h-2zm4 0h2v2h-2z"/>
        <path fill="#66757F" d="M2 33h2v3H2zm4 0h2v3H6zm4 0h2v3h-2zm5 0h2v3h-2zm4 0h2v3h-2zm5 0h2v3h-2zm4 0h2v3h-2zm4 0h2v3h-2z"/>
      </g>
      """,
      "Venue Poll"
    }
  end

  defp get_poll_type_badge_info("date_selection") do
    {
      """
      <g transform="scale(0.834)">
        <path fill="#E0E7EC" d="M36 32c0 2.209-1.791 4-4 4H4c-2.209 0-4-1.791-4-4V9c0-2.209 1.791-4 4-4h28c2.209 0 4 1.791 4 4v23z"/>
        <path d="M23.657 19.12H17.87c-1.22 0-1.673-.791-1.673-1.56 0-.791.429-1.56 1.673-1.56h8.184c1.154 0 1.628 1.04 1.628 1.628 0 .452-.249.927-.52 1.492l-5.607 11.395c-.633 1.266-.882 1.717-1.899 1.717-1.244 0-1.877-.949-1.877-1.605 0-.271.068-.474.226-.791l5.652-10.716zM10.889 19h-.5c-1.085 0-1.538-.731-1.538-1.5 0-.792.565-1.5 1.538-1.5h2.015c.972 0 1.515.701 1.515 1.605V30.47c0 1.13-.558 1.763-1.53 1.763s-1.5-.633-1.5-1.763V19z" fill="#66757F"/>
        <path fill="#DD2F45" d="M34 0h-3.277c.172.295.277.634.277 1 0 1.104-.896 2-2 2s-2-.896-2-2c0-.366.105-.705.277-1H8.723C8.895.295 9 .634 9 1c0 1.104-.896 2-2 2s-2-.896-2-2c0-.366.105-.705.277-1H2C.896 0 0 .896 0 2v11h36V2c0-1.104-.896-2-2-2z"/>
        <path d="M13.182 4.604c0-.5.32-.78.75-.78.429 0 .749.28.749.78v5.017h1.779c.51 0 .73.38.72.72-.02.33-.28.659-.72.659h-2.498c-.49 0-.78-.319-.78-.819V4.604zm-6.91 0c0-.5.32-.78.75-.78s.75.28.75.78v3.488c0 .92.589 1.649 1.539 1.649.909 0 1.529-.769 1.529-1.649V4.604c0-.5.319-.78.749-.78s.75.28.75.78v3.568c0 1.679-1.38 2.949-3.028 2.949-1.669 0-3.039-1.25-3.039-2.949V4.604zM5.49 9.001c0 1.679-1.069 2.119-1.979 2.119-.689 0-1.839-.27-1.839-1.14 0-.269.23-.609.56-.609.4 0 .75.37 1.199.37.56 0 .56-.52.56-.84V4.604c0-.5.32-.78.749-.78.431 0 .75.28.75.78v4.397z" fill="#F5F8FA"/>
        <path d="M32 10c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1m0-3c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1m-3 3c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1m0-3c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1m-3 3c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1m0-3c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1m-3 0c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1m0 3c0 .552.447 1 1 1s1-.448 1-1-.447-1-1-1-1 .448-1 1" fill="#F4ABBA"/>
      </g>
      """,
      "Date Poll"
    }
  end

  defp get_poll_type_badge_info("time") do
    {
      """
      <g transform="scale(0.834)">
        <path fill="#FFCC4D" d="M20 6.042c0 1.112-.903 2.014-2 2.014s-2-.902-2-2.014V2.014C16 .901 16.903 0 18 0s2 .901 2 2.014v4.028z"/>
        <path fill="#FFAC33" d="M9.18 36c-.224 0-.452-.052-.666-.159-.736-.374-1.035-1.28-.667-2.027l8.94-18.127c.252-.512.768-.835 1.333-.835s1.081.323 1.333.835l8.941 18.127c.368.747.07 1.653-.666 2.027-.736.372-1.631.07-1.999-.676L18.121 19.74l-7.607 15.425c-.262.529-.788.835-1.334.835z"/>
        <path fill="#58595B" d="M18.121 20.392c-.263 0-.516-.106-.702-.295L3.512 5.998c-.388-.394-.388-1.031 0-1.424s1.017-.393 1.404 0L18.121 17.96 31.324 4.573c.389-.393 1.017-.393 1.405 0 .388.394.388 1.031 0 1.424l-13.905 14.1c-.187.188-.439.295-.703.295z"/>
        <path fill="#DD2E44" d="M34.015 19.385c0 8.898-7.115 16.111-15.894 16.111-8.777 0-15.893-7.213-15.893-16.111 0-8.9 7.116-16.113 15.893-16.113 8.778-.001 15.894 7.213 15.894 16.113z"/>
        <path fill="#E6E7E8" d="M30.041 19.385c0 6.674-5.335 12.084-11.92 12.084-6.583 0-11.919-5.41-11.919-12.084C6.202 12.71 11.538 7.3 18.121 7.3c6.585-.001 11.92 5.41 11.92 12.085z"/>
        <path fill="#FFCC4D" d="M30.04 1.257c-1.646 0-3.135.676-4.214 1.77l8.429 8.544C35.333 10.478 36 8.968 36 7.299c0-3.336-2.669-6.042-5.96-6.042zm-24.08 0c1.645 0 3.135.676 4.214 1.77l-8.429 8.544C.667 10.478 0 8.968 0 7.299c0-3.336 2.668-6.042 5.96-6.042z"/>
        <path fill="#414042" d="M23 20h-5c-.552 0-1-.447-1-1v-9c0-.552.448-1 1-1s1 .448 1 1v8h4c.553 0 1 .448 1 1 0 .553-.447 1-1 1z"/>
      </g>
      """,
      "Time Poll"
    }
  end

  defp get_poll_type_badge_info("music_track") do
    {
      """
      <g transform="scale(0.834)">
        <path fill="#5DADEC" d="M34.209.206L11.791 2.793C10.806 2.907 10 3.811 10 4.803v18.782C9.09 23.214 8.075 23 7 23c-3.865 0-7 2.685-7 6 0 3.314 3.135 6 7 6s7-2.686 7-6V10.539l18-2.077v13.124c-.91-.372-1.925-.586-3-.586-3.865 0-7 2.685-7 6 0 3.314 3.135 6 7 6s7-2.686 7-6V1.803c0-.992-.806-1.71-1.791-1.597z"/>
      </g>
      """,
      "Music Poll"
    }
  end

  defp get_poll_type_badge_info(_) do
    {
      """
      <g transform="scale(0.834)">
        <path fill="#CCD6DD" d="M31 2H5C3.343 2 2 3.343 2 5v26c0 1.657 1.343 3 3 3h26c1.657 0 3-1.343 3-3V5c0-1.657-1.343-3-3-3z"/>
        <path fill="#E1E8ED" d="M31 1H5C2.791 1 1 2.791 1 5v26c0 2.209 1.791 4 4 4h26c2.209 0 4-1.791 4-4V5c0-2.209-1.791-4-4-4zm0 2c1.103 0 2 .897 2 2v4h-6V3h4zm-4 16h6v6h-6v-6zm0-2v-6h6v6h-6zM25 3v6h-6V3h6zm-6 8h6v6h-6v-6zm0 8h6v6h-6v-6zM17 3v6h-6V3h6zm-6 8h6v6h-6v-6zm0 8h6v6h-6v-6zM3 5c0-1.103.897-2 2-2h4v6H3V5zm0 6h6v6H3v-6zm0 8h6v6H3v-6zm2 14c-1.103 0-2-.897-2-2v-4h6v6H5zm6 0v-6h6v6h-6zm8 0v-6h6v6h-6zm12 0h-4v-6h6v4c0 1.103-.897 2-2 2z"/>
        <path fill="#5C913B" d="M13 33H7V16c0-1.104.896-2 2-2h2c1.104 0 2 .896 2 2v17z"/>
        <path fill="#3B94D9" d="M29 33h-6V9c0-1.104.896-2 2-2h2c1.104 0 2 .896 2 2v24z"/>
        <path fill="#DD2E44" d="M21 33h-6V23c0-1.104.896-2 2-2h2c1.104 0 2 .896 2 2v10z"/>
      </g>
      """,
      "Poll"
    }
  end

  # ===========================================================================
  # Poll Options List Rendering
  # ===========================================================================

  # Renders the poll options list for social cards.
  # Shows top 4 options or ballot box fallback for empty polls.
  defp render_poll_options_list(poll, _theme_suffix) do
    options = Map.get(poll, :poll_options, [])

    case length(options) do
      0 ->
        # Fallback to ballot box for empty polls
        render_ballot_box_fallback()

      count ->
        # Show top 4 options
        top_options = Enum.take(options, 4)
        remaining = max(count - 4, 0)

        option_texts =
          top_options
          |> Enum.with_index()
          |> Enum.map(fn {option, index} ->
            y_pos = 145 + index * 35
            option_title = Map.get(option, :title) || Map.get(option, "title") || ""
            truncated_title = truncate_option_title(option_title, 25)

            """
            <text x="450" y="#{y_pos}" font-family="Arial, sans-serif"
                  font-size="28" font-weight="600" fill="white" opacity="0.95">
              ✓ #{Shared.svg_escape(truncated_title)}
            </text>
            """
          end)
          |> Enum.join("\n")

        more_text =
          if remaining > 0 do
            plural = if remaining == 1, do: "", else: "s"

            """
            <text x="450" y="290" font-family="Arial, sans-serif"
                  font-size="24" font-weight="500" fill="white" opacity="0.8">
              +#{remaining} more option#{plural}
            </text>
            """
          else
            ""
          end

        """
        #{option_texts}
        #{more_text}
        """
    end
  end

  # Truncates poll option titles for display in social cards.
  defp truncate_option_title(title, max_length) when is_binary(title) do
    if String.length(title) <= max_length do
      title
    else
      String.slice(title, 0, max_length - 3) <> "..."
    end
  end

  defp truncate_option_title(_, _), do: ""

  # Renders ballot box fallback for polls with no options.
  defp render_ballot_box_fallback do
    """
    <!-- Vote icon/indicator (right side, large) -->
    <circle cx="600" cy="240" r="80" fill="white" opacity="0.15"/>
    <text x="600" y="260" text-anchor="middle" font-family="Arial, sans-serif"
          font-size="64" font-weight="bold" fill="white" opacity="0.9">
      🗳️
    </text>
    """
  end
end
