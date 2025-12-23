defmodule EventasaurusWeb.SocialCardView do
  @moduledoc """
  View helpers for generating social card content.

  This module provides functions for safely processing event data
  and generating SVG content for social cards with proper sanitization.
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias Eventasaurus.SocialCards.UrlBuilder

  @doc """
  Helper function to ensure text fits within specified line limits.
  Truncates text if it exceeds the maximum length for proper display in social cards.
  """
  def truncate_title(title, max_length \\ 60) do
    if String.length(title) <= max_length do
      title
    else
      title
      |> String.slice(0, max_length - 3)
      |> Kernel.<>("...")
    end
  end

  @doc """
  Formats event title for multi-line display in SVG.
  Returns a specific line (0, 1, or 2) of the title.
  """
  def format_title(title, line_number) when is_binary(title) and line_number >= 0 do
    # Sanitize the title first
    safe_title = Sanitizer.sanitize_text(title)

    # Split title into words and group into lines
    words = String.split(safe_title, " ")
    # ~18 chars per line max
    lines = split_into_lines(words, 18)

    Enum.at(lines, line_number, "")
  end

  def format_title(_, _), do: ""

  @doc """
  Calculates appropriate font size based on title length.
  """
  def calculate_font_size(title) when is_binary(title) do
    # Sanitize first
    safe_title = Sanitizer.sanitize_text(title)
    length = String.length(safe_title)

    cond do
      length <= 20 -> "48"
      length <= 40 -> "36"
      length <= 60 -> "28"
      true -> "24"
    end
  end

  def calculate_font_size(_), do: "48"

  @doc """
  Formats color values for safe use in SVG.
  """
  def format_color(color) do
    Sanitizer.validate_color(color)
  end

  # Private helper to split words into lines with max character limit
  defp split_into_lines(words, max_chars_per_line) do
    words
    |> Enum.reduce({[], ""}, fn word, {lines, current_line} ->
      new_line = if current_line == "", do: word, else: current_line <> " " <> word

      if String.length(new_line) <= max_chars_per_line do
        {lines, new_line}
      else
        # Start new line with current word
        {lines ++ [current_line], word}
      end
    end)
    |> case do
      {lines, ""} -> lines
      {lines, last_line} -> lines ++ [last_line]
    end
    # Max 3 lines
    |> Enum.take(3)
  end

  @doc """
  Escapes text content for safe use in SVG templates.
  Prevents SVG injection by properly encoding special characters.
  """
  def svg_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def svg_escape(nil), do: ""

  @doc """
  Determines if an event has a valid image URL.
  Uses sanitizer to validate the URL.
  """
  def has_image?(%{cover_image_url: url}) do
    sanitized_url = Sanitizer.validate_image_url(url)
    sanitized_url != nil
  end

  def has_image?(_), do: false

  @doc """
  Gets a safe image URL for SVG rendering.
  Returns the validated URL if valid, otherwise returns nil.
  """
  def safe_image_url(%{cover_image_url: url}) do
    Sanitizer.validate_image_url(url)
  end

  def safe_image_url(_), do: nil

  @doc """
  Gets a local image path for SVG rendering by downloading external images or using static files.
  Returns a local file path if successful, otherwise returns nil.
  Uses sanitizer to validate the URL before downloading.
  """
  def local_image_path(%{cover_image_url: url}) do
    case Sanitizer.validate_image_url(url) do
      nil ->
        nil

      valid_url ->
        if String.starts_with?(valid_url, "/") do
          # Handle local static file path with security validation
          # SECURITY: Prevent directory traversal - construct safe path
          relative_path = String.trim_leading(valid_url, "/")
          static_dir = Path.join(["priv", "static"])
          static_path = Path.join(static_dir, relative_path)

          # SECURITY: Ensure the resolved path is still within the static directory
          canonical_static_dir = Path.expand(static_dir)
          canonical_static_path = Path.expand(static_path)

          if String.starts_with?(canonical_static_path, canonical_static_dir <> "/") and
               File.exists?(canonical_static_path) do
            canonical_static_path
          else
            nil
          end
        else
          # Handle external URL - download it
          case Eventasaurus.Services.SvgConverter.download_image_locally(valid_url) do
            {:ok, local_path} -> local_path
            {:error, _reason} -> nil
          end
        end
    end
  end

  def local_image_path(_), do: nil

  @doc """
  Gets a base64 data URL for local images to embed directly in SVG.
  This solves the rsvg-convert issue with file:// URLs by embedding the image data directly.
  Returns a data URL string if successful, otherwise returns nil.
  """
  def local_image_data_url(%{cover_image_url: url}) do
    case local_image_path(%{cover_image_url: url}) do
      nil ->
        nil

      local_path ->
        case File.read(local_path) do
          {:ok, image_data} ->
            # Determine MIME type from file extension
            mime_type =
              case Path.extname(local_path) |> String.downcase() do
                ".png" -> "image/png"
                ".jpg" -> "image/jpeg"
                ".jpeg" -> "image/jpeg"
                ".gif" -> "image/gif"
                ".webp" -> "image/webp"
                # Default fallback
                _ -> "image/png"
              end

            # Convert to base64 and create data URL
            base64_data = Base.encode64(image_data)
            data_url = "data:#{mime_type};base64,#{base64_data}"

            # Clean up temporary downloaded files (but not static files)
            if String.contains?(local_path, "social_card_img_") do
              Task.start(fn ->
                # Small delay to ensure data URL is used
                Process.sleep(1000)
                File.rm(local_path)
              end)
            end

            data_url

          {:error, _reason} ->
            nil
        end
    end
  end

  def local_image_data_url(_), do: nil

  @doc """
  Gets an HTTP-accessible URL for images to use in SVG rendering.
  For local static files, returns the web-accessible path.
  For external images, copies them to static directory temporarily.
  This works better with rsvg-convert than base64 data URLs.
  Returns an HTTP URL string if successful, otherwise returns nil.
  """
  def http_image_url(%{cover_image_url: url}) do
    case Sanitizer.validate_image_url(url) do
      nil ->
        nil

      valid_url ->
        if String.starts_with?(valid_url, "/") do
          # For local static files, return the web-accessible URL
          valid_url
        else
          # For external images, download and serve them temporarily
          case Eventasaurus.Services.SvgConverter.download_image_locally(valid_url) do
            {:ok, local_path} ->
              # Copy to static directory with a unique name for HTTP access
              filename = "temp_social_#{System.unique_integer([:positive])}.jpg"
              static_path = Path.join(["priv", "static", "images", "temp", filename])

              # Ensure temp directory exists
              Path.dirname(static_path) |> File.mkdir_p!()

              case File.cp(local_path, static_path) do
                :ok ->
                  # Clean up the original temp file
                  File.rm(local_path)

                  # Schedule cleanup of the static temp file
                  Task.start(fn ->
                    # 30 seconds delay
                    Process.sleep(30_000)
                    File.rm(static_path)
                  end)

                  # Return HTTP URL
                  "/images/temp/#{filename}"

                {:error, _reason} ->
                  # Clean up on failure
                  File.rm(local_path)
                  nil
              end

            {:error, _reason} ->
              nil
          end
        end
    end
  end

  def http_image_url(_), do: nil

  @doc """
  Gets a local file path for images that rsvg-convert can access.
  For local static files, returns the existing path.
  For external images, downloads them to a permanent location.
  Returns an absolute file path string if successful, otherwise returns nil.
  """
  def local_file_path_for_svg(%{cover_image_url: url}) do
    case Sanitizer.validate_image_url(url) do
      nil ->
        nil

      valid_url ->
        if String.starts_with?(valid_url, "/") do
          # For local static files, return the absolute path
          relative_path = String.trim_leading(valid_url, "/")
          static_dir = Path.join(["priv", "static"])
          static_path = Path.join(static_dir, relative_path)

          # SECURITY: Ensure the resolved path is still within the static directory
          canonical_static_dir = Path.expand(static_dir)
          canonical_static_path = Path.expand(static_path)

          if String.starts_with?(canonical_static_path, canonical_static_dir <> "/") and
               File.exists?(canonical_static_path) do
            canonical_static_path
          else
            nil
          end
        else
          # For external images, download and save them to static directory permanently
          case Eventasaurus.Services.SvgConverter.download_image_locally(valid_url) do
            {:ok, local_path} ->
              # Copy to static directory with a unique name
              filename = "downloaded_#{System.unique_integer([:positive])}.jpg"
              static_path = Path.join(["priv", "static", "images", "temp", filename])

              # Ensure temp directory exists
              Path.dirname(static_path) |> File.mkdir_p!()

              case File.cp(local_path, static_path) do
                :ok ->
                  # Clean up the original temp file
                  File.rm(local_path)

                  # Return absolute path for rsvg-convert
                  Path.expand(static_path)

                {:error, _reason} ->
                  # Clean up on failure
                  File.rm(local_path)
                  nil
              end

            {:error, _reason} ->
              nil
          end
        end
    end
  end

  def local_file_path_for_svg(_), do: nil

  @doc """
  Gets an optimized base64 data URL for external images.
  Downloads and resizes external images to reduce data URL size for better rsvg-convert compatibility.
  Returns a data URL string if successful, otherwise returns nil.
  """
  def optimized_external_image_data_url(%{cover_image_url: url}) do
    case Sanitizer.validate_image_url(url) do
      nil ->
        nil

      valid_url ->
        unless String.starts_with?(valid_url, "/") do
          # For external images only
          case Eventasaurus.Services.SvgConverter.download_image_locally(valid_url) do
            {:ok, local_path} ->
              # Try to resize the image to reduce file size
              resized_path = resize_image_for_social_card(local_path)

              case File.read(resized_path || local_path) do
                {:ok, image_data} ->
                  # Determine MIME type
                  mime_type =
                    case Path.extname(resized_path || local_path) |> String.downcase() do
                      ".png" -> "image/png"
                      ".jpg" -> "image/jpeg"
                      ".jpeg" -> "image/jpeg"
                      ".gif" -> "image/gif"
                      ".webp" -> "image/webp"
                      # Default for external images
                      _ -> "image/jpeg"
                    end

                  # Convert to base64 and create data URL
                  base64_data = Base.encode64(image_data)
                  data_url = "data:#{mime_type};base64,#{base64_data}"

                  # Clean up temporary files
                  File.rm(local_path)
                  if resized_path && resized_path != local_path, do: File.rm(resized_path)

                  data_url

                {:error, _reason} ->
                  File.rm(local_path)
                  if resized_path && resized_path != local_path, do: File.rm(resized_path)
                  nil
              end

            {:error, _reason} ->
              nil
          end
        else
          # Not an external image
          nil
        end
    end
  end

  def optimized_external_image_data_url(_), do: nil

  # Resizes an image to optimize it for social card use.
  # Returns the path to the resized image, or nil if resizing fails.
  defp resize_image_for_social_card(image_path) do
    try do
      # Create a resized version using ImageMagick if available
      resized_path = image_path <> "_resized"

      # Try to resize to 400x400 max with quality 85 to reduce file size
      {_output, exit_code} =
        System.cmd(
          "convert",
          [
            image_path,
            # Only resize if larger than 400x400
            "-resize",
            "400x400>",
            # Reduce quality slightly
            "-quality",
            "85",
            resized_path
          ],
          stderr_to_stdout: true
        )

      if exit_code == 0 && File.exists?(resized_path) do
        resized_path
      else
        # Fallback to original if resize fails
        nil
      end
    rescue
      # ImageMagick not available or other error
      _ -> nil
    end
  end

  @doc """
  Gets sanitized event title for safe SVG rendering.
  """
  def safe_title(event) do
    title = Map.get(event, :title, "")
    Sanitizer.sanitize_text(title)
  end

  @doc """
  Gets sanitized event description for safe SVG rendering.
  """
  def safe_description(event) do
    description = Map.get(event, :description, "")
    Sanitizer.sanitize_text(description)
  end

  @doc """
  Sanitizes complete event data for safe use in social card generation.
  """
  def sanitize_event(event) do
    Sanitizer.sanitize_event_data(event)
  end

  @doc """
  Generates the social card URL path for an event using the unified UrlBuilder.
  Returns just the path component; use with UrlHelper.build_url/1 for full URL.
  """
  def social_card_url(event) do
    UrlBuilder.build_path(:event, event)
  end

  # Logo constants for consistent positioning
  @logo_x 32
  @logo_y 32
  @logo_width 280

  # Title positioning constants to avoid duplication
  @title_base_y 200
  @title_line_spacing 8

  @doc """
  Calculates the Y position for a title line based on line number and font size.
  """
  def title_line_y_position(line_number, font_size) when line_number >= 0 do
    font_size_int = if is_binary(font_size), do: String.to_integer(font_size), else: font_size
    @title_base_y + line_number * (font_size_int + @title_line_spacing)
  end

  # Pre-load logo SVGs at compile time for better performance
  @logo_path_dark Path.join([
                    to_string(:code.priv_dir(:eventasaurus)),
                    "static",
                    "images",
                    "logos",
                    "general-op.svg"
                  ])
  @logo_path_light Path.join([
                     to_string(:code.priv_dir(:eventasaurus)),
                     "static",
                     "images",
                     "logos",
                     "general-op-white.svg"
                   ])
  @logo_svg_dark (case File.read(@logo_path_dark) do
                    {:ok, svg_content} -> svg_content
                    {:error, reason} -> raise "Failed to load dark logo SVG: #{inspect(reason)}"
                  end)
  @logo_svg_light (case File.read(@logo_path_light) do
                     {:ok, svg_content} -> svg_content
                     {:error, reason} -> raise "Failed to load light logo SVG: #{inspect(reason)}"
                   end)

  @doc """
  Gets the logo as an SVG element.
  Embeds the logo SVG content directly with proper positioning and scaling.
  Automatically selects white logo for dark backgrounds and black logo for light backgrounds.
  """
  def get_logo_svg_element(_theme_suffix, theme_colors) do
    # Select the appropriate logo based on background color
    svg_content =
      if is_dark_color?(theme_colors.primary) do
        @logo_svg_light
      else
        @logo_svg_dark
      end

    # Extract just the inner SVG content (remove <svg> wrapper)
    # We'll position it using a <g> transform
    inner_svg =
      svg_content
      |> String.replace(~r/^<\?xml[^>]+>\s*/i, "")
      |> String.replace(~r/<svg[^>]*>/i, "")
      |> String.replace(~r/<\/svg>\s*$/i, "")

    # Scale uniformly to fit width while maintaining aspect ratio (original is 715x166)
    # Target width: 280
    # This maintains the proper aspect ratio: 715/166 ≈ 4.3:1
    scale = @logo_width / 715

    """
    <g transform="translate(#{@logo_x}, #{@logo_y}) scale(#{scale})">
      #{inner_svg}
    </g>
    """
  end

  # Helper to determine if a color is dark (needs logo inversion)
  defp is_dark_color?(color) when is_binary(color) do
    # Extract RGB values from hex color
    case parse_hex_color(color) do
      {r, g, b} ->
        # Calculate relative luminance using the formula from WCAG 2.0
        # https://www.w3.org/TR/WCAG20/#relativeluminancedef
        luminance = 0.299 * r + 0.587 * g + 0.114 * b
        # Consider dark if luminance is below 128 (midpoint of 0-255)
        luminance < 128

      nil ->
        false
    end
  end

  defp is_dark_color?(_), do: false

  # Parse hex color to RGB tuple
  defp parse_hex_color("#" <> hex) do
    case String.length(hex) do
      6 ->
        # Full hex format #RRGGBB
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 2), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 2, 2), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 4, 2), 16) do
          {r, g, b}
        else
          _ -> nil
        end

      3 ->
        # Short hex format #RGB
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 1), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 1, 1), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 2, 1), 16) do
          # Convert from 0-15 to 0-255
          {r * 17, g * 17, b * 17}
        else
          _ -> nil
        end

      8 ->
        # Hex with alpha #RRGGBBAA (ignore alpha for luminance)
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 2), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 2, 2), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 4, 2), 16) do
          {r, g, b}
        else
          _ -> nil
        end

      4 ->
        # Short hex with alpha #RGBA (ignore alpha for luminance)
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 1), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 1, 1), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 2, 1), 16) do
          # Convert from 0-15 to 0-255
          {r * 17, g * 17, b * 17}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_hex_color(_), do: nil

  # ============================================================================
  # Phase 1: Reusable Social Card Components
  # ============================================================================

  @doc """
  Renders the background gradient SVG definition and rectangle.
  Returns SVG markup with gradient definition and filled rectangle.

  ## Parameters
    - theme_suffix: Unique theme identifier for IDs (e.g., "minimal", "cosmic")
    - theme_colors: Map with :primary and :secondary color hex values

  ## Returns
    SVG markup string with gradient definition and background rectangle
  """
  def render_background_gradient(theme_suffix, theme_colors, opts \\ []) do
    id_suffix = safe_svg_id(theme_suffix)
    include_image_clip = Keyword.get(opts, :include_image_clip, true)

    # Include image clip path in defs for rsvg-convert compatibility
    image_clip_def =
      if include_image_clip do
        """
        <!-- Clip path for rounded corners on image (unique per theme) -->
            <clipPath id="imageClip-#{id_suffix}">
              <rect x="418" y="32" width="350" height="350" rx="24" ry="24"/>
            </clipPath>
        """
      else
        ""
      end

    """
    <defs>
      <!-- Gradient background definition (unique per theme) -->
      <linearGradient id="bgGradient-#{id_suffix}" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" style="stop-color:#{format_color(theme_colors.primary)};stop-opacity:1" />
        <stop offset="100%" style="stop-color:#{format_color(theme_colors.secondary)};stop-opacity:1" />
      </linearGradient>
      #{image_clip_def}
    </defs>

    <!-- Background gradient -->
    <rect width="800" height="419" fill="url(#bgGradient-#{id_suffix})"/>
    """
  end

  @doc """
  Renders the image section for a social card with proper fallback.
  Handles both local and external images with appropriate data URL encoding.

  ## Parameters
    - entity: Map with :cover_image_url field
    - theme_suffix: Unique theme identifier for clip path ID

  ## Returns
    SVG markup string with image or "No Image" placeholder
  """
  def render_image_section(entity, theme_suffix, _opts \\ []) do
    id_suffix = safe_svg_id(theme_suffix)

    if has_image?(entity) do
      # Check if this is a local static file or external URL
      if String.starts_with?(entity.cover_image_url, "/") do
        # Local static file - use base64 data URL (this works)
        case local_image_data_url(entity) do
          nil ->
            render_no_image_placeholder()

          data_url ->
            # Note: clipPath is now defined in <defs> via render_background_gradient
            # for rsvg-convert compatibility
            """
            <!-- Image (positioned top-right with rounded corners) -->
            <image href="#{data_url}"
                   x="418" y="32"
                   width="350" height="350"
                   clip-path="url(#imageClip-#{id_suffix})"
                   preserveAspectRatio="xMidYMid slice"/>
            """
        end
      else
        # External URL - download, optimize, and use base64 data URL
        case optimized_external_image_data_url(entity) do
          nil ->
            render_no_image_placeholder()

          data_url ->
            # Note: clipPath is now defined in <defs> via render_background_gradient
            # for rsvg-convert compatibility
            """
            <!-- Image (positioned top-right with rounded corners) -->
            <image href="#{data_url}"
                   x="418" y="32"
                   width="350" height="350"
                   clip-path="url(#imageClip-#{id_suffix})"
                   preserveAspectRatio="xMidYMid slice"/>
            """
        end
      end
    else
      render_no_image_placeholder()
    end
  end

  # Helper to render "No Image" placeholder
  defp render_no_image_placeholder do
    """
    <rect x="418" y="32" width="350" height="350" rx="24" ry="24" fill="#f3f4f6" stroke="#e5e7eb" stroke-width="2"/>
    <text x="593" y="220" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" fill="#9ca3af">No Image</text>
    """
  end

  @doc """
  Renders a call-to-action bubble (e.g., "RSVP", "VOTE").
  Positioned at bottom-left with rounded corners.

  ## Parameters
    - cta_text: Text to display in the bubble (e.g., "RSVP", "VOTE")
    - theme_suffix: Unique theme identifier for clip path ID

  ## Returns
    SVG markup string with CTA bubble
  """
  def render_cta_bubble(cta_text, theme_suffix) do
    id_suffix = safe_svg_id(theme_suffix)

    """
    <!-- Clip path for CTA bubble rounded corners (unique per theme) -->
    <clipPath id="ctaClip-#{id_suffix}">
      <rect x="32" y="355" width="80" height="32" rx="16" ry="16"/>
    </clipPath>

    <!-- CTA bubble (bottom-left) -->
    <rect x="32" y="355" width="80" height="32" rx="16" ry="16" fill="white" opacity="0.95"/>
    <text x="72" y="375" text-anchor="middle" font-family="Arial, sans-serif"
          font-size="14" font-weight="bold" fill="#374151">#{cta_text}</text>
    """
  end

  @doc """
  Renders the base SVG structure for a social card with a content block.
  This is the foundational function that all card types can use.

  ## Parameters
    - theme_suffix: Unique theme identifier for IDs
    - theme_colors: Map with :primary and :secondary colors
    - content_block: SVG markup for card-specific content (title, poll options, etc.)

  ## Returns
    Complete SVG markup as a string
  """
  def render_social_card_base(theme_suffix, theme_colors, content_block) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg width="800" height="419" viewBox="0 0 800 419" xmlns="http://www.w3.org/2000/svg">
      #{render_background_gradient(theme_suffix, theme_colors)}
      #{content_block}
    </svg>
    """
  end

  # ============================================================================
  # Event-Specific Social Card Rendering
  # ============================================================================

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
      case get_theme_colors(theme_name) do
        %{primary: primary, secondary: secondary} = colors
        when is_binary(primary) and is_binary(secondary) ->
          colors

        _ ->
          %{primary: "#1a1a1a", secondary: "#333333"}
      end

    # Build event-specific content
    event_content = render_event_content(sanitized_event, theme_suffix, theme_colors)

    # Use the base function to create complete SVG
    render_social_card_base(theme_suffix, theme_colors, event_content)
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
      if format_title(event.title, 0) != "" do
        y_pos = title_line_y_position(0, calculate_font_size(event.title))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(event.title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if format_title(event.title, 1) != "" do
        y_pos = title_line_y_position(1, calculate_font_size(event.title))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(event.title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if format_title(event.title, 2) != "" do
        y_pos = title_line_y_position(2, calculate_font_size(event.title))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(event.title, 2)}</tspan>)
      else
        ""
      end

    """
    #{render_image_section(event, theme_suffix)}

    <!-- Logo (top-left) -->
    #{get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Event title (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{calculate_font_size(event.title)}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    #{render_cta_bubble("RSVP", theme_suffix)}
    """
  end

  # ============================================================================
  # Poll-Specific Social Card Rendering
  # ============================================================================

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
      case get_theme_colors(theme_name) do
        %{primary: primary, secondary: secondary} = colors
        when is_binary(primary) and is_binary(secondary) ->
          colors

        _ ->
          %{primary: "#1a1a1a", secondary: "#333333"}
      end

    # Build poll-specific content
    poll_content = render_poll_content(sanitized_poll, event, theme_suffix, theme_colors)

    # Use the base function to create complete SVG
    render_social_card_base(theme_suffix, theme_colors, poll_content)
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
      if format_title(poll.title, 0) != "" do
        y_pos = title_line_y_position(0, calculate_font_size(poll.title))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(poll.title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if format_title(poll.title, 1) != "" do
        y_pos = title_line_y_position(1, calculate_font_size(poll.title))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(poll.title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if format_title(poll.title, 2) != "" do
        y_pos = title_line_y_position(2, calculate_font_size(poll.title))
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(poll.title, 2)}</tspan>)
      else
        ""
      end

    """
    <!-- Logo (top-left) -->
    #{get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Poll type indicator (right side, below logo) -->
    #{render_poll_type_badge(poll.poll_type)}

    <!-- Poll title (left-aligned, multi-line) -->
    <text font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{calculate_font_size(poll.title)}" fill="white">
      #{title_line_1}
      #{title_line_2}
      #{title_line_3}
    </text>

    <!-- Poll options list or ballot box fallback (right side) -->
    #{render_poll_options_list(poll, theme_suffix)}

    #{render_cta_bubble("VOTE", theme_suffix)}
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

  # ============================================================================
  # Poll Type Badge Icons - Twemoji Integration
  # ============================================================================
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
            truncated_title = truncate_option_title(option.title, 25)

            """
            <text x="450" y="#{y_pos}" font-family="Arial, sans-serif"
                  font-size="28" font-weight="600" fill="white" opacity="0.95">
              ✓ #{svg_escape(truncated_title)}
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

  # Private helper to extract colors from theme with error handling
  defp get_theme_colors(theme) do
    try do
      theme_config = EventasaurusApp.Themes.get_default_customizations(theme)

      colors =
        if is_map(theme_config) do
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
        require Logger
        Logger.error("Failed to get theme colors for #{inspect(theme)}: #{inspect(error)}")
        %{primary: "#1a1a1a", secondary: "#333333", accent: "#0066cc", text: "#ffffff"}
    end
  end

  defp validate_color_or_default(color, default) when is_binary(color) do
    if Regex.match?(~r/^#[0-9A-Fa-f]{3,8}$/i, color), do: color, else: default
  end

  defp validate_color_or_default(_, default), do: default

  # Sanitizes theme_suffix for safe use in SVG IDs.
  # Removes or replaces characters that are not valid in XML IDs.
  # SVG IDs must start with a letter or underscore and can only contain letters, digits, hyphens, underscores, and periods.
  defp safe_svg_id(theme_suffix) when is_binary(theme_suffix) do
    theme_suffix
    |> String.replace(~r/[^a-zA-Z0-9\-_.]/, "_")
    |> String.replace(~r/^[^a-zA-Z_]/, "_")
  end

  defp safe_svg_id(theme_suffix) when is_atom(theme_suffix) do
    theme_suffix
    |> to_string()
    |> safe_svg_id()
  end

  defp safe_svg_id(_), do: "_default"

  # ============================================================================
  # City-Specific Social Card Rendering
  # ============================================================================

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

    # Get theme colors with city-friendly palette
    theme_colors = %{
      primary: "#1e40af",
      # Deep blue
      secondary: "#3b82f6"
      # Bright blue
    }

    # Build city-specific content
    city_content = render_city_content(city, stats, theme_suffix, theme_colors)

    # Use the base function to create complete SVG
    render_social_card_base(theme_suffix, theme_colors, city_content)
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
    #{get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- City name (large, centered) -->
    <text x="400" y="180" text-anchor="middle"
          font-family="Arial, sans-serif" font-weight="bold"
          font-size="#{city_font_size}" fill="white">
      #{svg_escape(safe_city_name)}
    </text>

    <!-- Stats line (centered below city name) -->
    <text x="400" y="240" text-anchor="middle"
          font-family="Arial, sans-serif" font-weight="600"
          font-size="32" fill="white" opacity="0.95">
      #{svg_escape(stats_text)}
    </text>

    <!-- Tagline (centered below stats) -->
    <text x="400" y="290" text-anchor="middle"
          font-family="Arial, sans-serif" font-weight="400"
          font-size="24" fill="white" opacity="0.85">
      Your event discovery platform
    </text>

    #{render_cta_bubble("EXPLORE", theme_suffix)}
    """
  end

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

  @doc """
  Sanitizes city data for safe use in social card generation.
  """
  def sanitize_city(city) do
    %{
      name: Sanitizer.sanitize_text(Map.get(city, :name, "")),
      slug: Map.get(city, :slug, "")
    }
  end

  # ============================================================================
  # Activity-Specific Social Card Rendering (Public Events)
  # ============================================================================

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

    # Wombie brand colors - teal/cyan gradient
    theme_colors = %{
      primary: "#0d9488",
      # Teal 600
      secondary: "#14b8a6"
      # Teal 500
    }

    # Build activity-specific content
    activity_content = render_activity_content(activity, theme_suffix, theme_colors)

    # Use the base function to create complete SVG
    render_social_card_base(theme_suffix, theme_colors, activity_content)
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
    title_font_size = calculate_font_size(safe_title)

    # Build title sections
    title_line_1 =
      if format_title(safe_title, 0) != "" do
        y_pos = activity_title_y_position(0, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(safe_title, 0)}</tspan>)
      else
        ""
      end

    title_line_2 =
      if format_title(safe_title, 1) != "" do
        y_pos = activity_title_y_position(1, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(safe_title, 1)}</tspan>)
      else
        ""
      end

    title_line_3 =
      if format_title(safe_title, 2) != "" do
        y_pos = activity_title_y_position(2, title_font_size)
        ~s(<tspan x="32" y="#{y_pos}">#{format_title(safe_title, 2)}</tspan>)
      else
        ""
      end

    """
    #{render_image_section(activity, theme_suffix)}

    <!-- Logo (top-left) -->
    #{get_logo_svg_element(theme_suffix, theme_colors)}

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

    #{render_cta_bubble("VIEW", theme_suffix)}
    """
  end

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
      #{svg_escape(date_time_text)}
    </text>
    """
  end

  # Render location section for activity card
  defp render_activity_location(""), do: ""

  defp render_activity_location(location_text) do
    # Truncate if too long
    truncated = truncate_title(location_text, 45)

    """
    <text x="32" y="340" font-family="Arial, sans-serif" font-weight="400"
          font-size="18" fill="white" opacity="0.85">
      #{svg_escape(truncated)}
    </text>
    """
  end

  # Calculate Y position for activity title lines (positioned higher to make room for date/location)
  defp activity_title_y_position(line_number, font_size) when is_binary(font_size) do
    activity_title_y_position(line_number, String.to_integer(font_size))
  end

  defp activity_title_y_position(line_number, font_size) when is_integer(font_size) do
    # Start at y=180 (lower than event cards to leave room for logo)
    # Then add spacing based on font size for each line
    base_y = 180
    line_spacing = font_size + 8
    base_y + line_number * line_spacing
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
end
