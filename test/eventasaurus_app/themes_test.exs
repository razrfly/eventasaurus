defmodule EventasaurusApp.ThemesTest do
  use ExUnit.Case, async: true

  alias EventasaurusApp.Themes

  describe "valid_themes/0" do
    test "returns all valid themes" do
      themes = Themes.valid_themes()

      assert is_list(themes)
      assert length(themes) == 7
      assert :minimal in themes
      assert :cosmic in themes
      assert :velocity in themes
      assert :retro in themes
      assert :celebration in themes
      assert :nature in themes
      assert :professional in themes
    end
  end

  describe "valid_theme?/1" do
    test "returns true for valid atom themes" do
      assert Themes.valid_theme?(:minimal) == true
      assert Themes.valid_theme?(:cosmic) == true
      assert Themes.valid_theme?(:velocity) == true
      assert Themes.valid_theme?(:retro) == true
      assert Themes.valid_theme?(:celebration) == true
      assert Themes.valid_theme?(:nature) == true
      assert Themes.valid_theme?(:professional) == true
    end

    test "returns true for valid string themes" do
      assert Themes.valid_theme?("minimal") == true
      assert Themes.valid_theme?("cosmic") == true
      assert Themes.valid_theme?("velocity") == true
    end

    test "returns false for invalid themes" do
      assert Themes.valid_theme?(:invalid) == false
      assert Themes.valid_theme?("invalid") == false
      assert Themes.valid_theme?(nil) == false
      assert Themes.valid_theme?(123) == false
    end
  end

  describe "get_theme_css_class/1" do
    test "returns correct CSS class for valid themes" do
      assert Themes.get_theme_css_class(:minimal) == "theme-minimal"
      assert Themes.get_theme_css_class(:cosmic) == "theme-cosmic"
      assert Themes.get_theme_css_class("velocity") == "theme-velocity"
    end

    test "returns default CSS class for invalid themes" do
      assert Themes.get_theme_css_class(:invalid) == "theme-minimal"
      assert Themes.get_theme_css_class("invalid") == "theme-minimal"
      assert Themes.get_theme_css_class(nil) == "theme-minimal"
    end
  end

  describe "get_default_customizations/1" do
    test "returns customizations for minimal theme" do
      customizations = Themes.get_default_customizations(:minimal)

      assert is_map(customizations)
      assert Map.has_key?(customizations, "colors")
      assert Map.has_key?(customizations, "typography")
      assert Map.has_key?(customizations, "layout")
      assert Map.has_key?(customizations, "mode")

      colors = customizations["colors"]
      assert colors["primary"] == "#000000"
      assert colors["background"] == "#ffffff"
      assert customizations["mode"] == "light"
    end

    test "returns customizations for cosmic theme" do
      customizations = Themes.get_default_customizations(:cosmic)

      colors = customizations["colors"]
      assert colors["primary"] == "#6366f1"
      assert colors["background"] == "#0f172a"
      assert customizations["mode"] == "dark"
    end

    test "returns minimal customizations for invalid themes" do
      minimal_customizations = Themes.get_default_customizations(:minimal)
      invalid_customizations = Themes.get_default_customizations(:invalid)

      assert minimal_customizations == invalid_customizations
    end
  end

  describe "merge_customizations/2" do
    test "merges custom colors with default theme" do
      custom = %{"colors" => %{"primary" => "#ff0000"}}
      merged = Themes.merge_customizations(:minimal, custom)

      assert merged["colors"]["primary"] == "#ff0000"
      assert merged["colors"]["secondary"] == "#333333" # Default preserved
      assert Map.has_key?(merged, "typography") # Other sections preserved
    end

    test "deep merges nested customizations" do
      custom = %{
        "colors" => %{"primary" => "#ff0000"},
        "typography" => %{"font_family" => "Arial"}
      }
      merged = Themes.merge_customizations(:minimal, custom)

      assert merged["colors"]["primary"] == "#ff0000"
      assert merged["colors"]["secondary"] == "#333333" # Default preserved
      assert merged["typography"]["font_family"] == "Arial"
      assert merged["typography"]["heading_weight"] == "600" # Default preserved
    end
  end

  describe "validate_customizations/1" do
    test "validates correct customizations" do
      valid_customizations = %{
        "colors" => %{
          "primary" => "#ff0000",
          "secondary" => "#00ff00"
        },
        "typography" => %{
          "font_family" => "Arial"
        },
        "layout" => %{
          "border_radius" => "8px"
        },
        "mode" => "light"
      }

      assert {:ok, ^valid_customizations} = Themes.validate_customizations(valid_customizations)
    end

    test "validates empty customizations" do
      assert {:ok, %{}} = Themes.validate_customizations(%{})
    end

    test "rejects invalid hex colors" do
      invalid_customizations = %{
        "colors" => %{
          "primary" => "not-a-color"
        }
      }

      assert {:error, message} = Themes.validate_customizations(invalid_customizations)
      assert message =~ "Invalid hex color"
    end

    test "rejects unknown color keys" do
      invalid_customizations = %{
        "colors" => %{
          "invalid_color" => "#ff0000"
        }
      }

      assert {:error, message} = Themes.validate_customizations(invalid_customizations)
      assert message =~ "Unknown color keys"
    end

    test "rejects invalid mode" do
      invalid_customizations = %{
        "mode" => "invalid_mode"
      }

      assert {:error, message} = Themes.validate_customizations(invalid_customizations)
      assert message =~ "Invalid mode"
    end

    test "accepts valid hex colors in different formats" do
      valid_customizations = %{
        "colors" => %{
          "primary" => "#ff0000",    # 6 digit with #
          "secondary" => "00ff00",   # 6 digit without #
          "accent" => "#f00",        # 3 digit with #
          "background" => "0f0"      # 3 digit without #
        }
      }

      assert {:ok, ^valid_customizations} = Themes.validate_customizations(valid_customizations)
    end
  end

  describe "CSS file accessibility" do
    @tag :skip
    test "cosmic theme CSS file is accessible via HTTP" do
      # Start the server if not already running
      Application.ensure_all_started(:eventasaurus)

      # Make HTTP request to the cosmic theme CSS (updated path)
      case HTTPoison.get("http://localhost:4000/assets/css/themes/cosmic.css") do
        {:ok, %HTTPoison.Response{status_code: 200, body: css_content}} ->
          # Check that the CSS contains cosmic theme styles
          assert String.contains?(css_content, ".theme-cosmic"),
            "Cosmic CSS should contain .theme-cosmic class"
          assert String.contains?(css_content, "--color-primary: #6366f1"),
            "Cosmic CSS should contain the indigo primary color"
          assert String.contains?(css_content, "Orbitron"),
            "Cosmic CSS should reference Orbitron font"
          assert String.contains?(css_content, "cosmicStars"),
            "Cosmic CSS should contain the star animation"

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          flunk("Expected cosmic.css to be accessible, but got HTTP #{status_code}")

        {:error, reason} ->
          flunk("Failed to fetch cosmic.css: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "cosmic theme is applied to event page" do
      # Make HTTP request to a cosmic-themed event page
      case HTTPoison.get("http://localhost:4000/tnhtg2b4fz") do
        {:ok, %HTTPoison.Response{status_code: 200, body: html_content}} ->
          # Check that the page has cosmic theme class
          assert String.contains?(html_content, "theme-cosmic"),
            "Event page should have theme-cosmic class"
          # Check that cosmic CSS is linked (updated path)
          assert String.contains?(html_content, "/assets/css/themes/cosmic.css"),
            "Event page should link to cosmic.css"
          # Check that Orbitron font is loaded
          assert String.contains?(html_content, "Orbitron"),
            "Event page should load Orbitron font for cosmic theme"

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          flunk("Expected event page to be accessible, but got HTTP #{status_code}")

        {:error, reason} ->
          flunk("Failed to fetch event page: #{inspect(reason)}")
      end
    end
  end
end
