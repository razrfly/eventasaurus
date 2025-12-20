defmodule EventasaurusWeb.Components.Activity.HeroCardTheme do
  @moduledoc """
  Centralized theming for hero card components.

  Consolidates gradient, overlay, badge, and button styles used across
  AggregatedHeroCard, ContainerHeroCard, GenericHeroCard, and other hero cards.

  ## Theme Categories

  - **Content themes**: trivia, food, movies, music, festival, social, comedy, theater, sports
  - **Container themes**: conference, tour, series, exhibition, tournament
  - **Color themes**: purple, blue, red, yellow, green, orange, teal, pink, indigo, rose, slate

  ## Usage

      alias EventasaurusWeb.Components.Activity.HeroCardTheme

      # Get individual style classes
      gradient = HeroCardTheme.gradient_class(:trivia)
      overlay = HeroCardTheme.overlay_class(:music)
      badge = HeroCardTheme.badge_class(:festival)
      button = HeroCardTheme.button_class(:food)
      label = HeroCardTheme.label(:trivia)  # => "Pub Quiz"

      # Get all styles for a theme at once
      %{gradient: g, overlay: o, badge: b, button: btn} = HeroCardTheme.theme(:trivia)
  """

  use Gettext, backend: EventasaurusWeb.Gettext

  @themes %{
    # Content-type themes (used by AggregatedHeroCard)
    trivia: %{
      gradient: "bg-gradient-to-r from-teal-900 via-teal-800 to-cyan-800",
      overlay: "bg-gradient-to-r from-teal-900/95 via-teal-900/80 to-cyan-900/60",
      badge: "bg-teal-500/20 text-teal-100",
      button: "bg-white text-teal-900 hover:bg-gray-100"
    },
    food: %{
      gradient: "bg-gradient-to-r from-orange-900 via-orange-800 to-amber-800",
      overlay: "bg-gradient-to-r from-orange-900/95 via-orange-900/80 to-amber-900/60",
      badge: "bg-orange-500/20 text-orange-100",
      button: "bg-white text-orange-900 hover:bg-gray-100"
    },
    movies: %{
      gradient: "bg-gradient-to-r from-gray-900 via-gray-800 to-slate-800",
      overlay: "bg-gradient-to-r from-gray-900/95 via-gray-900/85 to-slate-900/70",
      badge: "bg-slate-500/20 text-slate-100",
      button: "bg-white text-gray-900 hover:bg-gray-100"
    },
    music: %{
      gradient: "bg-gradient-to-r from-purple-900 via-purple-800 to-fuchsia-900",
      overlay: "bg-gradient-to-r from-purple-900/95 via-purple-900/80 to-fuchsia-900/60",
      badge: "bg-purple-500/20 text-purple-100",
      button: "bg-white text-purple-900 hover:bg-gray-100"
    },
    festival: %{
      gradient: "bg-gradient-to-r from-indigo-900 via-violet-800 to-purple-800",
      overlay: "bg-gradient-to-r from-indigo-900/95 via-violet-900/80 to-purple-900/60",
      badge: "bg-indigo-500/20 text-indigo-100",
      button: "bg-white text-indigo-900 hover:bg-gray-100"
    },
    social: %{
      gradient: "bg-gradient-to-r from-blue-900 via-blue-800 to-indigo-800",
      overlay: "bg-gradient-to-r from-blue-900/95 via-blue-900/80 to-indigo-900/60",
      badge: "bg-blue-500/20 text-blue-100",
      button: "bg-white text-blue-900 hover:bg-gray-100"
    },
    comedy: %{
      gradient: "bg-gradient-to-r from-amber-900 via-yellow-800 to-orange-800",
      overlay: "bg-gradient-to-r from-amber-900/95 via-yellow-900/80 to-orange-900/60",
      badge: "bg-amber-500/20 text-amber-100",
      button: "bg-white text-amber-900 hover:bg-gray-100"
    },
    theater: %{
      gradient: "bg-gradient-to-r from-red-900 via-rose-800 to-pink-800",
      overlay: "bg-gradient-to-r from-red-900/95 via-rose-900/80 to-pink-900/60",
      badge: "bg-red-500/20 text-red-100",
      button: "bg-white text-red-900 hover:bg-gray-100"
    },
    sports: %{
      gradient: "bg-gradient-to-r from-emerald-900 via-green-800 to-teal-800",
      overlay: "bg-gradient-to-r from-emerald-900/95 via-green-900/80 to-teal-900/60",
      badge: "bg-emerald-500/20 text-emerald-100",
      button: "bg-white text-emerald-900 hover:bg-gray-100"
    },

    # Entity-type themes (used by PerformerHeroCard, VenueHeroCard)
    performer: %{
      gradient: "bg-gradient-to-r from-purple-900 via-purple-800 to-fuchsia-900",
      overlay: "bg-gradient-to-r from-purple-900/95 via-purple-900/85 to-purple-800/70",
      badge: "bg-purple-500/20 text-purple-100",
      button: "bg-white text-purple-900 hover:bg-gray-100"
    },
    venue: %{
      gradient: "bg-gradient-to-r from-slate-900 via-slate-800 to-slate-700",
      overlay: "bg-gradient-to-r from-slate-900/95 via-slate-900/85 to-slate-800/70",
      badge: "bg-indigo-500/20 text-indigo-100",
      button: "bg-white text-slate-900 hover:bg-gray-100"
    },

    # Container-type themes (used by ContainerHeroCard)
    conference: %{
      gradient: "bg-gradient-to-r from-blue-900 via-blue-800 to-cyan-800",
      overlay: "bg-gradient-to-r from-blue-900/95 via-blue-900/80 to-cyan-900/60",
      badge: "bg-blue-500/20 text-blue-100",
      button: "bg-white text-blue-900 hover:bg-gray-100"
    },
    tour: %{
      gradient: "bg-gradient-to-r from-emerald-900 via-teal-800 to-cyan-800",
      overlay: "bg-gradient-to-r from-emerald-900/95 via-teal-900/80 to-cyan-900/60",
      badge: "bg-emerald-500/20 text-emerald-100",
      button: "bg-white text-emerald-900 hover:bg-gray-100"
    },
    series: %{
      gradient: "bg-gradient-to-r from-purple-900 via-purple-800 to-fuchsia-900",
      overlay: "bg-gradient-to-r from-purple-900/95 via-purple-900/80 to-fuchsia-900/60",
      badge: "bg-purple-500/20 text-purple-100",
      button: "bg-white text-purple-900 hover:bg-gray-100"
    },
    exhibition: %{
      gradient: "bg-gradient-to-r from-amber-900 via-orange-800 to-yellow-800",
      overlay: "bg-gradient-to-r from-amber-900/95 via-orange-900/80 to-yellow-900/60",
      badge: "bg-amber-500/20 text-amber-100",
      button: "bg-white text-amber-900 hover:bg-gray-100"
    },
    tournament: %{
      gradient: "bg-gradient-to-r from-red-900 via-rose-800 to-pink-800",
      overlay: "bg-gradient-to-r from-red-900/95 via-rose-900/80 to-pink-900/60",
      badge: "bg-red-500/20 text-red-100",
      button: "bg-white text-red-900 hover:bg-gray-100"
    },

    # Color-based themes (used by GenericHeroCard for schema types)
    purple: %{
      gradient: "bg-gradient-to-r from-purple-900 via-purple-800 to-purple-700",
      overlay: "bg-gradient-to-r from-purple-900/95 via-purple-900/80 to-purple-700/60",
      badge: "bg-purple-500/20 text-purple-100",
      button: "bg-white text-purple-900 hover:bg-gray-100"
    },
    blue: %{
      gradient: "bg-gradient-to-r from-blue-900 via-blue-800 to-blue-700",
      overlay: "bg-gradient-to-r from-blue-900/95 via-blue-900/80 to-blue-700/60",
      badge: "bg-blue-500/20 text-blue-100",
      button: "bg-white text-blue-900 hover:bg-gray-100"
    },
    red: %{
      gradient: "bg-gradient-to-r from-red-900 via-red-800 to-red-700",
      overlay: "bg-gradient-to-r from-red-900/95 via-red-900/80 to-red-700/60",
      badge: "bg-red-500/20 text-red-100",
      button: "bg-white text-red-900 hover:bg-gray-100"
    },
    yellow: %{
      gradient: "bg-gradient-to-r from-amber-900 via-amber-800 to-amber-700",
      overlay: "bg-gradient-to-r from-amber-900/95 via-amber-900/80 to-amber-700/60",
      badge: "bg-amber-500/20 text-amber-100",
      button: "bg-white text-amber-900 hover:bg-gray-100"
    },
    green: %{
      gradient: "bg-gradient-to-r from-emerald-900 via-emerald-800 to-emerald-700",
      overlay: "bg-gradient-to-r from-emerald-900/95 via-emerald-900/80 to-emerald-700/60",
      badge: "bg-emerald-500/20 text-emerald-100",
      button: "bg-white text-emerald-900 hover:bg-gray-100"
    },
    orange: %{
      gradient: "bg-gradient-to-r from-orange-900 via-orange-800 to-orange-700",
      overlay: "bg-gradient-to-r from-orange-900/95 via-orange-900/80 to-orange-700/60",
      badge: "bg-orange-500/20 text-orange-100",
      button: "bg-white text-orange-900 hover:bg-gray-100"
    },
    teal: %{
      gradient: "bg-gradient-to-r from-teal-900 via-teal-800 to-teal-700",
      overlay: "bg-gradient-to-r from-teal-900/95 via-teal-900/80 to-teal-700/60",
      badge: "bg-teal-500/20 text-teal-100",
      button: "bg-white text-teal-900 hover:bg-gray-100"
    },
    pink: %{
      gradient: "bg-gradient-to-r from-pink-900 via-pink-800 to-pink-700",
      overlay: "bg-gradient-to-r from-pink-900/95 via-pink-900/80 to-pink-700/60",
      badge: "bg-pink-500/20 text-pink-100",
      button: "bg-white text-pink-900 hover:bg-gray-100"
    },
    indigo: %{
      gradient: "bg-gradient-to-r from-indigo-900 via-indigo-800 to-indigo-700",
      overlay: "bg-gradient-to-r from-indigo-900/95 via-indigo-900/80 to-indigo-700/60",
      badge: "bg-indigo-500/20 text-indigo-100",
      button: "bg-white text-indigo-900 hover:bg-gray-100"
    },
    rose: %{
      gradient: "bg-gradient-to-r from-rose-900 via-rose-800 to-rose-700",
      overlay: "bg-gradient-to-r from-rose-900/95 via-rose-900/80 to-rose-700/60",
      badge: "bg-rose-500/20 text-rose-100",
      button: "bg-white text-rose-900 hover:bg-gray-100"
    },
    slate: %{
      gradient: "bg-gradient-to-r from-slate-900 via-slate-800 to-slate-700",
      overlay: "bg-gradient-to-r from-slate-900/95 via-slate-900/80 to-slate-700/60",
      badge: "bg-slate-500/20 text-slate-100",
      button: "bg-white text-slate-900 hover:bg-gray-100"
    },

    # Default fallback theme
    default: %{
      gradient: "bg-gradient-to-r from-gray-900 via-gray-800 to-gray-700",
      overlay: "bg-gradient-to-t from-gray-900/80 to-transparent",
      badge: "bg-white/20 text-white",
      button: "bg-white text-gray-900 hover:bg-gray-100"
    }
  }

  @doc """
  Returns the complete theme map for a given theme name.

  ## Examples

      iex> HeroCardTheme.theme(:trivia)
      %{gradient: "bg-gradient-to-r from-teal-900...", overlay: "...", badge: "...", button: "..."}

      iex> HeroCardTheme.theme(:unknown)
      %{gradient: "bg-gradient-to-r from-gray-900...", ...}
  """
  @spec theme(atom()) :: map()
  def theme(theme_name) when is_atom(theme_name) do
    Map.get(@themes, theme_name, @themes.default)
  end

  @doc """
  Returns the gradient class for a theme.

  Used for solid background gradients when no image is present.
  """
  @spec gradient_class(atom()) :: String.t()
  def gradient_class(theme_name) do
    theme(theme_name).gradient
  end

  @doc """
  Returns the overlay class for a theme.

  Used as a semi-transparent gradient overlay on top of background images.
  """
  @spec overlay_class(atom()) :: String.t()
  def overlay_class(theme_name) do
    theme(theme_name).overlay
  end

  @doc """
  Returns the badge class for a theme.

  Used for category/type badges displayed on hero cards.
  """
  @spec badge_class(atom()) :: String.t()
  def badge_class(theme_name) do
    theme(theme_name).badge
  end

  @doc """
  Returns the button class for a theme.

  Used for primary action buttons on hero cards.
  """
  @spec button_class(atom()) :: String.t()
  def button_class(theme_name) do
    theme(theme_name).button
  end

  @doc """
  Returns a list of all available theme names.
  """
  @spec available_themes() :: [atom()]
  def available_themes do
    Map.keys(@themes)
  end

  @doc """
  Checks if a theme name is valid/defined.
  """
  @spec valid_theme?(atom()) :: boolean()
  def valid_theme?(theme_name) when is_atom(theme_name) do
    Map.has_key?(@themes, theme_name)
  end

  def valid_theme?(_), do: false

  @doc """
  Returns a human-readable label for a theme.

  Used for displaying category/type names in hero card badges.

  ## Examples

      iex> HeroCardTheme.label(:trivia)
      "Pub Quiz"

      iex> HeroCardTheme.label(:festival)
      "Festival"

      iex> HeroCardTheme.label(:unknown)
      "Events"
  """
  @spec label(atom()) :: String.t()
  def label(theme_name) when is_atom(theme_name) do
    case theme_name do
      # Content themes
      :trivia -> gettext("Pub Quiz")
      :food -> gettext("Food & Dining")
      :movies -> gettext("Movies")
      :music -> gettext("Music")
      :festival -> gettext("Festival")
      :social -> gettext("Social Events")
      :comedy -> gettext("Comedy")
      :theater -> gettext("Theater")
      :sports -> gettext("Sports")
      # Container themes
      :conference -> gettext("Conference")
      :tour -> gettext("Tour")
      :series -> gettext("Series")
      :exhibition -> gettext("Exhibition")
      :tournament -> gettext("Tournament")
      # Entity types
      :venue -> gettext("Venue")
      :performer -> gettext("Artist")
      # Default
      _ -> gettext("Events")
    end
  end

  def label(_), do: gettext("Events")
end
