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
    lines = split_into_lines(words, 18)  # ~18 chars per line max

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
    |> Enum.take(3)  # Max 3 lines
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
      nil -> nil
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
      nil -> nil
      local_path ->
        case File.read(local_path) do
          {:ok, image_data} ->
            # Determine MIME type from file extension
            mime_type = case Path.extname(local_path) |> String.downcase() do
              ".png" -> "image/png"
              ".jpg" -> "image/jpeg"
              ".jpeg" -> "image/jpeg"
              ".gif" -> "image/gif"
              ".webp" -> "image/webp"
              _ -> "image/png"  # Default fallback
            end

            # Convert to base64 and create data URL
            base64_data = Base.encode64(image_data)
            data_url = "data:#{mime_type};base64,#{base64_data}"

            # Clean up temporary downloaded files (but not static files)
            if String.contains?(local_path, "social_card_img_") do
              Task.start(fn ->
                Process.sleep(1000)  # Small delay to ensure data URL is used
                File.rm(local_path)
              end)
            end

            data_url

          {:error, _reason} -> nil
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
      nil -> nil
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
                    Process.sleep(30_000)  # 30 seconds delay
                    File.rm(static_path)
                  end)

                  # Return HTTP URL
                  "/images/temp/#{filename}"

                {:error, _reason} ->
                  File.rm(local_path)  # Clean up on failure
                  nil
              end

            {:error, _reason} -> nil
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
      nil -> nil
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
                  File.rm(local_path)  # Clean up on failure
                  nil
              end

            {:error, _reason} -> nil
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
      nil -> nil
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
                  mime_type = case Path.extname(resized_path || local_path) |> String.downcase() do
                    ".png" -> "image/png"
                    ".jpg" -> "image/jpeg"
                    ".jpeg" -> "image/jpeg"
                    ".gif" -> "image/gif"
                    ".webp" -> "image/webp"
                    _ -> "image/jpeg"  # Default for external images
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

            {:error, _reason} -> nil
          end
        else
          nil  # Not an external image
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
      {_output, exit_code} = System.cmd("convert", [
        image_path,
        "-resize", "400x400>",  # Only resize if larger than 400x400
        "-quality", "85",       # Reduce quality slightly
        resized_path
      ], stderr_to_stdout: true)

      if exit_code == 0 && File.exists?(resized_path) do
        resized_path
      else
        nil  # Fallback to original if resize fails
      end
    rescue
      _ -> nil  # ImageMagick not available or other error
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
  @logo_y 16
  @logo_width 280
  @logo_height 120

  # Title positioning constants to avoid duplication
  @title_x 32
  @title_base_y 200
  @title_line_spacing 8

  @doc """
  Calculates the Y position for a title line based on line number and font size.
  """
  def title_line_y_position(line_number, font_size) when line_number >= 0 do
    font_size_int = if is_binary(font_size), do: String.to_integer(font_size), else: font_size
    @title_base_y + (line_number * (font_size_int + @title_line_spacing))
  end

  # Pre-load and encode logo at compile time for better performance
  @logo_path Path.join([:code.priv_dir(:eventasaurus), "static", "images", "logos", "general.png"])
  @logo_data (case File.read(@logo_path) do
    {:ok, image_data} ->
      base64_data = Base.encode64(image_data)
      data_url = "data:image/png;base64,#{base64_data}"
      {:ok, data_url}
    {:error, _reason} ->
      {:error, :file_not_found}
  end)

  @doc """
  Gets the logo as an SVG element with base64 data URL for reliable rendering.
  Falls back to dinosaur emoji with consistent positioning if logo file cannot be read.
  """
  def get_logo_svg_element do
    case @logo_data do
      {:ok, data_url} ->
        """
        <image href="#{data_url}"
               x="#{@logo_x}" y="#{@logo_y}"
               width="#{@logo_width}" height="#{@logo_height}"
               preserveAspectRatio="xMidYMid meet"/>
        """

      {:error, :file_not_found} ->
        # Fallback with consistent positioning and background
        fallback_center_x = @logo_x + div(@logo_width, 2)
        fallback_center_y = @logo_y + div(@logo_height, 2) + 12  # Offset for text baseline

        """
        <rect x="#{@logo_x}" y="#{@logo_y}" width="#{@logo_width}" height="#{@logo_height}" rx="8" ry="8" fill="#10b981"/>
        <text x="#{fallback_center_x}" y="#{fallback_center_y}" text-anchor="middle" font-family="Arial, sans-serif" font-size="36" fill="white">🦖</text>
        """
    end
  end
end
