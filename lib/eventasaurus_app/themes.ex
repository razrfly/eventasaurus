defmodule EventasaurusApp.Themes do
  @moduledoc """
  The Themes context provides functions for theme validation and utilities.

  This module handles:
  - Theme validation
  - Theme customization merging
  - CSS class generation
  - Default theme configurations
  """

  @valid_themes [:minimal, :cosmic, :velocity, :retro, :celebration, :nature, :professional]

  @doc """
  Returns the list of all valid themes.
  """
  @spec valid_themes() :: [atom()]
  def valid_themes, do: @valid_themes

  @doc """
  Checks if a theme is valid.

  ## Examples

      iex> EventasaurusApp.Themes.valid_theme?(:minimal)
      true

      iex> EventasaurusApp.Themes.valid_theme?("cosmic")
      true

      iex> EventasaurusApp.Themes.valid_theme?(:invalid)
      false
  """
  @spec valid_theme?(atom() | String.t()) :: boolean()
  def valid_theme?(theme) when is_atom(theme), do: theme in @valid_themes
  def valid_theme?(theme) when is_binary(theme) do
    theme
    |> String.to_existing_atom()
    |> valid_theme?()
  rescue
    ArgumentError -> false
  end
  def valid_theme?(_), do: false

  @doc """
  Merges custom theme settings with base theme defaults.

  ## Examples

      iex> EventasaurusApp.Themes.merge_customizations(:minimal, %{"colors" => %{"primary" => "#ff0000"}})
      %{"colors" => %{"primary" => "#ff0000", "secondary" => "#333333", ...}, ...}
  """
  @spec merge_customizations(atom(), map()) :: map()
  def merge_customizations(theme, customizations) when is_atom(theme) and is_map(customizations) do
    default_customizations = get_default_customizations(theme)
    deep_merge(default_customizations, customizations)
  end

  @doc """
  Validates theme customizations for proper structure and values.

  Validates:
  - Color hex codes
  - Typography settings
  - Layout dimensions
  - Mode settings
  """
  @spec validate_customizations(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_customizations(customizations) when is_map(customizations) do
    with {:ok, _} <- validate_colors(Map.get(customizations, "colors", %{})),
         {:ok, _} <- validate_typography(Map.get(customizations, "typography", %{})),
         {:ok, _} <- validate_layout(Map.get(customizations, "layout", %{})),
         {:ok, _} <- validate_mode(Map.get(customizations, "mode", "light")) do
      {:ok, customizations}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the CSS class name for a given theme.

  ## Examples

      iex> EventasaurusApp.Themes.get_theme_css_class(:minimal)
      "theme-minimal"

      iex> EventasaurusApp.Themes.get_theme_css_class(:invalid)
      "theme-minimal"
  """
  @spec get_theme_css_class(atom() | String.t()) :: String.t()
  def get_theme_css_class(theme) when is_binary(theme) do
    try do
      theme
      |> String.to_existing_atom()
      |> get_theme_css_class()
    rescue
      ArgumentError -> "theme-minimal"
    end
  end
  def get_theme_css_class(theme) when theme in @valid_themes do
    "theme-#{theme}"
  end
  def get_theme_css_class(_), do: "theme-minimal" # Fallback to default

  @doc """
  Returns the default customizations for a given theme.
  """
  @spec get_default_customizations(atom()) :: map()
  def get_default_customizations(:minimal) do
    %{
      "colors" => %{
        "primary" => "#000000",
        "secondary" => "#333333",
        "accent" => "#0066cc",
        "background" => "#ffffff",
        "text" => "#000000",
        "text_secondary" => "#666666",
        "border" => "#e5e7eb"
      },
      "typography" => %{
        "font_family" => "Inter",
        "font_family_heading" => "Inter",
        "heading_weight" => "600",
        "body_size" => "16px",
        "body_weight" => "400"
      },
      "layout" => %{
        "border_radius" => "8px",
        "border_radius_large" => "12px",
        "shadow_style" => "soft",
        "button_border_radius" => "8px",
        "card_border_radius" => "12px",
        "input_border_radius" => "6px"
      },
      "mode" => "light"
    }
  end

  def get_default_customizations(:cosmic) do
    %{
      "colors" => %{
        "primary" => "#6366f1",
        "secondary" => "#8b5cf6",
        "accent" => "#06b6d4",
        "background" => "#0f172a",
        "text" => "#f8fafc",
        "text_secondary" => "#cbd5e1",
        "border" => "#334155"
      },
      "typography" => %{
        "font_family" => "Inter",
        "font_family_heading" => "Inter",
        "heading_weight" => "700",
        "body_size" => "16px",
        "body_weight" => "400"
      },
      "layout" => %{
        "border_radius" => "12px",
        "border_radius_large" => "16px",
        "shadow_style" => "glowing",
        "button_border_radius" => "12px",
        "card_border_radius" => "16px",
        "input_border_radius" => "8px"
      },
      "mode" => "dark"
    }
  end

  def get_default_customizations(:velocity) do
    %{
      "colors" => %{
        "primary" => "#ef4444",
        "secondary" => "#f97316",
        "accent" => "#eab308",
        "background" => "#fafafa",
        "text" => "#171717",
        "text_secondary" => "#525252",
        "border" => "#e5e5e5"
      },
      "typography" => %{
        "font_family" => "Inter",
        "font_family_heading" => "Inter",
        "heading_weight" => "800",
        "body_size" => "16px",
        "body_weight" => "400"
      },
      "layout" => %{
        "border_radius" => "6px",
        "border_radius_large" => "12px",
        "shadow_style" => "dynamic",
        "button_border_radius" => "6px",
        "card_border_radius" => "12px",
        "input_border_radius" => "6px"
      },
      "mode" => "light"
    }
  end

  def get_default_customizations(:retro) do
    %{
      "colors" => %{
        "primary" => "#d97706",
        "secondary" => "#dc2626",
        "accent" => "#059669",
        "background" => "#fef3c7",
        "text" => "#451a03",
        "text_secondary" => "#92400e",
        "border" => "#fbbf24"
      },
      "typography" => %{
        "font_family" => "Georgia",
        "font_family_heading" => "Georgia",
        "heading_weight" => "700",
        "body_size" => "17px",
        "body_weight" => "400"
      },
      "layout" => %{
        "border_radius" => "4px",
        "border_radius_large" => "8px",
        "shadow_style" => "vintage",
        "button_border_radius" => "4px",
        "card_border_radius" => "8px",
        "input_border_radius" => "4px"
      },
      "mode" => "light"
    }
  end

  def get_default_customizations(:celebration) do
    %{
      "colors" => %{
        "primary" => "#ec4899",
        "secondary" => "#8b5cf6",
        "accent" => "#06b6d4",
        "background" => "#fdf2f8",
        "text" => "#831843",
        "text_secondary" => "#be185d",
        "border" => "#f9a8d4"
      },
      "typography" => %{
        "font_family" => "Inter",
        "font_family_heading" => "Inter",
        "heading_weight" => "700",
        "body_size" => "16px",
        "body_weight" => "400"
      },
      "layout" => %{
        "border_radius" => "16px",
        "border_radius_large" => "24px",
        "shadow_style" => "festive",
        "button_border_radius" => "16px",
        "card_border_radius" => "24px",
        "input_border_radius" => "12px"
      },
      "mode" => "light"
    }
  end

  def get_default_customizations(:nature) do
    %{
      "colors" => %{
        "primary" => "#059669",
        "secondary" => "#065f46",
        "accent" => "#d97706",
        "background" => "#f0fdf4",
        "text" => "#064e3b",
        "text_secondary" => "#047857",
        "border" => "#bbf7d0"
      },
      "typography" => %{
        "font_family" => "Inter",
        "font_family_heading" => "Inter",
        "heading_weight" => "600",
        "body_size" => "16px",
        "body_weight" => "400"
      },
      "layout" => %{
        "border_radius" => "10px",
        "border_radius_large" => "16px",
        "shadow_style" => "organic",
        "button_border_radius" => "10px",
        "card_border_radius" => "16px",
        "input_border_radius" => "8px"
      },
      "mode" => "light"
    }
  end

  def get_default_customizations(:professional) do
    %{
      "colors" => %{
        "primary" => "#1e40af",
        "secondary" => "#374151",
        "accent" => "#dc2626",
        "background" => "#f8fafc",
        "text" => "#1e293b",
        "text_secondary" => "#64748b",
        "border" => "#e2e8f0"
      },
      "typography" => %{
        "font_family" => "Inter",
        "font_family_heading" => "Inter",
        "heading_weight" => "600",
        "body_size" => "16px",
        "body_weight" => "400"
      },
      "layout" => %{
        "border_radius" => "6px",
        "border_radius_large" => "8px",
        "shadow_style" => "corporate",
        "button_border_radius" => "6px",
        "card_border_radius" => "8px",
        "input_border_radius" => "6px"
      },
      "mode" => "light"
    }
  end

  # Fallback to minimal theme defaults
  def get_default_customizations(_), do: get_default_customizations(:minimal)

  # Private helper functions

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = left_val, %{} = right_val ->
        deep_merge(left_val, right_val)
      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp validate_colors(colors) when is_map(colors) do
    valid_keys = ["primary", "secondary", "accent", "background", "text", "text_secondary", "border"]

    # Check for unknown keys
    unknown_keys = Map.keys(colors) -- valid_keys
    if length(unknown_keys) > 0 do
      {:error, "Unknown color keys: #{Enum.join(unknown_keys, ", ")}"}
    else
      # Validate hex color format for each color
      colors
      |> Enum.reduce_while({:ok, colors}, fn {key, value}, acc ->
        if valid_hex_color?(value) do
          {:cont, acc}
        else
          {:halt, {:error, "Invalid hex color for #{key}: #{value}"}}
        end
      end)
    end
  end
  defp validate_colors(_), do: {:error, "Colors must be a map"}

  defp validate_typography(typography) when is_map(typography) do
    valid_keys = ["font_family", "font_family_heading", "heading_weight", "body_size", "body_weight"]

    unknown_keys = Map.keys(typography) -- valid_keys
    if length(unknown_keys) > 0 do
      {:error, "Unknown typography keys: #{Enum.join(unknown_keys, ", ")}"}
    else
      {:ok, typography}
    end
  end
  defp validate_typography(_), do: {:error, "Typography must be a map"}

  defp validate_layout(layout) when is_map(layout) do
    valid_keys = ["border_radius", "border_radius_large", "shadow_style", "button_border_radius", "card_border_radius", "input_border_radius"]

    unknown_keys = Map.keys(layout) -- valid_keys
    if length(unknown_keys) > 0 do
      {:error, "Unknown layout keys: #{Enum.join(unknown_keys, ", ")}"}
    else
      {:ok, layout}
    end
  end
  defp validate_layout(_), do: {:error, "Layout must be a map"}

  defp validate_mode(mode) when mode in ["light", "dark", "auto"] do
    {:ok, mode}
  end
  defp validate_mode(mode) do
    {:error, "Invalid mode: #{mode}. Must be 'light', 'dark', or 'auto'"}
  end

  defp valid_hex_color?(color) when is_binary(color) do
    # Match hex colors with 3, 4, 6, or 8 characters (with or without #)
    Regex.match?(~r/^#?([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8}|[A-Fa-f0-9]{3}|[A-Fa-f0-9]{4})$/, color)
  end
  defp valid_hex_color?(_), do: false
end
