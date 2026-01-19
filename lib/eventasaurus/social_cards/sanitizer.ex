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
      id: Map.get(event, :id),
      title: sanitize_text(Map.get(event, :title, "")),
      description: sanitize_text(Map.get(event, :description, "")),
      cover_image_url: validate_image_url(Map.get(event, :cover_image_url)),
      updated_at: Map.get(event, :updated_at),
      theme: validate_theme(Map.get(event, :theme)),
      theme_customizations: sanitize_theme_customizations(Map.get(event, :theme_customizations)),
      # Date/time fields for social card display
      start_at: Map.get(event, :start_at),
      timezone: sanitize_timezone(Map.get(event, :timezone))
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
    # Remove HTML tags completely
    |> HtmlSanitizeEx.strip_tags()
    # Remove any remaining dangerous chars
    |> String.replace(~r/[<>&"']/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate_text(200)
  end

  def sanitize_text(_), do: ""

  @doc """
  Sanitizes timezone string - allows valid IANA timezone identifiers.
  """
  @spec sanitize_timezone(any()) :: String.t() | nil
  def sanitize_timezone(tz) when is_binary(tz) do
    # Only allow alphanumeric, underscores, slashes, and plus/minus (common in tz names)
    if Regex.match?(~r/^[A-Za-z0-9_\/+-]+$/, tz) do
      tz
    else
      nil
    end
  end

  def sanitize_timezone(_), do: nil

  @doc """
  Validates image URLs - allows HTTP/HTTPS URLs and local static file paths.
  """
  @spec validate_image_url(any()) :: String.t() | nil
  def validate_image_url(url) when is_binary(url) do
    # Handle local static file paths (e.g., /images/events/general/metaverse.png)
    if is_local_static_path?(url) do
      url
    else
      # Handle external URLs
      uri = URI.parse(url)

      if valid_scheme?(uri.scheme) and valid_host?(uri.host) and image_extension?(url) do
        url
      else
        nil
      end
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
  defp truncate_text(text, max_length) do
    Eventasaurus.Utils.Text.truncate_text(text, max_length)
  end

  defp valid_scheme?(scheme), do: scheme in ["http", "https"]

  defp valid_host?(host), do: is_binary(host) and String.length(host) > 2

  defp is_local_static_path?(path) do
    # Check if it's a local path starting with / and has a valid image extension
    if String.starts_with?(path, "/") and Regex.match?(~r/\.(jpe?g|png|gif|webp)$/i, path) do
      # SECURITY: Prevent directory traversal attacks
      # Normalize the path and ensure it stays within allowed directories
      normalized_path = Path.expand(path, "/")

      # Check that the normalized path starts with allowed directories
      allowed_prefixes = ["/images/", "/uploads/"]

      Enum.any?(allowed_prefixes, fn prefix ->
        # Ensure no traversal sequences remain after normalization
        String.starts_with?(normalized_path, prefix) and
          not String.contains?(normalized_path, "..")
      end)
    else
      false
    end
  end

  defp image_extension?(url) do
    # Check for file extension in path
    has_extension = Regex.match?(~r/\.(jpe?g|png|gif|webp)(\?.*)?$/i, url)

    # Also check for format indicators in query params (e.g., Unsplash URLs)
    has_format_param = Regex.match?(~r/[&?]fm=(jpe?g|png|gif|webp)/i, url)

    # Allow known image service domains even without explicit extensions
    known_image_service =
      Regex.match?(
        ~r/^https?:\/\/(images\.unsplash\.com|.*\.cloudinary\.com|.*\.amazonaws\.com)/i,
        url
      )

    has_extension or has_format_param or known_image_service
  end

  # Theme validation helpers
  defp validate_theme(theme) when is_atom(theme) do
    # Only allow known theme atoms
    valid_themes = [:minimal, :cosmic, :celebration, :velocity, :retro, :nature, :professional]
    if theme in valid_themes, do: theme, else: :minimal
  end

  defp validate_theme(_), do: :minimal

  defp sanitize_theme_customizations(customizations) when is_map(customizations) do
    # Only allow known safe keys and validate values
    # Handle both string and atom keys
    allowed_keys = [:colors, :fonts, :spacing, "colors", "fonts", "spacing"]

    customizations
    |> Map.take(allowed_keys)
    |> Enum.into(%{}, fn {key, value} ->
      normalized_key = normalize_key(key)
      {normalized_key, sanitize_theme_value(normalized_key, value)}
    end)
  end

  defp sanitize_theme_customizations(_), do: %{}

  defp sanitize_theme_value(:colors, colors) when is_map(colors) do
    allowed_keys = [
      :primary,
      :secondary,
      :accent,
      :text,
      :background,
      "primary",
      "secondary",
      "accent",
      "text",
      "background"
    ]

    colors
    |> Map.take(allowed_keys)
    |> Enum.into(%{}, fn {key, value} ->
      normalized_key = normalize_key(key)
      {normalized_key, validate_color(value)}
    end)
  end

  defp sanitize_theme_value(:fonts, fonts) when is_map(fonts) do
    # Only allow safe font properties
    allowed_keys = [:family, :size, :weight, "family", "size", "weight"]

    fonts
    |> Map.take(allowed_keys)
    |> Enum.into(%{}, fn {key, value} ->
      normalized_key = normalize_key(key)
      {normalized_key, sanitize_text(to_string(value))}
    end)
  end

  defp sanitize_theme_value(:spacing, spacing) when is_map(spacing) do
    # Only allow numeric spacing values
    allowed_keys = [:margin, :padding, :gap, "margin", "padding", "gap"]

    spacing
    |> Map.take(allowed_keys)
    |> Enum.into(%{}, fn {key, value} ->
      normalized_key = normalize_key(key)
      {normalized_key, sanitize_numeric_value(value)}
    end)
  end

  defp sanitize_theme_value(_, _), do: %{}

  # Helper to normalize keys to atoms
  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: String.to_atom(key)

  defp sanitize_numeric_value(value) when is_integer(value) and value >= 0 and value <= 100,
    do: value

  defp sanitize_numeric_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} when num >= 0 and num <= 100 -> num
      _ -> 0
    end
  end

  defp sanitize_numeric_value(_), do: 0
end
