defmodule EventasaurusWeb.EventSocialCardController do
  use EventasaurusWeb, :controller

  require Logger

  alias EventasaurusApp.Events
  alias Eventasaurus.Services.SvgConverter
  alias Eventasaurus.SocialCards.HashGenerator
  import EventasaurusWeb.SocialCardView

  @doc """
  Generates a social card PNG for an event by slug with hash validation.
  Provides cache busting through hash-based URLs.
  """
  def generate_card_by_slug(conn, %{"slug" => slug, "hash" => hash, "rest" => rest}) do
    Logger.info("Social card requested for event slug: #{slug}, hash: #{hash}, rest: #{inspect(rest)}")

    # The hash should be clean now, but check if rest contains .png
    final_hash = if rest == ["png"] do
      hash  # Hash is clean, rest contains the extension
    else
      # Fallback: extract hash from combined parameter
      combined = if is_list(rest) and length(rest) > 0 do
        "#{hash}.#{Enum.join(rest, ".")}"
      else
        hash
      end
      String.replace_suffix(combined, ".png", "")
    end

    case Events.get_event_by_slug(slug) do
      nil ->
        Logger.warning("Event not found for slug: #{slug}")
        send_resp(conn, 404, "Event not found")

      event ->
        # Validate that the hash matches current event data
        case HashGenerator.validate_hash(event, final_hash) do
          true ->
            Logger.info("Hash validated for event #{slug}: #{event.title}")

            # Check for system dependencies first
            case SvgConverter.verify_rsvg_available() do
              :ok ->
                # Sanitize event data before rendering
                sanitized_event = sanitize_event(event)

                # Render SVG template with sanitized event data
                svg_content = render_svg_template(sanitized_event)

                # Convert SVG to PNG
                case SvgConverter.svg_to_png(svg_content, event.slug, sanitized_event) do
              {:ok, png_path} ->
                # Read the PNG file and serve it
                case File.read(png_path) do
                  {:ok, png_data} ->
                    Logger.info("Successfully generated social card PNG for slug #{slug} (#{byte_size(png_data)} bytes)")

                    # Clean up the temporary file
                    SvgConverter.cleanup_temp_file(png_path)

                    conn
                    |> put_resp_content_type("image/png")
                    |> put_resp_header("cache-control", "public, max-age=31536000")  # Cache for 1 year since hash ensures freshness
                    |> put_resp_header("etag", "\"#{final_hash}\"")
                    |> send_resp(200, png_data)

                  {:error, reason} ->
                    Logger.error("Failed to read PNG file for slug #{slug}: #{inspect(reason)}")
                    SvgConverter.cleanup_temp_file(png_path)
                    send_resp(conn, 500, "Failed to generate social card")
                end

                  {:error, reason} ->
                    Logger.error("Failed to convert SVG to PNG for slug #{slug}: #{inspect(reason)}")
                    send_resp(conn, 500, "Failed to generate social card")
                end

              {:error, :command_not_found} ->
                Logger.error("rsvg-convert command not found - social card generation unavailable. Install librsvg2-bin package.")

                conn
                |> put_resp_content_type("text/plain")
                |> send_resp(503, "Social card generation temporarily unavailable - missing system dependency")
            end

          false ->
            Logger.warning("Hash mismatch for event #{slug}. Expected: #{HashGenerator.generate_hash(event)}, Got: #{final_hash}")

            # Redirect to current URL with correct hash
            current_url = HashGenerator.generate_url_path(event)

            conn
            |> put_resp_header("location", current_url)
            |> send_resp(301, "Social card URL has been updated")
        end
    end
  end

    # Private helper to render SVG template with proper context
  defp render_svg_template(event) do
    # Get theme colors from event's theme with error handling
    theme_colors = case get_theme_colors(event.theme || :minimal) do
      %{primary: primary, secondary: secondary} = colors when is_binary(primary) and is_binary(secondary) ->
        colors
      _ ->
        Logger.warning("Failed to get valid theme colors for theme: #{inspect(event.theme)}, using defaults")
        %{primary: "#1a1a1a", secondary: "#333333"}
    end
    theme = %{color1: theme_colors.primary, color2: theme_colors.secondary}

    # Build image section - use different approaches for local vs external images
    image_section = if has_image?(event) do
      # Check if this is a local static file or external URL
      if String.starts_with?(event.cover_image_url, "/") do
        # Local static file - use base64 data URL (this works)
        case local_image_data_url(event) do
          nil ->
            # Fallback to "No Image" if image processing fails
            """
            <rect x="418" y="32" width="350" height="350" rx="24" ry="24" fill="#f3f4f6" stroke="#e5e7eb" stroke-width="2"/>
            <text x="593" y="220" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" fill="#9ca3af">No Image</text>
            """
          data_url ->
            """
            <image href="#{data_url}"
                   x="418" y="32"
                   width="350" height="350"
                   clip-path="url(#imageClip)"
                   preserveAspectRatio="xMidYMid slice"/>
            """
        end
      else
        # External URL - download, optimize, and use base64 data URL
        case optimized_external_image_data_url(event) do
          nil ->
            # Fallback to "No Image" if download/optimization fails
            """
            <rect x="418" y="32" width="350" height="350" rx="24" ry="24" fill="#f3f4f6" stroke="#e5e7eb" stroke-width="2"/>
            <text x="593" y="220" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" fill="#9ca3af">No Image</text>
            """
          data_url ->
            """
            <image href="#{data_url}"
                   x="418" y="32"
                   width="350" height="350"
                   clip-path="url(#imageClip)"
                   preserveAspectRatio="xMidYMid slice"/>
            """
        end
      end
    else
      """
      <rect x="418" y="32" width="350" height="350" rx="24" ry="24" fill="#f3f4f6" stroke="#e5e7eb" stroke-width="2"/>
      <text x="593" y="220" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" fill="#9ca3af">No Image</text>
      """
    end

    # Build title sections - positioned lower for better balance
    title_line_1 = if format_title(event.title, 0) != "" do
      y_pos = EventasaurusWeb.SocialCardView.title_line_y_position(0, calculate_font_size(event.title))
      ~s(<tspan x="32" y="#{y_pos}">#{format_title(event.title, 0)}</tspan>)
    else
      ""
    end

    title_line_2 = if format_title(event.title, 1) != "" do
      y_pos = EventasaurusWeb.SocialCardView.title_line_y_position(1, calculate_font_size(event.title))
      ~s(<tspan x="32" y="#{y_pos}">#{format_title(event.title, 1)}</tspan>)
    else
      ""
    end

    title_line_3 = if format_title(event.title, 2) != "" do
      y_pos = EventasaurusWeb.SocialCardView.title_line_y_position(2, calculate_font_size(event.title))
      ~s(<tspan x="32" y="#{y_pos}">#{format_title(event.title, 2)}</tspan>)
    else
      ""
    end

    # Create the complete SVG
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg width="800" height="419" viewBox="0 0 800 419" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <!-- Gradient background definition -->
        <linearGradient id="bgGradient" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" style="stop-color:#{format_color(theme.color1)};stop-opacity:1" />
          <stop offset="100%" style="stop-color:#{format_color(theme.color2)};stop-opacity:1" />
        </linearGradient>

        <!-- Clip path for rounded corners on event image -->
        <clipPath id="imageClip">
          <rect x="418" y="32" width="350" height="350" rx="24" ry="24"/>
        </clipPath>

        <!-- Clip path for RSVP bubble rounded corners -->
        <clipPath id="rsvpClip">
          <rect x="32" y="355" width="80" height="32" rx="16" ry="16"/>
        </clipPath>
      </defs>

      <!-- Background gradient -->
      <rect width="800" height="419" fill="url(#bgGradient)"/>

      <!-- Event image (positioned top-right with rounded corners) -->
      #{image_section}

      <!-- Logo (top-left) - Using actual Eventasaurus logo -->
      #{get_logo_svg_element()}

      <!-- Event title (left-aligned, multi-line) -->
      <text font-family="Arial, sans-serif" font-weight="bold"
            font-size="#{calculate_font_size(event.title)}" fill="white">
        #{title_line_1}
        #{title_line_2}
        #{title_line_3}
      </text>

      <!-- RSVP bubble (bottom-left) -->
      <rect x="32" y="355" width="80" height="32" rx="16" ry="16" fill="white" opacity="0.95"/>
      <text x="72" y="375" text-anchor="middle" font-family="Arial, sans-serif"
            font-size="14" font-weight="bold" fill="#374151">RSVP</text>
    </svg>
    """
  end

  # Private helper to extract colors from theme with error handling
  defp get_theme_colors(theme) do
    try do
      theme_config = EventasaurusApp.Themes.get_default_customizations(theme)
      colors = if is_map(theme_config) do
        Map.get(theme_config, "colors", %{})
      else
        %{}
      end

      %{
        primary: validate_color_or_default(Map.get(colors, "primary"), "#1a1a1a"),
        secondary: validate_color_or_default(Map.get(colors, "secondary"), "#333333"),
        accent: validate_color_or_default(Map.get(colors, "accent"), "#0066cc"),
        text: validate_color_or_default(Map.get(colors, "text"), "#ffffff")
      }
    rescue
      error ->
        Logger.error("Failed to get theme colors for #{inspect(theme)}: #{inspect(error)}")
        %{primary: "#1a1a1a", secondary: "#333333", accent: "#0066cc", text: "#ffffff"}
    end
  end

    defp validate_color_or_default(color, default) when is_binary(color) do
    if Regex.match?(~r/^#[0-9A-Fa-f]{3,8}$/i, color), do: color, else: default
  end
  defp validate_color_or_default(_, default), do: default
end
