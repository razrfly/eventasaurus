defmodule Eventasaurus.SocialCards.Sanitizer do
  @moduledoc """
  Simple, focused sanitizer for social card generation.
  Prioritizes security and simplicity over complex HTML processing.
  """

  @doc """
  Sanitizes event data for safe use in SVG templates.
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
  Sanitizes theme data for safe use in SVG templates.
  """
  @spec sanitize_theme_data(map()) :: map()
  def sanitize_theme_data(theme) do
    %{
      color1: validate_color(Map.get(theme, :color1)),
      color2: validate_color(Map.get(theme, :color2))
    }
  end

  @doc """
  Sanitizes text by removing all HTML/XML content and keeping only safe plain text.
  This is intentionally aggressive for security.
  """
  @spec sanitize_text(any()) :: String.t()
  def sanitize_text(text) when is_binary(text) do
    text
    |> HtmlSanitizeEx.strip_tags()  # Remove HTML tags completely
    |> String.replace(~r/[<>&"']/, "")  # Remove any remaining dangerous chars
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.trim()
    |> truncate_text(200)
  end
  def sanitize_text(_), do: ""

  @doc """
  Validates image URLs - only allows proper HTTP/HTTPS image URLs.
  """
  @spec validate_image_url(any()) :: String.t() | nil
  def validate_image_url(url) when is_binary(url) do
    uri = URI.parse(url)

    if valid_scheme?(uri.scheme) and valid_host?(uri.host) and image_extension?(url) do
      url
    else
      nil
    end
  end
  def validate_image_url(_), do: nil

  @doc """
  Validates hex color codes.
  """
  @spec validate_color(any()) :: String.t()
  def validate_color(color) when is_binary(color) do
    if Regex.match?(~r/^#[0-9A-Fa-f]{3,8}$/, color) do
      String.downcase(color)
    else
      "#6E56CF"
    end
  end
  def validate_color(_), do: "#6E56CF"

  # Simple private helpers
  defp truncate_text(text, max_length), do: String.slice(text, 0, max_length)

  defp valid_scheme?(scheme), do: scheme in ["http", "https"]

  defp valid_host?(host), do: is_binary(host) and String.length(host) > 2

  defp image_extension?(url), do: Regex.match?(~r/\.(jpe?g|png|gif|webp)(\?.*)?$/i, url)
end
