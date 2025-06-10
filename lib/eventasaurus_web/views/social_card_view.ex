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
          # Handle local static file path
          static_path = Path.join(["priv", "static"]) |> Path.join(String.trim_leading(valid_url, "/"))
          if File.exists?(static_path) do
            Path.absname(static_path)
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
end
