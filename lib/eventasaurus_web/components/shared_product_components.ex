defmodule EventasaurusWeb.Components.SharedProductComponents do
  @moduledoc """
  Shared components for product pages (Changelog, Roadmap).

  Provides consistent styling for tags, color strips, and badges
  across the changelog and roadmap pages.
  """
  use Phoenix.Component

  # =============================================================================
  # Tag Badge Component
  # =============================================================================

  @doc """
  Renders a tag badge with consistent styling.

  ## Examples

      <.tag_badge tag="mobile" />
      <.tag_badge tag="social" />
  """
  attr :tag, :string, required: true

  def tag_badge(assigns) do
    {bg_color, text_color, ring_color} = tag_color(assigns.tag)

    assigns =
      assigns
      |> assign(:bg_color, bg_color)
      |> assign(:text_color, text_color)
      |> assign(:ring_color, ring_color)

    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset",
      @bg_color, @text_color, @ring_color
    ]}>
      <%= @tag %>
    </span>
    """
  end

  # =============================================================================
  # Tag Color Functions
  # =============================================================================

  @doc """
  Returns {bg_color, text_color, ring_color} for tag badges.
  Comprehensive list covering both changelog and roadmap tags.
  """
  @spec tag_color(String.t()) :: {String.t(), String.t(), String.t()}
  def tag_color(tag) do
    case String.downcase(tag) do
      # Platform & Technical
      "mobile" -> {"bg-sky-50", "text-sky-700", "ring-sky-700/10"}
      "ios" -> {"bg-sky-50", "text-sky-700", "ring-sky-700/10"}
      "android" -> {"bg-sky-50", "text-sky-700", "ring-sky-700/10"}
      "platform" -> {"bg-slate-50", "text-slate-700", "ring-slate-700/10"}
      "api" -> {"bg-emerald-50", "text-emerald-700", "ring-emerald-700/10"}
      "integration" -> {"bg-emerald-50", "text-emerald-700", "ring-emerald-700/10"}
      "sync" -> {"bg-emerald-50", "text-emerald-700", "ring-emerald-700/10"}
      "devtools" -> {"bg-lime-50", "text-lime-700", "ring-lime-700/10"}
      "infrastructure" -> {"bg-slate-50", "text-slate-700", "ring-slate-700/10"}

      # AI & Discovery
      "ai" -> {"bg-fuchsia-50", "text-fuchsia-700", "ring-fuchsia-700/10"}
      "planning" -> {"bg-fuchsia-50", "text-fuchsia-700", "ring-fuchsia-700/10"}
      "suggestions" -> {"bg-fuchsia-50", "text-fuchsia-700", "ring-fuchsia-700/10"}
      "discovery" -> {"bg-emerald-50", "text-emerald-700", "ring-emerald-700/10"}
      "explore" -> {"bg-emerald-50", "text-emerald-700", "ring-emerald-700/10"}
      "public-events" -> {"bg-emerald-50", "text-emerald-700", "ring-emerald-700/10"}
      "search" -> {"bg-teal-50", "text-teal-700", "ring-teal-700/10"}

      # Social & Community
      "social" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "matching" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "activities" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "chat" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "communication" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "collaboration" -> {"bg-purple-50", "text-purple-700", "ring-purple-700/10"}
      "groups" -> {"bg-purple-50", "text-purple-700", "ring-purple-700/10"}
      "communities" -> {"bg-purple-50", "text-purple-700", "ring-purple-700/10"}
      "friends" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "invitations" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "email" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}

      # Scheduling & Planning
      "polling" -> {"bg-blue-50", "text-blue-700", "ring-blue-700/10"}
      "scheduling" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      "voting" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}
      "decisions" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}
      "calendar" -> {"bg-blue-50", "text-blue-700", "ring-blue-700/10"}
      "recurring" -> {"bg-blue-50", "text-blue-700", "ring-blue-700/10"}

      # Music & Entertainment
      "music" -> {"bg-pink-50", "text-pink-700", "ring-pink-700/10"}
      "spotify" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "gaming" -> {"bg-red-50", "text-red-700", "ring-red-700/10"}
      "boardgames" -> {"bg-red-50", "text-red-700", "ring-red-700/10"}

      # Events & Templates
      "templates" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}
      "productivity" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}
      "festivals" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}
      "multi-day" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}

      # Commerce & Transactions
      "ticketing" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "payments" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "crowdfunding" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "monetization" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}

      # Content & Media
      "photos" -> {"bg-rose-50", "text-rose-700", "ring-rose-700/10"}
      "memories" -> {"bg-rose-50", "text-rose-700", "ring-rose-700/10"}
      "sharing" -> {"bg-rose-50", "text-rose-700", "ring-rose-700/10"}

      # Food & Drink
      "wine" -> {"bg-red-50", "text-red-700", "ring-red-700/10"}
      "tasting" -> {"bg-red-50", "text-red-700", "ring-red-700/10"}
      "ratings" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}

      # Location & Venues
      "venues" -> {"bg-teal-50", "text-teal-700", "ring-teal-700/10"}
      "reviews" -> {"bg-teal-50", "text-teal-700", "ring-teal-700/10"}
      "maps" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "location" -> {"bg-lime-50", "text-lime-700", "ring-lime-700/10"}

      # Lists & Organization
      "lists" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      "contributions" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      "export" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}

      # Gamification
      "leagues" -> {"bg-orange-50", "text-orange-700", "ring-orange-700/10"}
      "gamification" -> {"bg-orange-50", "text-orange-700", "ring-orange-700/10"}

      # Communication
      "reminders" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}
      "notifications" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}
      "messaging" -> {"bg-yellow-50", "text-yellow-700", "ring-yellow-700/10"}

      # Design & Customization
      "themes" -> {"bg-pink-50", "text-pink-700", "ring-pink-700/10"}
      "design" -> {"bg-pink-50", "text-pink-700", "ring-pink-700/10"}
      "customization" -> {"bg-red-50", "text-red-700", "ring-red-700/10"}
      "ux" -> {"bg-rose-50", "text-rose-700", "ring-rose-700/10"}
      "accessibility" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}

      # Analytics & Business
      "analytics" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      "business" -> {"bg-gray-50", "text-gray-700", "ring-gray-700/10"}
      "performance" -> {"bg-orange-50", "text-orange-700", "ring-orange-700/10"}

      # Default
      _ -> {"bg-zinc-50", "text-zinc-700", "ring-zinc-700/10"}
    end
  end

  @doc """
  Returns solid color class for card left strips based on tag.
  Used for the colorful left border on cards.
  """
  @spec tag_strip_color(String.t()) :: String.t()
  def tag_strip_color(tag) do
    case String.downcase(tag) do
      # Platform & Technical
      "mobile" -> "bg-sky-500"
      "ios" -> "bg-sky-500"
      "android" -> "bg-sky-500"
      "platform" -> "bg-slate-500"
      "api" -> "bg-emerald-500"
      "integration" -> "bg-emerald-500"
      "sync" -> "bg-emerald-500"

      # AI & Discovery
      "ai" -> "bg-fuchsia-500"
      "planning" -> "bg-fuchsia-400"
      "discovery" -> "bg-emerald-500"
      "explore" -> "bg-emerald-500"
      "public-events" -> "bg-emerald-500"

      # Social & Community
      "social" -> "bg-violet-500"
      "matching" -> "bg-violet-500"
      "activities" -> "bg-violet-400"
      "chat" -> "bg-violet-500"
      "communication" -> "bg-violet-400"
      "collaboration" -> "bg-purple-500"
      "groups" -> "bg-purple-500"
      "communities" -> "bg-purple-500"
      "friends" -> "bg-violet-500"
      "invitations" -> "bg-violet-500"
      "email" -> "bg-violet-400"

      # Scheduling & Planning
      "polling" -> "bg-blue-500"
      "scheduling" -> "bg-cyan-500"
      "voting" -> "bg-indigo-500"
      "decisions" -> "bg-indigo-500"
      "calendar" -> "bg-blue-500"
      "recurring" -> "bg-blue-400"

      # Music & Entertainment
      "music" -> "bg-pink-500"
      "spotify" -> "bg-green-500"
      "gaming" -> "bg-red-500"
      "boardgames" -> "bg-red-500"

      # Events & Templates
      "templates" -> "bg-indigo-500"
      "productivity" -> "bg-indigo-400"
      "festivals" -> "bg-amber-500"
      "multi-day" -> "bg-amber-500"

      # Commerce & Transactions
      "ticketing" -> "bg-green-500"
      "payments" -> "bg-green-500"
      "crowdfunding" -> "bg-green-400"
      "monetization" -> "bg-green-500"

      # Content & Media
      "photos" -> "bg-rose-500"
      "memories" -> "bg-rose-400"
      "sharing" -> "bg-rose-500"

      # Food & Drink
      "wine" -> "bg-red-600"
      "tasting" -> "bg-red-500"
      "ratings" -> "bg-amber-500"

      # Location & Venues
      "venues" -> "bg-teal-500"
      "reviews" -> "bg-teal-400"
      "maps" -> "bg-green-500"
      "location" -> "bg-lime-500"

      # Lists & Organization
      "lists" -> "bg-cyan-500"
      "contributions" -> "bg-cyan-400"
      "export" -> "bg-cyan-500"

      # Gamification
      "leagues" -> "bg-orange-500"
      "gamification" -> "bg-orange-500"
      "notifications" -> "bg-amber-500"

      # Design & Customization
      "themes" -> "bg-pink-500"
      "design" -> "bg-pink-500"
      "customization" -> "bg-red-500"

      # Default
      _ -> "bg-zinc-400"
    end
  end
end
