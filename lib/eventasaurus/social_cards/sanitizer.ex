defmodule Eventasaurus.SocialCards.Sanitizer do
  @moduledoc """
  Provides functions for validating and sanitizing input data for social card generation.

  This module ensures that all user-provided data is properly sanitized to prevent
  SVG injection attacks and other security vulnerabilities when generating social cards.
  """

  @doc """
  Validates and sanitizes event data for safe use in SVG templates.
  Returns a map with sanitized values.

  ## Examples

      iex> event = %{id: 1, title: "<script>alert('xss')</script>My Event", cover_image_url: "https://example.com/image.jpg", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.Sanitizer.sanitize_event_data(event)
      %{
        id: 1,
        title: "My Event",
        cover_image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

  """
  @spec sanitize_event_data(map()) :: map()
  def sanitize_event_data(event) do
    %{
      id: event.id,
      title: sanitize_text(Map.get(event, :title, "")),
      description: sanitize_text(Map.get(event, :description, "")),
      cover_image_url: validate_image_url(Map.get(event, :cover_image_url)),
      updated_at: Map.get(event, :updated_at)
    }
  end

  @doc """
  Validates and sanitizes theme data for safe use in SVG templates.
  Returns a map with sanitized values.

  ## Examples

      iex> theme = %{color1: "#ff0000", color2: "invalid-color"}
      iex> Eventasaurus.SocialCards.Sanitizer.sanitize_theme_data(theme)
      %{color1: "#ff0000", color2: "#6E56CF"}

  """
  @spec sanitize_theme_data(map()) :: map()
  def sanitize_theme_data(theme) do
    %{
      color1: validate_color(Map.get(theme, :color1)),
      color2: validate_color(Map.get(theme, :color2))
    }
  end

  @doc """
  Sanitizes text for safe inclusion in SVG.

  This function:
  - Strips HTML/XML tags
  - Removes control characters
  - Escapes XML special characters
  - Truncates to reasonable length to prevent DoS

  ## Examples

      iex> Eventasaurus.SocialCards.Sanitizer.sanitize_text("<script>alert('xss')</script>Hello & World")
      "Hello &amp; World"

      iex> Eventasaurus.SocialCards.Sanitizer.sanitize_text("<svg><rect/></svg>My Event")
      "My Event"

  """
  @spec sanitize_text(any()) :: String.t()
  def sanitize_text(text) when is_binary(text) do
    text
    |> strip_html_tags()
    |> remove_control_characters()
    |> escape_xml_characters()
    |> String.trim()
    |> truncate_text(200)  # Prevent extremely long titles
  end
  def sanitize_text(_), do: ""

  @doc """
  Validates image URL and returns a default if invalid.

  Only allows HTTP/HTTPS URLs and validates basic URL structure.

  ## Examples

      iex> Eventasaurus.SocialCards.Sanitizer.validate_image_url("https://example.com/image.jpg")
      "https://example.com/image.jpg"

      iex> Eventasaurus.SocialCards.Sanitizer.validate_image_url("javascript:alert('xss')")
      nil

  """
  @spec validate_image_url(any()) :: String.t() | nil
  def validate_image_url(url) when is_binary(url) do
    # Basic URL validation - only allow HTTP/HTTPS
    if Regex.match?(~r/^https?:\/\/[^\s<>"{}|\\^`\[\]]+$/i, url) do
      # Additional validation to prevent common injection patterns
      if String.contains?(url, ["javascript:", "data:", "vbscript:", "<", ">"]) do
        nil
      else
        url
      end
    else
      nil
    end
  end
  def validate_image_url(_), do: nil

  @doc """
  Validates color value and returns a default if invalid.

  Accepts hex colors in formats: #RGB, #RRGGBB, #RRGGBBAA

  ## Examples

      iex> Eventasaurus.SocialCards.Sanitizer.validate_color("#ff0000")
      "#ff0000"

      iex> Eventasaurus.SocialCards.Sanitizer.validate_color("red")
      "#6E56CF"

  """
  @spec validate_color(any()) :: String.t()
  def validate_color(color) when is_binary(color) do
    # Allow hex colors: #RGB, #RRGGBB, #RRGGBBAA
    if Regex.match?(~r/^#([0-9A-F]{3}|[0-9A-F]{6}|[0-9A-F]{8})$/i, color) do
      String.downcase(color)
    else
      "#6E56CF"  # Default purple color
    end
  end
  def validate_color(_), do: "#6E56CF"

  # Private helper functions

  # Strip HTML/XML tags using a more careful regex approach
  defp strip_html_tags(text) do
    text
    # Remove dangerous tags and their content (script, style, iframe, object, embed)
    |> String.replace(~r/<(script|style|iframe|object|embed)[^>]*>.*?<\/\1>/mis, "")
    # Remove self-closing dangerous tags
    |> String.replace(~r/<(script|style|iframe|object|embed)[^>]*\/>/mi, "")
    # For SVG tags, remove the tag but keep the content
    |> String.replace(~r/<svg[^>]*>/mi, "")
    |> String.replace(~r/<\/svg>/mi, "")
    # Remove all other HTML/XML tags (keep content)
    |> String.replace(~r/<\/?[a-zA-Z][^>]*>/m, "")
    # Remove HTML entities
    |> String.replace(~r/&[a-zA-Z0-9#]+;/, "")
  end

  # Remove control characters that could break SVG (but not spaces or normal text characters)
  defp remove_control_characters(text) do
    String.replace(text, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, "")
  end

  # Escape XML special characters
  defp escape_xml_characters(text) do
    text
    |> String.replace("&", "&amp;")   # Must be first to avoid double-escaping
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  # Truncate text to prevent DoS attacks with extremely long strings
  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end
end
