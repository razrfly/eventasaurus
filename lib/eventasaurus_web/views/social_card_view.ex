defmodule EventasaurusWeb.SocialCardView do
  @moduledoc """
  View helpers for generating social card content.

  This module provides functions for safely processing event data
  and generating SVG content for social cards with proper sanitization.
  """

  alias Eventasaurus.SocialCards.Sanitizer
  alias Eventasaurus.SocialCards.HashGenerator

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
  Generates the social card URL for an event using the new hash-based format.
  """
  def social_card_url(event) do
    HashGenerator.generate_url_path(event)
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
  def render_background_gradient(theme_suffix, theme_colors) do
    id_suffix = safe_svg_id(theme_suffix)

    """
    <defs>
      <!-- Gradient background definition (unique per theme) -->
      <linearGradient id="bgGradient-#{id_suffix}" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" style="stop-color:#{format_color(theme_colors.primary)};stop-opacity:1" />
        <stop offset="100%" style="stop-color:#{format_color(theme_colors.secondary)};stop-opacity:1" />
      </linearGradient>
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
            """
            <!-- Clip path for rounded corners on image (unique per theme) -->
            <clipPath id="imageClip-#{id_suffix}">
              <rect x="418" y="32" width="350" height="350" rx="24" ry="24"/>
            </clipPath>

            <!-- Image (positioned top-right with rounded corners) -->
            <image href="#{data_url}"
                   x="418" y="32"
                   width="350" height="350"
                   clip-path="url(#imageClip-#{id_suffix})"
                   preserveAspectRatio="xMidYMid meet"/>
            """
        end
      else
        # External URL - download, optimize, and use base64 data URL
        case optimized_external_image_data_url(entity) do
          nil ->
            render_no_image_placeholder()

          data_url ->
            """
            <!-- Clip path for rounded corners on image (unique per theme) -->
            <clipPath id="imageClip-#{id_suffix}">
              <rect x="418" y="32" width="350" height="350" rx="24" ry="24"/>
            </clipPath>

            <!-- Image (positioned top-right with rounded corners) -->
            <image href="#{data_url}"
                   x="418" y="32"
                   width="350" height="350"
                   clip-path="url(#imageClip-#{id_suffix})"
                   preserveAspectRatio="xMidYMid meet"/>
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

    # Get poll type display name
    poll_type_text = poll_type_display_text(poll.poll_type)

    """
    <!-- Logo (top-left) -->
    #{get_logo_svg_element(theme_suffix, theme_colors)}

    <!-- Poll type indicator (right side, below logo) -->
    <text x="600" y="110" text-anchor="middle" font-family="Arial, sans-serif"
          font-size="16" font-weight="600" fill="white" opacity="0.9">
      #{poll_type_text}
    </text>

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

  # Helper to get display text for poll type
  defp poll_type_display_text("movie"), do: "🎬  Movie Poll"
  defp poll_type_display_text("places"), do: "📍  Places Poll"
  defp poll_type_display_text("venue"), do: "🏢  Venue Poll"
  defp poll_type_display_text("date_selection"), do: "📅  Date Poll"
  defp poll_type_display_text("time"), do: "⏰  Time Poll"
  defp poll_type_display_text("music_track"), do: "🎵  Music Poll"
  defp poll_type_display_text("custom"), do: "📊  Poll"
  defp poll_type_display_text("general"), do: "📊  Poll"
  defp poll_type_display_text(_), do: "📊  Poll"

  # Renders the poll options list for social cards.
  # Shows top 3 options or ballot box fallback for empty polls.
  defp render_poll_options_list(poll, _theme_suffix) do
    options = Map.get(poll, :poll_options, [])

    case length(options) do
      0 ->
        # Fallback to ballot box for empty polls
        render_ballot_box_fallback()

      count ->
        # Show top 3 options
        top_options = Enum.take(options, 3)
        remaining = max(count - 3, 0)

        option_texts =
          top_options
          |> Enum.with_index()
          |> Enum.map(fn {option, index} ->
            y_pos = 145 + index * 35
            truncated_title = truncate_option_title(option.title, 25)

            """
            <text x="450" y="#{y_pos}" font-family="Arial, sans-serif"
                  font-size="18" font-weight="600" fill="white" opacity="0.95">
              ✓ #{svg_escape(truncated_title)}
            </text>
            """
          end)
          |> Enum.join("\n")

        more_text =
          if remaining > 0 do
            plural = if remaining == 1, do: "", else: "s"

            """
            <text x="450" y="250" font-family="Arial, sans-serif"
                  font-size="16" font-weight="500" fill="white" opacity="0.8">
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
end
