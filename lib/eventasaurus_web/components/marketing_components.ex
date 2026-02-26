defmodule EventasaurusWeb.MarketingComponents do
  @moduledoc """
  Components for the Wombie marketing rebrand pages.
  Follows the Oatmeal olive palette + Familjen Grotesk + editorial whitespace aesthetic.
  """
  use Phoenix.Component
  import EventasaurusWeb.CoreComponents, only: [logo: 1]

  # ─── Layout ──────────────────────────────────────────────────────

  @doc """
  Top-level wrapper that applies the `.marketing-page` scoping class.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def marketing_page(assigns) do
    ~H"""
    <div class={["marketing-page min-h-screen", @class]} id="marketing-root" phx-hook="ScrollReveal">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Sticky minimal navigation bar for marketing pages.
  """
  attr :class, :string, default: ""

  def marketing_nav(assigns) do
    ~H"""
    <header class={[
      "sticky top-0 z-50 border-b border-oat-200/60 bg-oat-100",
      @class
    ]}>
      <div class="mx-auto max-w-2xl md:max-w-3xl lg:max-w-7xl px-6 lg:px-10 py-4 flex items-center justify-between">
        <.logo class="text-2xl" text_color="text-oat-950" />
        <nav class="hidden md:flex items-center gap-8">
          <a href="/about" class="text-sm/7 font-medium text-oat-950 hover:text-oat-700 transition-colors">
            About
          </a>
          <a href="/our-story" class="text-sm/7 font-medium text-oat-950 hover:text-oat-700 transition-colors">
            Our Story
          </a>
          <.m_button href="/invite-only" variant="primary" size="sm">
            Get Started
          </.m_button>
        </nav>
        <!-- Mobile: simple CTA -->
        <div class="md:hidden">
          <.m_button href="/invite-only" variant="primary" size="sm">
            Get Started
          </.m_button>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Dark olive footer for marketing pages.
  """
  def marketing_footer(assigns) do
    ~H"""
    <footer class="bg-oat-950/[0.025] text-oat-950">
      <div class="mx-auto max-w-2xl md:max-w-3xl lg:max-w-7xl px-6 lg:px-10 py-16">
        <div class="flex flex-col md:flex-row justify-between gap-8">
          <div>
            <.logo class="text-lg" text_color="text-oat-950" />
            <p class="mt-2 text-sm text-oat-600 max-w-xs">
              Real-world connection, starting with your closest friends.
            </p>
          </div>
          <div class="flex gap-12 text-sm">
            <div class="space-y-3">
              <p class="font-medium text-oat-950">Product</p>
              <a href="/about" class="block text-oat-600 hover:text-oat-950 transition-colors">About</a>
              <a href="/our-story" class="block text-oat-600 hover:text-oat-950 transition-colors">Our Story</a>
              <a href="/whats-new" class="block text-oat-600 hover:text-oat-950 transition-colors">What's New</a>
            </div>
            <div class="space-y-3">
              <p class="font-medium text-oat-950">Legal</p>
              <a href="/privacy" class="block text-oat-600 hover:text-oat-950 transition-colors">Privacy</a>
              <a href="/terms" class="block text-oat-600 hover:text-oat-950 transition-colors">Terms</a>
              <a href="/your-data" class="block text-oat-600 hover:text-oat-950 transition-colors">Your Data</a>
            </div>
          </div>
        </div>
        <div class="mt-12 pt-8 border-t border-oat-300 text-sm text-oat-600">
          &copy; <%= Date.utc_today().year %> Wombie. All rights reserved.
        </div>
      </div>
    </footer>
    """
  end

  @doc """
  Centered container — max-w-6xl by default, max-w-3xl with `narrow`.
  """
  attr :class, :string, default: ""
  attr :narrow, :boolean, default: false
  slot :inner_block, required: true

  def m_container(assigns) do
    ~H"""
    <div class={[
      "mx-auto px-6 lg:px-10",
      if(@narrow, do: "max-w-3xl", else: "max-w-2xl md:max-w-3xl lg:max-w-7xl"),
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Full-width section with background variant.
  Variants: primary (oat-100), secondary (oat-50), tertiary (oat-200), dark (oat-950).
  """
  attr :variant, :string, default: "primary"
  attr :class, :string, default: ""
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def m_section(assigns) do
    ~H"""
    <section id={@id} class={[
      "py-16",
      section_bg(@variant),
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </section>
    """
  end

  defp section_bg("primary"), do: "bg-oat-100"
  defp section_bg("secondary"), do: "bg-oat-50"
  defp section_bg("tertiary"), do: "bg-oat-200"
  defp section_bg("dark"), do: "bg-oat-950 text-white"
  defp section_bg(_), do: "bg-oat-100"

  # ─── Typography ──────────────────────────────────────────────────

  @doc """
  Display heading in Familjen Grotesk with tight tracking.
  """
  attr :level, :string, default: "h2"
  attr :class, :string, default: ""
  attr :size, :string, default: "default"
  slot :inner_block, required: true

  def m_heading(assigns) do
    assigns =
      assign(assigns, :classes, [
        "font-familjen text-pretty text-oat-950",
        heading_size(assigns.size),
        assigns.class
      ])

    case assigns.level do
      "h1" -> ~H"<h1 class={@classes}><%= render_slot(@inner_block) %></h1>"
      "h2" -> ~H"<h2 class={@classes}><%= render_slot(@inner_block) %></h2>"
      "h3" -> ~H"<h3 class={@classes}><%= render_slot(@inner_block) %></h3>"
      _ -> ~H"<h2 class={@classes}><%= render_slot(@inner_block) %></h2>"
    end
  end

  defp heading_size("hero"), do: "text-5xl/none sm:text-6xl/none tracking-[-0.04em]"

  defp heading_size("large"),
    do: "text-3xl/tight sm:text-4xl/tight font-medium tracking-[-0.03em]"

  defp heading_size("default"),
    do: "text-2xl/tight sm:text-3xl/tight font-medium tracking-[-0.03em]"

  defp heading_size("small"), do: "text-xl sm:text-2xl font-medium tracking-[-0.03em]"
  defp heading_size(_), do: "text-2xl/tight sm:text-3xl/tight font-medium tracking-[-0.03em]"

  @doc """
  Quiet eyebrow label in olive tone.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def m_label(assigns) do
    ~H"""
    <span class={["text-sm/7 font-semibold text-oat-700", @class]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  @doc """
  Prose-width body text.
  """
  attr :class, :string, default: ""
  attr :size, :string, default: "default"
  slot :inner_block, required: true

  def m_body(assigns) do
    ~H"""
    <p class={[
      "leading-relaxed",
      body_size(@size),
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  defp body_size("large"), do: "text-lg/8 sm:text-xl/8 text-oat-700"
  defp body_size("default"), do: "text-base/7 sm:text-lg/8 text-oat-700"
  defp body_size("small"), do: "text-sm/6 text-oat-600"
  defp body_size(_), do: "text-base/7 sm:text-lg/8 text-oat-700"

  # ─── Interactive ─────────────────────────────────────────────────

  @doc """
  Pill-shaped CTA button. Supports `href` for links or renders as button.
  Variants: primary, secondary, ghost.
  """
  attr :variant, :string, default: "primary"
  attr :size, :string, default: "default"
  attr :href, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def m_button(assigns) do
    assigns =
      assign(assigns, :classes, [
        "inline-flex items-center justify-center font-medium rounded-full transition-all duration-200",
        button_variant(assigns.variant),
        button_size(assigns.size),
        assigns.class
      ])

    if assigns.href do
      ~H"""
      <a href={@href} class={@classes}>
        <%= render_slot(@inner_block) %>
      </a>
      """
    else
      ~H"""
      <button class={@classes}>
        <%= render_slot(@inner_block) %>
      </button>
      """
    end
  end

  defp button_variant("primary"), do: "bg-oat-950 text-white hover:bg-oat-800"

  defp button_variant("secondary"),
    do: "bg-oat-950/10 text-oat-950 hover:bg-oat-950/15"

  defp button_variant("ghost"), do: "text-oat-700 hover:text-oat-950 hover:bg-oat-100"
  defp button_variant(_), do: button_variant("primary")

  defp button_size("sm"), do: "px-3 py-1 text-sm/7"
  defp button_size("default"), do: "px-4 py-2 text-sm/7"
  defp button_size("lg"), do: "px-4 py-2 text-base/7"
  defp button_size(_), do: button_size("default")

  @doc """
  Wrapper that adds `.scroll-reveal` class for intersection observer animation.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def scroll_reveal(assigns) do
    ~H"""
    <div class={["scroll-reveal", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  # ─── Why Wombie Specific ─────────────────────────────────────────

  @doc """
  White card with icon, title, and description.
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :class, :string, default: ""

  def story_card(assigns) do
    ~H"""
    <div class={["scroll-reveal rounded-2xl bg-oat-50 p-6", @class]}>
      <div class="text-2xl mb-3"><%= @icon %></div>
      <h3 class="font-familjen font-semibold text-oat-950 text-lg mb-2"><%= @title %></h3>
      <p class="text-sm/6 text-oat-600 leading-relaxed"><%= @description %></p>
    </div>
    """
  end

  @doc """
  Crossed-out anti-feature declaration.
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :class, :string, default: ""

  def anti_pattern_item(assigns) do
    ~H"""
    <div class={["scroll-reveal flex gap-4 items-start", @class]}>
      <span class="text-xl flex-shrink-0 mt-0.5"><%= @icon %></span>
      <div>
        <p class="font-familjen font-semibold text-oat-950 anti-strike"><%= @title %></p>
        <p class="text-sm/6 text-oat-600 mt-1"><%= @description %></p>
      </div>
    </div>
    """
  end

  @doc """
  Large metric display with context text.
  """
  attr :metric, :string, required: true
  attr :context, :string, required: true
  attr :class, :string, default: ""

  def stat_block(assigns) do
    ~H"""
    <div class={["text-center", @class]}>
      <p class="font-familjen text-3xl sm:text-4xl lg:text-5xl text-oat-950 tracking-[-0.03em]">
        <%= @metric %>
      </p>
      <p class="mt-3 text-oat-600 text-base/7 sm:text-lg/8"><%= @context %></p>
    </div>
    """
  end

  @doc """
  Numbered step card with icon, title, and description.
  """
  attr :number, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :class, :string, default: ""

  def step_card(assigns) do
    ~H"""
    <div class={["scroll-reveal text-center", @class]}>
      <div class="inline-flex items-center justify-center w-14 h-14 rounded-full bg-oat-100 text-2xl mb-4">
        <%= @icon %>
      </div>
      <div class="text-sm/7 font-semibold text-oat-700 mb-2">
        Step <%= @number %>
      </div>
      <h3 class="font-familjen font-semibold text-xl text-oat-950 mb-2"><%= @title %></h3>
      <p class="text-sm/6 text-oat-600 leading-relaxed max-w-xs mx-auto"><%= @description %></p>
    </div>
    """
  end

  @doc """
  SVG concentric circles diagram for the privacy model.
  Indigo center (private) to amber outer ring (open).
  """
  attr :class, :string, default: ""

  def privacy_circles(assigns) do
    ~H"""
    <div class={["privacy-circles flex justify-center", @class]}>
      <svg viewBox="0 0 400 400" class="w-64 h-64 sm:w-80 sm:h-80 lg:w-96 lg:h-96" role="img" aria-label="Concentric privacy circles: private at center, expanding to open">
        <!-- Open (outermost) -->
        <circle cx="200" cy="200" r="180" fill="none" stroke="#D97706" stroke-width="2" opacity="0.3" />
        <circle cx="200" cy="200" r="180" fill="#FEF3C7" opacity="0.15" />
        <!-- Extended -->
        <circle cx="200" cy="200" r="130" fill="none" stroke="#B4B3A3" stroke-width="2" opacity="0.4" />
        <circle cx="200" cy="200" r="130" fill="#EBEAE3" opacity="0.3" />
        <!-- Close friends -->
        <circle cx="200" cy="200" r="80" fill="none" stroke="#6366F1" stroke-width="2" opacity="0.5" />
        <circle cx="200" cy="200" r="80" fill="#E0E7FF" opacity="0.4" />
        <!-- Private (center) -->
        <circle cx="200" cy="200" r="35" fill="#6366F1" opacity="0.85" />
        <text x="200" y="205" text-anchor="middle" fill="white" font-size="12" font-weight="600">You</text>
        <!-- Labels -->
        <text x="200" y="135" text-anchor="middle" fill="#6F6E5F" font-size="11" font-weight="500">Close Friends</text>
        <text x="200" y="80" text-anchor="middle" fill="#8C8B78" font-size="11" font-weight="500">Extended Circle</text>
        <text x="200" y="30" text-anchor="middle" fill="#B4B3A3" font-size="11" font-weight="500">Open</text>
      </svg>
    </div>
    """
  end
end
