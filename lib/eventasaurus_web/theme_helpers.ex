defmodule EventasaurusWeb.ThemeHelpers do
  @moduledoc """
  Helper functions for theme-related operations in templates.
  """

  import Phoenix.HTML.Tag
  alias EventasaurusApp.Themes

  @doc """
  Returns the theme CSS link tags based on the current theme.
  Only loads the base CSS and the specific theme CSS to optimize performance.
  """
  def theme_css_links(conn_or_socket) do
    theme =
      case conn_or_socket.assigns do
        %{theme: theme} when not is_nil(theme) -> theme
        # Default theme
        _ -> :minimal
      end

    # Always include base theme CSS
    base_css = tag(:link, rel: "stylesheet", href: "/assets/themes/base.css")

    # Include specific theme CSS
    theme_css = tag(:link, rel: "stylesheet", href: "/assets/themes/#{theme}.css")

    [base_css, theme_css]
  end

  @doc """
  Returns all theme CSS links for cases where we need to load all themes.
  This is useful for admin interfaces or theme preview functionality.
  """
  def all_theme_css_links do
    themes = Themes.valid_themes()

    # Always include base theme CSS first
    base_css = tag(:link, rel: "stylesheet", href: "/assets/themes/base.css")

    # Include all theme CSS files
    theme_css_links =
      Enum.map(themes, fn theme ->
        tag(:link, rel: "stylesheet", href: "/assets/themes/#{theme}.css")
      end)

    [base_css | theme_css_links]
  end

  @doc """
  Generates inline CSS variables for theme customizations.
  This is used when we need to apply custom theme variables directly to elements.
  """
  def theme_css_variables(customizations) when is_map(customizations) do
    variables = []

    # Add color variables
    colors = Map.get(customizations, "colors", %{})

    variables =
      Enum.reduce(colors, variables, fn {key, value}, acc ->
        sanitized_key = sanitize_css_identifier(key)
        sanitized_value = sanitize_and_normalize_color(value)
        ["--color-#{sanitized_key}: #{sanitized_value};" | acc]
      end)

    # Add typography variables
    typography = Map.get(customizations, "typography", %{})

    variables =
      Enum.reduce(typography, variables, fn {key, value}, acc ->
        sanitized_key = sanitize_css_identifier(key)
        sanitized_value = sanitize_css_value(value)
        ["--#{sanitized_key}: #{sanitized_value};" | acc]
      end)

    # Add layout variables
    layout = Map.get(customizations, "layout", %{})

    variables =
      Enum.reduce(layout, variables, fn {key, value}, acc ->
        sanitized_key = sanitize_css_identifier(key)
        sanitized_value = sanitize_css_value(value)
        ["--#{sanitized_key}: #{sanitized_value};" | acc]
      end)

    # Join all variables
    Enum.join(variables, " ")
  end

  def theme_css_variables(_), do: ""

  # Private helper functions for CSS sanitization

  defp sanitize_css_identifier(identifier) do
    # Remove any characters that aren't alphanumeric, dash, or underscore
    identifier
    |> to_string()
    |> String.replace("_", "-")
    |> String.replace(~r/[^a-zA-Z0-9\-]/, "")
  end

  defp sanitize_css_value(value) do
    # Escape potentially dangerous characters
    value
    |> to_string()
    |> String.replace(";", "")
    |> String.replace("}", "")
    |> String.replace("{", "")
    |> String.replace("/*", "")
    |> String.replace("*/", "")
    |> String.replace("</", "")
    |> String.replace("<", "")
    |> String.replace(">", "")
  end

  defp sanitize_and_normalize_color(value) do
    sanitized = sanitize_css_value(value)

    # Normalize hex colors - add # if missing
    cond do
      # Already has # prefix
      String.match?(sanitized, ~r/^#[0-9a-fA-F]{3,6}$/) ->
        sanitized

      # Valid hex without # prefix
      String.match?(sanitized, ~r/^[0-9a-fA-F]{3,6}$/) ->
        "#" <> sanitized

      # Other color formats (rgba, hsl, named colors, etc.)
      true ->
        sanitized
    end
  end

  @doc """
  Returns the appropriate theme class for an element based on the theme.
  """
  def theme_class(theme) when is_atom(theme) do
    "theme-#{theme}"
  end

  def theme_class(theme) when is_binary(theme) do
    try do
      theme_atom = String.to_existing_atom(theme)
      "theme-#{theme_atom}"
    rescue
      ArgumentError -> "theme-minimal"
    end
  end

  def theme_class(_), do: "theme-minimal"

  @doc """
  Returns font links for themes that require external fonts.
  """
  def theme_font_links do
    # Load Google Fonts for different themes
    fonts = [
      # Orbitron for cosmic theme (space-like)
      "https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&display=swap",
      # Playfair Display for retro theme
      "https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&display=swap",
      # Montserrat for professional theme
      "https://fonts.googleapis.com/css2?family=Montserrat:wght@300;400;600;700&display=swap",
      # Fredoka One for celebration theme
      "https://fonts.googleapis.com/css2?family=Fredoka+One&display=swap",
      # Merriweather for nature theme
      "https://fonts.googleapis.com/css2?family=Merriweather:wght@300;400;700&display=swap",
      # Rajdhani for velocity theme
      "https://fonts.googleapis.com/css2?family=Rajdhani:wght@300;400;600;700&display=swap"
    ]

    fonts
    |> Enum.map(fn font_url ->
      Phoenix.HTML.raw("""
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="#{font_url}" rel="stylesheet">
      """)
    end)
  end

  @doc """
  Returns the Google Fonts link for a specific theme
  """
  def theme_font_link(:minimal), do: ""

  def theme_font_link(:cosmic),
    do:
      ~s(<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&display=swap" rel="stylesheet">)

  def theme_font_link(:velocity),
    do:
      ~s(<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Rajdhani:wght@400;600;700&display=swap" rel="stylesheet">)

  def theme_font_link(:retro),
    do:
      ~s(<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&display=swap" rel="stylesheet">)

  def theme_font_link(:celebration),
    do:
      ~s(<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;600&display=swap" rel="stylesheet">)

  def theme_font_link(:nature),
    do:
      ~s(<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Merriweather:wght@400;700&display=swap" rel="stylesheet">)

  def theme_font_link(:professional),
    do:
      ~s(<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700&display=swap" rel="stylesheet">)

  def theme_font_link(_), do: ""

  @doc """
  Determines if a theme should use dark mode navbar styling
  """
  def dark_theme?(theme) when theme in [:cosmic], do: true
  def dark_theme?(_theme), do: false

  @doc """
  Returns appropriate navbar background classes based on theme
  """
  def navbar_bg_classes(theme) do
    if dark_theme?(theme) do
      "bg-gray-900 shadow-lg"
    else
      "bg-white shadow-sm"
    end
  end

  @doc """
  Returns appropriate navbar text classes based on theme
  """
  def navbar_text_classes(theme) do
    if dark_theme?(theme) do
      "text-gray-100"
    else
      "text-gray-700"
    end
  end

  @doc """
  Returns appropriate navbar link classes based on theme
  """
  def navbar_link_classes(theme) do
    if dark_theme?(theme) do
      "text-gray-100 hover:text-white"
    else
      "text-gray-700 hover:text-gray-900"
    end
  end

  @doc """
  Returns appropriate navbar border classes based on theme
  """
  def navbar_border_classes(theme) do
    if dark_theme?(theme) do
      "border-gray-700"
    else
      "border-gray-200"
    end
  end
end
