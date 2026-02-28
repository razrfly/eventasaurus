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

  @spec marketing_nav(map()) :: Phoenix.LiveView.Rendered.t()
  def marketing_nav(assigns) do
    ~H"""
    <header id="marketing-nav" phx-hook="MobileNav" class={[
      "sticky top-0 z-50 border-b border-oat-200/60 bg-oat-100",
      @class
    ]}>
      <div class="mx-auto max-w-2xl md:max-w-3xl lg:max-w-7xl px-6 lg:px-10 py-4 flex items-center justify-between">
        <.logo class="text-2xl" text_color="text-oat-950" />
        <div class="hidden md:flex items-center gap-8">
          <a href="/about" class="text-sm/7 font-medium text-oat-950 hover:text-oat-700 transition-colors">
            About
          </a>
          <a href="/our-story" class="text-sm/7 font-medium text-oat-950 hover:text-oat-700 transition-colors">
            Our Story
          </a>
          <.m_button href="/invite-only" variant="primary" size="sm">
            Get Started
          </.m_button>
        </div>
        <%!-- Mobile: hamburger button --%>
        <button data-mobile-toggle
                type="button"
                aria-controls="marketing-mobile-menu"
                aria-expanded="false"
                class="md:hidden inline-flex items-center justify-center rounded-lg p-2 text-oat-950 hover:bg-oat-950/10 transition-colors"
                aria-label="Open menu">
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"/>
          </svg>
        </button>
      </div>
      <%!-- Mobile overlay panel --%>
      <div data-mobile-menu
           id="marketing-mobile-menu"
           role="dialog"
           aria-modal="true"
           aria-hidden="true"
           class="hidden fixed inset-0 z-50 bg-oat-50/95 backdrop-blur-sm flex flex-col p-6">
        <div class="flex items-center justify-between mb-10">
          <.logo class="text-xl" text_color="text-oat-950" />
          <button data-mobile-close
                  type="button"
                  class="rounded-lg p-2 text-oat-950 hover:bg-oat-950/10 transition-colors"
                  aria-label="Close menu">
            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>
        <nav class="flex flex-col gap-6 text-xl font-medium text-oat-950">
          <a href="/about" class="hover:text-oat-600 transition-colors">About</a>
          <a href="/our-story" class="hover:text-oat-600 transition-colors">Our Story</a>
        </nav>
        <div class="mt-auto">
          <a href="/invite-only"
             class="block w-full rounded-full bg-oat-950 py-3.5 text-center text-sm font-semibold text-white hover:bg-oat-800 transition-colors">
            Get Started
          </a>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Dark olive footer for marketing pages.
  """
  @spec marketing_footer(map()) :: Phoenix.LiveView.Rendered.t()
  def marketing_footer(assigns) do
    ~H"""
    <footer class="bg-oat-950 text-white">
      <div class="mx-auto max-w-2xl md:max-w-3xl lg:max-w-7xl px-6 lg:px-10 py-16">
        <div class="grid grid-cols-1 gap-12 lg:grid-cols-3">
          <%!-- Logo + tagline --%>
          <div>
            <.logo class="text-lg" text_color="text-white" />
            <p class="mt-2 text-sm text-oat-400 max-w-xs">
              Real-world connection, starting with your closest friends.
            </p>
          </div>
          <%!-- Newsletter form --%>
          <div>
            <p class="text-sm font-semibold text-white">Stay in the loop</p>
            <p class="mt-1 text-sm text-oat-400">Early access updates. No spam, ever.</p>
            <form action="/invite-only" method="get"
                  class="mt-4 flex items-center border-b border-white/20 py-2 focus-within:border-white transition-colors">
              <label for="newsletter_email" class="sr-only">Email address</label>
              <input type="email" name="email" id="newsletter_email" placeholder="Your email"
                     class="flex-1 bg-transparent text-sm text-white placeholder-oat-500 focus:outline-none" />
              <button type="submit" aria-label="Subscribe"
                      class="ml-2 flex size-7 items-center justify-center rounded-full hover:bg-white/10 transition-colors">
                <svg class="h-4 w-4 text-white" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3"/>
                </svg>
              </button>
            </form>
          </div>
          <%!-- Link columns --%>
          <div class="flex gap-12 text-sm">
            <div class="space-y-3">
              <p class="font-medium text-white">Product</p>
              <a href="/about" class="block text-oat-400 hover:text-white transition-colors">About</a>
              <a href="/our-story" class="block text-oat-400 hover:text-white transition-colors">Our Story</a>
              <a href="/whats-new" class="block text-oat-400 hover:text-white transition-colors">What's New</a>
            </div>
            <div class="space-y-3">
              <p class="font-medium text-white">Legal</p>
              <a href="/privacy" class="block text-oat-400 hover:text-white transition-colors">Privacy</a>
              <a href="/terms" class="block text-oat-400 hover:text-white transition-colors">Terms</a>
              <a href="/your-data" class="block text-oat-400 hover:text-white transition-colors">Your Data</a>
            </div>
          </div>
        </div>
        <%!-- Bottom bar with copyright + social icons --%>
        <div class="mt-12 pt-8 border-t border-white/10 text-sm text-oat-500 flex items-center justify-between flex-wrap gap-4">
          <span>&copy; <%= Date.utc_today().year %> Wombie. All rights reserved.</span>
          <div class="flex items-center gap-5">
            <a href="https://twitter.com/wombieapp" target="_blank" rel="noopener noreferrer" aria-label="X (Twitter)"
               class="text-oat-500 hover:text-white transition-colors">
              <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.74l7.73-8.835L1.254 2.25H8.08l4.26 5.632zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
              </svg>
            </a>
            <a href="https://instagram.com/wombieapp" target="_blank" rel="noopener noreferrer" aria-label="Instagram"
               class="text-oat-500 hover:text-white transition-colors">
              <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/>
              </svg>
            </a>
          </div>
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
  Announcement badge — small pill above the hero headline.
  """
  attr :text, :string, required: true
  attr :cta, :string, default: "Join the waitlist"
  attr :href, :string, default: "/invite-only"

  @spec m_announcement_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def m_announcement_badge(assigns) do
    ~H"""
    <a href={@href}
       class="group inline-flex items-center gap-x-3 rounded-full bg-oat-950/[0.05] px-3 py-1 text-sm/6 text-oat-950 hover:bg-oat-950/[0.08] transition-colors max-sm:flex-col max-sm:rounded-md max-sm:px-3.5 max-sm:py-2">
      <span class="text-pretty sm:truncate"><%= @text %></span>
      <span class="h-3 w-px bg-oat-950/20 max-sm:hidden"></span>
      <span class="inline-flex shrink-0 items-center gap-1.5 font-semibold">
        <%= @cta %>
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5"/>
        </svg>
      </span>
    </a>
    """
  end

  @doc """
  Single testimonial card with avatar initials, quote, name, and byline.
  """
  attr :quote, :string, required: true
  attr :name, :string, required: true
  attr :byline, :string, required: true
  attr :initials, :string, required: true
  attr :bg, :string, default: "bg-oat-300"

  @spec testimonial_item(map()) :: Phoenix.LiveView.Rendered.t()
  def testimonial_item(assigns) do
    ~H"""
    <figure class="scroll-reveal flex flex-col justify-between gap-8 rounded-md bg-oat-950/[0.025] p-6 text-sm/7 text-oat-950">
      <blockquote>
        <p class="text-oat-700">"<%= @quote %>"</p>
      </blockquote>
      <figcaption class="flex items-center gap-4">
        <div class={["flex size-11 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-oat-950 ring-1 ring-black/[0.05]", @bg]}>
          <%= @initials %>
        </div>
        <div>
          <p class="font-semibold"><%= @name %></p>
          <p class="text-oat-600"><%= @byline %></p>
        </div>
      </figcaption>
    </figure>
    """
  end

  @doc """
  Two-column FAQ section with a label/heading on the left and accordion items on the right.
  """
  slot :inner_block, required: true

  @spec faq_section(map()) :: Phoenix.LiveView.Rendered.t()
  def faq_section(assigns) do
    ~H"""
    <section class="py-16 bg-oat-100">
      <.m_container class="grid grid-cols-1 gap-x-8 gap-y-10 lg:grid-cols-2">
        <div class="flex flex-col gap-4">
          <.m_label>Questions & Answers</.m_label>
          <.m_heading size="default">Everything you need to know</.m_heading>
          <.m_body>
            Can't find the answer?
            <a href="/invite-only" class="font-semibold underline hover:text-oat-700">Join the waitlist</a>
            and we'll reach out.
          </.m_body>
        </div>
        <div class="divide-y divide-oat-950/10 border-y border-oat-950/10">
          <%= render_slot(@inner_block) %>
        </div>
      </.m_container>
    </section>
    """
  end

  @doc """
  Single FAQ accordion item using native <details>/<summary>.
  """
  attr :question, :string, required: true
  slot :inner_block, required: true

  @spec faq_item(map()) :: Phoenix.LiveView.Rendered.t()
  def faq_item(assigns) do
    ~H"""
    <details class="faq-item">
      <summary>
        <span><%= @question %></span>
        <span class="shrink-0 ml-2">
          <svg class="faq-icon-plus h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15"/>
          </svg>
          <svg class="faq-icon-minus h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15"/>
          </svg>
        </span>
      </summary>
      <div class="faq-body"><%= render_slot(@inner_block) %></div>
    </details>
    """
  end

  @doc """
  SVG concentric circles diagram for the privacy model.
  Indigo center (private) to amber outer ring (open).
  """
  attr :class, :string, default: ""

  def privacy_circles(assigns) do
    ~H"""
    <div id="privacy-circles" phx-hook="PrivacyCircles"
         class={["privacy-circles flex flex-col items-center gap-4", @class]}>
      <svg viewBox="0 0 400 400" class="w-64 h-64 sm:w-80 sm:h-80 lg:w-96 lg:h-96"
           role="img" aria-label="Interactive privacy circles">
        <%!-- Open (outermost) --%>
        <g data-ring="open" class="ring-open cursor-pointer" role="button" tabindex="0">
          <circle cx="200" cy="200" r="180" fill="none" stroke="#D97706" stroke-width="2" opacity="0.3" />
          <circle cx="200" cy="200" r="180" fill="#FEF3C7" opacity="0.15" />
          <circle cx="200" cy="200" r="190" fill="transparent" />
          <text x="200" y="30" text-anchor="middle" fill="#B4B3A3" font-size="11" font-weight="500">Open</text>
        </g>
        <%!-- Extended --%>
        <g data-ring="extended" class="ring-extended cursor-pointer" role="button" tabindex="0">
          <circle cx="200" cy="200" r="130" fill="none" stroke="#B4B3A3" stroke-width="2" opacity="0.4" />
          <circle cx="200" cy="200" r="130" fill="#EBEAE3" opacity="0.3" />
          <circle cx="200" cy="200" r="140" fill="transparent" />
          <text x="200" y="80" text-anchor="middle" fill="#8C8B78" font-size="11" font-weight="500">Extended Circle</text>
        </g>
        <%!-- Close friends --%>
        <g data-ring="friends" class="ring-friends cursor-pointer" role="button" tabindex="0">
          <circle cx="200" cy="200" r="80" fill="none" stroke="#6366F1" stroke-width="2" opacity="0.5" />
          <circle cx="200" cy="200" r="80" fill="#E0E7FF" opacity="0.4" />
          <circle cx="200" cy="200" r="90" fill="transparent" />
          <text x="200" y="135" text-anchor="middle" fill="#6F6E5F" font-size="11" font-weight="500">Close Friends</text>
        </g>
        <%!-- Private (center) --%>
        <g data-ring="private" class="ring-private cursor-pointer" role="button" tabindex="0">
          <circle cx="200" cy="200" r="35" fill="#6366F1" opacity="0.85" />
          <text x="200" y="205" text-anchor="middle" fill="white" font-size="12" font-weight="600">You</text>
        </g>
      </svg>
      <%!-- Scenario description — updated by PrivacyCircles hook --%>
      <p id="privacy-scenario"
         class="min-h-[3rem] max-w-xs text-center text-sm/6 text-oat-600 transition-all duration-300">
        Tap a ring to see how it works.
      </p>
    </div>
    """
  end
end
