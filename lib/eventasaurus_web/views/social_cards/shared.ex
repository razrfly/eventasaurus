defmodule EventasaurusWeb.SocialCards.Shared do
  @moduledoc """
  Shared utilities for social card SVG generation.

  This module contains all the helper functions used across different card types:
  - Text formatting (truncate, format_title, calculate_font_size)
  - SVG utilities (svg_escape, format_color, safe_svg_id)
  - Image handling (has_image?, safe_image_url, data URL functions)
  - Base rendering (render_background_gradient, render_image_section, render_cta_bubble)
  - Theme utilities (get_theme_colors, get_logo_svg_element)
  """

  alias Eventasaurus.SocialCards.Sanitizer

  # Logo positioning constants
  @logo_x 32
  @logo_y 32
  @logo_width 280

  # Title positioning constants
  @title_base_y 200
  @title_line_spacing 8

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

  # ===========================================================================
  # Text Formatting
  # ===========================================================================

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
    safe_title = Sanitizer.sanitize_text(title)
    words = String.split(safe_title, " ")
    lines = split_into_lines(words, 18)
    Enum.at(lines, line_number, "")
  end

  def format_title(_, _), do: ""

  @doc """
  Calculates appropriate font size based on title length.
  """
  def calculate_font_size(title) when is_binary(title) do
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
  Calculates the Y position for a title line based on line number and font size.
  """
  def title_line_y_position(line_number, font_size) when line_number >= 0 do
    font_size_int = if is_binary(font_size), do: String.to_integer(font_size), else: font_size
    @title_base_y + line_number * (font_size_int + @title_line_spacing)
  end

  # Private helper to split words into lines with max character limit
  defp split_into_lines(words, max_chars_per_line) do
    words
    |> Enum.reduce({[], ""}, fn word, {lines, current_line} ->
      new_line = if current_line == "", do: word, else: current_line <> " " <> word

      if String.length(new_line) <= max_chars_per_line do
        {lines, new_line}
      else
        {lines ++ [current_line], word}
      end
    end)
    |> case do
      {lines, ""} -> lines
      {lines, last_line} -> lines ++ [last_line]
    end
    |> Enum.take(3)
  end

  # ===========================================================================
  # SVG Utilities
  # ===========================================================================

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
  Formats color values for safe use in SVG.
  """
  def format_color(color) do
    Sanitizer.validate_color(color)
  end

  @doc """
  Sanitizes theme_suffix for safe use in SVG IDs.
  """
  def safe_svg_id(theme_suffix) when is_binary(theme_suffix) do
    theme_suffix
    |> String.replace(~r/[^a-zA-Z0-9\-_.]/, "_")
    |> String.replace(~r/^[^a-zA-Z_]/, "_")
  end

  def safe_svg_id(theme_suffix) when is_atom(theme_suffix) do
    theme_suffix
    |> to_string()
    |> safe_svg_id()
  end

  def safe_svg_id(_), do: "_default"

  # ===========================================================================
  # Image Handling
  # ===========================================================================

  @doc """
  Determines if an entity has a valid image URL.
  """
  def has_image?(%{cover_image_url: url}) do
    sanitized_url = Sanitizer.validate_image_url(url)
    sanitized_url != nil
  end

  def has_image?(_), do: false

  @doc """
  Gets a safe image URL for SVG rendering.
  """
  def safe_image_url(%{cover_image_url: url}) do
    Sanitizer.validate_image_url(url)
  end

  def safe_image_url(_), do: nil

  @doc """
  Gets a local image path for SVG rendering by downloading external images or using static files.
  """
  def local_image_path(%{cover_image_url: url}) do
    case Sanitizer.validate_image_url(url) do
      nil ->
        nil

      valid_url ->
        if String.starts_with?(valid_url, "/") do
          relative_path = String.trim_leading(valid_url, "/")
          static_dir = Path.join(["priv", "static"])
          static_path = Path.join(static_dir, relative_path)

          canonical_static_dir = Path.expand(static_dir)
          canonical_static_path = Path.expand(static_path)

          if String.starts_with?(canonical_static_path, canonical_static_dir <> "/") and
               File.exists?(canonical_static_path) do
            canonical_static_path
          else
            nil
          end
        else
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
  """
  def local_image_data_url(%{cover_image_url: url}) do
    case local_image_path(%{cover_image_url: url}) do
      nil ->
        nil

      local_path ->
        case File.read(local_path) do
          {:ok, image_data} ->
            mime_type =
              case Path.extname(local_path) |> String.downcase() do
                ".png" -> "image/png"
                ".jpg" -> "image/jpeg"
                ".jpeg" -> "image/jpeg"
                ".gif" -> "image/gif"
                ".webp" -> "image/webp"
                _ -> "image/png"
              end

            base64_data = Base.encode64(image_data)
            data_url = "data:#{mime_type};base64,#{base64_data}"

            if String.contains?(local_path, "social_card_img_") do
              Task.start(fn ->
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
  Gets an optimized base64 data URL for external images.
  """
  def optimized_external_image_data_url(%{cover_image_url: url}) do
    case Sanitizer.validate_image_url(url) do
      nil ->
        nil

      valid_url ->
        unless String.starts_with?(valid_url, "/") do
          case Eventasaurus.Services.SvgConverter.download_image_locally(valid_url) do
            {:ok, local_path} ->
              resized_path = resize_image_for_social_card(local_path)

              case File.read(resized_path || local_path) do
                {:ok, image_data} ->
                  mime_type =
                    case Path.extname(resized_path || local_path) |> String.downcase() do
                      ".png" -> "image/png"
                      ".jpg" -> "image/jpeg"
                      ".jpeg" -> "image/jpeg"
                      ".gif" -> "image/gif"
                      ".webp" -> "image/webp"
                      _ -> "image/jpeg"
                    end

                  base64_data = Base.encode64(image_data)
                  data_url = "data:#{mime_type};base64,#{base64_data}"

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
          nil
        end
    end
  end

  def optimized_external_image_data_url(_), do: nil

  defp resize_image_for_social_card(image_path) do
    try do
      resized_path = image_path <> "_resized"

      {_output, exit_code} =
        System.cmd(
          "convert",
          [image_path, "-resize", "400x400>", "-quality", "85", resized_path],
          stderr_to_stdout: true
        )

      if exit_code == 0 && File.exists?(resized_path) do
        resized_path
      else
        nil
      end
    rescue
      _ -> nil
    end
  end

  # ===========================================================================
  # Theme Utilities
  # ===========================================================================

  @doc """
  Gets theme colors from theme name with error handling.
  """
  def get_theme_colors(theme) do
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

  @doc """
  Gets the logo as an SVG element.
  Automatically selects white logo for dark backgrounds and black logo for light backgrounds.
  """
  def get_logo_svg_element(_theme_suffix, theme_colors) do
    svg_content =
      if is_dark_color?(theme_colors.primary) do
        @logo_svg_light
      else
        @logo_svg_dark
      end

    inner_svg =
      svg_content
      |> String.replace(~r/^<\?xml[^>]+>\s*/i, "")
      |> String.replace(~r/<svg[^>]*>/i, "")
      |> String.replace(~r/<\/svg>\s*$/i, "")

    scale = @logo_width / 715

    """
    <g transform="translate(#{@logo_x}, #{@logo_y}) scale(#{scale})">
      #{inner_svg}
    </g>
    """
  end

  defp is_dark_color?(color) when is_binary(color) do
    case parse_hex_color(color) do
      {r, g, b} ->
        luminance = 0.299 * r + 0.587 * g + 0.114 * b
        luminance < 128

      nil ->
        false
    end
  end

  defp is_dark_color?(_), do: false

  defp parse_hex_color("#" <> hex) do
    case String.length(hex) do
      6 ->
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 2), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 2, 2), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 4, 2), 16) do
          {r, g, b}
        else
          _ -> nil
        end

      3 ->
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 1), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 1, 1), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 2, 1), 16) do
          {r * 17, g * 17, b * 17}
        else
          _ -> nil
        end

      8 ->
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 2), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 2, 2), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 4, 2), 16) do
          {r, g, b}
        else
          _ -> nil
        end

      4 ->
        with {r, ""} <- Integer.parse(String.slice(hex, 0, 1), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 1, 1), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 2, 1), 16) do
          {r * 17, g * 17, b * 17}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_hex_color(_), do: nil

  # ===========================================================================
  # Base SVG Rendering
  # ===========================================================================

  @doc """
  Renders the background gradient SVG definition and rectangle.
  """
  def render_background_gradient(theme_suffix, theme_colors, opts \\ []) do
    id_suffix = safe_svg_id(theme_suffix)
    include_image_clip = Keyword.get(opts, :include_image_clip, true)

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
  """
  def render_image_section(entity, theme_suffix, _opts \\ []) do
    id_suffix = safe_svg_id(theme_suffix)

    if has_image?(entity) do
      if String.starts_with?(entity.cover_image_url, "/") do
        case local_image_data_url(entity) do
          nil ->
            render_no_image_placeholder()

          data_url ->
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
        case optimized_external_image_data_url(entity) do
          nil ->
            render_no_image_placeholder()

          data_url ->
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

  defp render_no_image_placeholder do
    """
    <rect x="418" y="32" width="350" height="350" rx="24" ry="24" fill="#f3f4f6" stroke="#e5e7eb" stroke-width="2"/>
    <text x="593" y="220" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" fill="#9ca3af">No Image</text>
    """
  end

  @doc """
  Renders a call-to-action bubble (e.g., "RSVP", "VOTE").
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

  # ===========================================================================
  # Sanitization Helpers
  # ===========================================================================

  @doc """
  Gets sanitized title for safe SVG rendering.
  """
  def safe_title(entity) do
    title = Map.get(entity, :title, "")
    Sanitizer.sanitize_text(title)
  end

  @doc """
  Gets sanitized description for safe SVG rendering.
  """
  def safe_description(entity) do
    description = Map.get(entity, :description, "")
    Sanitizer.sanitize_text(description)
  end
end
