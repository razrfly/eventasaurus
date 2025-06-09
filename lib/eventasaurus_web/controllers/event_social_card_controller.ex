defmodule EventasaurusWeb.EventSocialCardController do
  use EventasaurusWeb, :controller

  require Logger
  alias Eventasaurus.Services.SvgConverter
  alias EventasaurusApp.Events

  @doc """
  Generates and serves a social card PNG image for the specified event.

  URL format: /events/:id/social_card.png
  """
  @spec generate_card(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def generate_card(conn, %{"id" => event_id}) do
    case verify_system_dependencies() do
      :ok ->
        # Fetch real event data from database
        case Events.get_event(event_id) do
          nil ->
            Logger.warning("Event #{event_id} not found")
            conn
            |> put_status(:not_found)
            |> put_resp_content_type("application/json")
            |> send_resp(404, Jason.encode!(%{error: "Event not found"}))

          event ->
            Logger.info("Generating social card for event #{event_id}: #{event.title}")

            # Render SVG template with real event data
            svg_content = render_svg_template(event)

            Logger.debug("Generated SVG content length: #{String.length(svg_content)} characters")

            # Convert SVG to PNG using our converter service
            case SvgConverter.svg_to_png(svg_content, event_id, event) do
              {:ok, png_path} ->
                Logger.info("Successfully converted social card for event #{event_id}")

                # Schedule cleanup of temporary file after serving
                SvgConverter.cleanup_temp_file(png_path)

                # Serve the PNG file with appropriate headers
                conn
                |> put_resp_content_type("image/png")
                |> put_resp_header("cache-control", "public, max-age=86400")
                |> put_resp_header("etag", "\"#{Path.basename(png_path, ".png")}\"")
                |> send_file(200, png_path)

              {:error, reason} ->
                Logger.error("Failed to generate social card for event #{event_id}: #{inspect(reason)}")

                # Return error response with fallback
                conn
                |> put_status(:internal_server_error)
                |> json(%{
                  error: "Failed to generate social card",
                  reason: reason,
                  event_id: event_id
                })
            end
        end

      {:error, reason} ->
        Logger.error("Social card generation failed - system dependency missing: #{reason}")

        conn
        |> put_status(:internal_server_error)
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "Social card generation unavailable")
    end
  end

  @doc """
  Verifies that required system dependencies are available.
  Returns :ok if all dependencies are present, {:error, reason} otherwise.
  """
  @spec verify_system_dependencies() :: :ok | {:error, String.t()}
  def verify_system_dependencies do
    case System.find_executable("rsvg-convert") do
      nil ->
        {:error, "rsvg-convert command not found"}

      _path ->
        :ok
    end
  end

  # Private helper to render SVG template with proper context
  defp render_svg_template(event) do
    # Create theme data
    theme = %{color1: "#1a1a1a", color2: "#333333"}

    # Import view helper functions for use in template
    import EventasaurusWeb.SocialCardView

    # Build image section - download external images locally for rsvg-convert compatibility
    image_section = if has_image?(event) do
      case local_image_path(event) do
        nil ->
          # Fallback to "No Image" if download fails
          """
          <rect x="418" y="32" width="350" height="350" rx="24" ry="24" fill="#f3f4f6" stroke="#e5e7eb" stroke-width="2"/>
          <text x="593" y="220" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" fill="#9ca3af">No Image</text>
          """
        local_path ->
          """
          <image href="file://#{local_path}"
                 x="418" y="32"
                 width="350" height="350"
                 clip-path="url(#imageClip)"
                 preserveAspectRatio="xMidYMid slice"/>
          """
      end
    else
      """
      <rect x="418" y="32" width="350" height="350" rx="24" ry="24" fill="#f3f4f6" stroke="#e5e7eb" stroke-width="2"/>
      <text x="593" y="220" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" fill="#9ca3af">No Image</text>
      """
    end

    # Build title sections
    title_line_1 = if format_title(event.title, 0) != "" do
      ~s(<tspan x="32" y="140">#{format_title(event.title, 0)}</tspan>)
    else
      ""
    end

    title_line_2 = if format_title(event.title, 1) != "" do
      font_size = String.to_integer(calculate_font_size(event.title))
      y_pos = 140 + font_size + 8
      ~s(<tspan x="32" y="#{y_pos}">#{format_title(event.title, 1)}</tspan>)
    else
      ""
    end

    title_line_3 = if format_title(event.title, 2) != "" do
      font_size = String.to_integer(calculate_font_size(event.title))
      y_pos = 140 + (font_size + 8) * 2
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

      <!-- Logo (top-left) - Using emoji placeholder for now -->
      <rect x="32" y="32" width="64" height="64" rx="8" ry="8" fill="#10b981"/>
      <text x="64" y="72" text-anchor="middle" font-family="Arial, sans-serif" font-size="36" fill="white">🦖</text>

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
end
