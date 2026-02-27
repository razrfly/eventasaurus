defmodule EventasaurusWeb.OatmealComponents do
  @moduledoc """
  Faithful Phoenix/HEEx translations of the Oatmeal olive-familjen theme components.

  These are 1:1 ports of the React components from `tmp/oatmeal-olive-familjen/`.
  No customization — just the theme as-is.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import EventasaurusWeb.CoreComponents, only: [logo: 1]

  # ═══════════════════════════════════════════════════════════════════
  # ELEMENT PRIMITIVES
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Responsive max-width container with responsive padding.
  Source: elements/container.tsx
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_container(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_container(assigns) do
    ~H"""
    <div class={["mx-auto w-full max-w-2xl px-6 md:max-w-3xl lg:max-w-7xl lg:px-10", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Display heading (h1). Large, tracked tight.
  Source: elements/heading.tsx
  """
  attr :class, :string, default: ""
  attr :color, :string, default: "dark"
  slot :inner_block, required: true

  @spec oat_heading(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_heading(assigns) do
    ~H"""
    <h1 class={[
      "font-familjen text-5xl/[3rem] tracking-[-0.04em] text-balance sm:text-[4rem]/[4rem]",
      heading_color(@color),
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </h1>
    """
  end

  defp heading_color("dark"), do: "text-oat-950"
  defp heading_color("light"), do: "text-white"
  defp heading_color(_), do: "text-oat-950"

  @doc """
  Subheading (h2). Medium weight, tight tracking.
  Source: elements/subheading.tsx
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_subheading(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_subheading(assigns) do
    ~H"""
    <h2 class={[
      "font-familjen text-3xl/9 font-medium tracking-[-0.03em] text-pretty text-oat-950 sm:text-[2.5rem]/10",
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </h2>
    """
  end

  @doc """
  Body text wrapper.
  Source: elements/text.tsx
  """
  attr :class, :string, default: ""
  attr :size, :string, default: "md"
  slot :inner_block, required: true

  @spec oat_text(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_text(assigns) do
    ~H"""
    <div class={[
      text_size(@size),
      "text-oat-700",
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp text_size("md"), do: "text-base/7"
  defp text_size("lg"), do: "text-lg/8"
  defp text_size(_), do: "text-base/7"

  @doc """
  Small eyebrow text above headings.
  Source: elements/eyebrow.tsx
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_eyebrow(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_eyebrow(assigns) do
    ~H"""
    <div class={["text-sm/7 font-semibold text-oat-700", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Primary solid button. Rounded-full pill shape.
  Source: elements/button.tsx — Button / ButtonLink
  """
  attr :href, :string, default: nil
  attr :size, :string, default: "md"
  attr :color, :string, default: "dark"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_button(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_button(assigns) do
    assigns =
      assign(assigns, :classes, [
        "inline-flex shrink-0 items-center justify-center gap-1 rounded-full text-sm/7 font-medium",
        oat_button_color(assigns.color),
        oat_button_size(assigns.size),
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
      <button type="button" class={@classes}>
        <%= render_slot(@inner_block) %>
      </button>
      """
    end
  end

  defp oat_button_color("dark"), do: "bg-oat-950 text-white hover:bg-oat-800"
  defp oat_button_color("light"), do: "bg-white text-oat-950 hover:bg-oat-100"
  defp oat_button_color(_), do: oat_button_color("dark")

  defp oat_button_size("md"), do: "px-3 py-1"
  defp oat_button_size("lg"), do: "px-4 py-2"
  defp oat_button_size(_), do: oat_button_size("md")

  @doc """
  Soft (low-contrast) button.
  Source: elements/button.tsx — SoftButton / SoftButtonLink
  """
  attr :href, :string, default: nil
  attr :size, :string, default: "md"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_soft_button(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_soft_button(assigns) do
    assigns =
      assign(assigns, :classes, [
        "inline-flex shrink-0 items-center justify-center gap-1 rounded-full bg-oat-950/10 text-sm/7 font-medium text-oat-950 hover:bg-oat-950/15",
        oat_button_size(assigns.size),
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
      <button type="button" class={@classes}>
        <%= render_slot(@inner_block) %>
      </button>
      """
    end
  end

  @doc """
  Styled link with arrow icon.
  Source: elements/link.tsx
  """
  attr :href, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_link(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_link(assigns) do
    ~H"""
    <a href={@href} class={["inline-flex items-center gap-2 text-sm/7 font-medium text-oat-950", @class]}>
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Base Section wrapper
  # Source: elements/section.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Base section wrapper with optional eyebrow + headline + subheadline header block.
  Source: elements/section.tsx
  """
  attr :eyebrow, :string, default: nil
  attr :headline, :string, default: nil
  attr :subheadline, :string, default: nil
  attr :class, :string, default: ""
  attr :id, :string, default: nil
  slot :cta
  slot :inner_block, required: true

  @spec oat_section(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_section(assigns) do
    ~H"""
    <section id={@id} class={["py-16", @class]}>
      <.oat_container class="flex flex-col gap-10 sm:gap-16">
        <%= if @headline do %>
          <div class="flex max-w-2xl flex-col gap-6">
            <div class="flex flex-col gap-2">
              <%= if @eyebrow do %>
                <.oat_eyebrow><%= @eyebrow %></.oat_eyebrow>
              <% end %>
              <.oat_subheading><%= @headline %></.oat_subheading>
            </div>
            <%= if @subheadline do %>
              <.oat_text class="text-pretty"><%= @subheadline %></.oat_text>
            <% end %>
            <%= render_slot(@cta) %>
          </div>
        <% end %>
        <div>
          <%= render_slot(@inner_block) %>
        </div>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Hero Simple Centered
  # Source: sections/hero-simple-centered.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Centered hero with large heading, subheadline, and optional CTA.
  Source: sections/hero-simple-centered.tsx
  """
  attr :class, :string, default: ""
  attr :eyebrow, :string, default: nil
  slot :headline, required: true
  slot :subheadline, required: true
  slot :cta

  @spec hero_simple_centered(map()) :: Phoenix.LiveView.Rendered.t()
  def hero_simple_centered(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <.oat_container class="flex flex-col items-center gap-6">
        <%= if @eyebrow do %>
          <.oat_eyebrow><%= @eyebrow %></.oat_eyebrow>
        <% end %>
        <.oat_heading class="max-w-5xl text-center">
          <%= render_slot(@headline) %>
        </.oat_heading>
        <.oat_text size="lg" class="flex max-w-xl flex-col gap-4 text-center">
          <%= render_slot(@subheadline) %>
        </.oat_text>
        <%= render_slot(@cta) %>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Features Three Column
  # Source: sections/features-three-column.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual feature item with icon, headline, and description.
  Source: sections/features-three-column.tsx — Feature
  """
  attr :icon, :string, default: nil
  attr :headline, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_feature(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_feature(assigns) do
    ~H"""
    <div class={["flex flex-col gap-2 text-sm/7", @class]}>
      <div class="flex items-start gap-3 text-oat-950">
        <%= if @icon do %>
          <div class="flex h-[1lh] items-center text-lg"><%= @icon %></div>
        <% end %>
        <h3 class="font-semibold"><%= @headline %></h3>
      </div>
      <div class="flex flex-col gap-4 text-oat-700">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  @doc """
  Three-column feature grid with Section header.
  Source: sections/features-three-column.tsx — FeaturesThreeColumn
  """
  attr :eyebrow, :string, default: nil
  attr :headline, :string, default: nil
  attr :subheadline, :string, default: nil
  attr :class, :string, default: ""
  slot :features, required: true

  @spec features_three_column(map()) :: Phoenix.LiveView.Rendered.t()
  def features_three_column(assigns) do
    ~H"""
    <.oat_section eyebrow={@eyebrow} headline={@headline} subheadline={@subheadline} class={@class}>
      <div class="grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-3">
        <%= render_slot(@features) %>
      </div>
    </.oat_section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Testimonial with Large Quote
  # Source: sections/testimonial-with-large-quote.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Single large quote testimonial with attribution.
  Source: sections/testimonial-with-large-quote.tsx
  """
  attr :name, :string, required: true
  attr :byline, :string, required: true
  attr :avatar, :string, default: nil
  attr :class, :string, default: ""
  slot :quote, required: true

  @spec testimonial_large_quote(map()) :: Phoenix.LiveView.Rendered.t()
  def testimonial_large_quote(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <.oat_container>
        <figure class="text-oat-950">
          <blockquote class="mx-auto flex max-w-[60rem] flex-col gap-4 text-center font-familjen text-3xl/10 font-medium tracking-tight text-pretty sm:text-5xl/[3.5rem]">
            <p>
              <span>&ldquo;</span><%= render_slot(@quote) %><span>&rdquo;</span>
            </p>
          </blockquote>
          <figcaption class="mt-16 flex flex-col items-center">
            <%= if @avatar do %>
              <div class="flex size-12 overflow-hidden rounded-full outline -outline-offset-1 outline-black/5">
                <img src={@avatar} alt={@name} class="size-full object-cover" />
              </div>
            <% end %>
            <p class="mt-4 text-center text-sm/6 font-semibold"><%= @name %></p>
            <p class="text-center text-sm/6 text-oat-700"><%= @byline %></p>
          </figcaption>
        </figure>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Stats Three Column with Description
  # Source: sections/stats-three-column-with-description.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual stat card.
  Source: sections/stats-three-column-with-description.tsx — Stat
  """
  attr :stat, :string, required: true
  attr :text, :string, required: true
  attr :class, :string, default: ""

  @spec oat_stat(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_stat(assigns) do
    ~H"""
    <div class={["rounded-xl bg-oat-950/[0.025] p-6", @class]}>
      <div class="text-2xl/10 tracking-tight text-oat-950"><%= @stat %></div>
      <p class="mt-2 text-sm/7 text-oat-700"><%= @text %></p>
    </div>
    """
  end

  @doc """
  Three-column stats with heading and description.
  Source: sections/stats-three-column-with-description.tsx
  """
  attr :class, :string, default: ""
  slot :heading, required: true
  slot :description, required: true
  slot :inner_block, required: true

  @spec stats_three_column(map()) :: Phoenix.LiveView.Rendered.t()
  def stats_three_column(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <.oat_container>
        <div class="relative flex flex-col gap-10 sm:gap-16">
          <hr class="absolute inset-x-0 -top-16 border-t border-oat-950/10" />
          <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
            <.oat_subheading><%= render_slot(@heading) %></.oat_subheading>
            <div class="flex max-w-xl flex-col gap-4 text-base/7 text-oat-700">
              <%= render_slot(@description) %>
            </div>
          </div>
          <div class="grid grid-cols-1 gap-2 md:grid-cols-3">
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: FAQs Accordion
  # Source: sections/faqs-accordion.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual FAQ item with toggle disclosure.
  Source: sections/faqs-accordion.tsx — Faq
  """
  attr :question, :string, required: true
  attr :id, :string, required: true
  slot :answer, required: true

  @spec oat_faq(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_faq(assigns) do
    ~H"""
    <div id={@id} phx-hook="FaqToggle">
      <button
        type="button"
        class="flex w-full items-start justify-between gap-6 py-4 text-left text-base/7 text-oat-950"
        aria-expanded="false"
        aria-controls={"#{@id}-answer"}
        phx-click={toggle_faq(@id)}
      >
        <%= @question %>
        <svg
          class="h-[1lh] w-4 shrink-0 transition-transform duration-200"
          viewBox="0 0 16 16"
          fill="currentColor"
          aria-hidden="true"
        >
          <%!-- Plus icon (vertical bar hidden when expanded via parent rotate) --%>
          <path d="M7.25 1v14h1.5V1z" class="faq-plus-bar" />
          <path d="M1 7.25h14v1.5H1z" />
        </svg>
      </button>
      <div
        id={"#{@id}-answer"}
        class="grid grid-rows-[0fr] transition-[grid-template-rows] duration-200 ease-out"
      >
        <div class="overflow-hidden">
          <div class="-mt-2 flex flex-col gap-2 pr-12 pb-4 text-sm/7 text-oat-700">
            <%= render_slot(@answer) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_faq(id) do
    %JS{}
    |> JS.toggle_attribute({"aria-expanded", "true", "false"},
      to: "##{id} button"
    )
    |> JS.toggle_class("grid-rows-[1fr]", to: "##{id}-answer")
    |> JS.toggle_class("[&_.faq-plus-bar]:scale-0",
      to: "##{id}"
    )
  end

  @doc """
  FAQ accordion section.
  Source: sections/faqs-accordion.tsx — FAQsAccordion
  """
  attr :headline, :string, default: nil
  attr :subheadline, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec faqs_accordion(map()) :: Phoenix.LiveView.Rendered.t()
  def faqs_accordion(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <div class="mx-auto flex max-w-3xl flex-col gap-6 px-6 lg:max-w-5xl lg:px-10">
        <div class="flex flex-col gap-6">
          <%= if @headline do %>
            <.oat_subheading><%= @headline %></.oat_subheading>
          <% end %>
          <%= if @subheadline do %>
            <.oat_text class="flex flex-col gap-4 text-pretty"><%= @subheadline %></.oat_text>
          <% end %>
        </div>
        <div class="divide-y divide-oat-950/10 border-y border-oat-950/10">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Call To Action Simple Centered
  # Source: sections/call-to-action-simple-centered.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Centered CTA with headline, subheadline, and button.
  Source: sections/call-to-action-simple-centered.tsx
  """
  attr :class, :string, default: ""
  slot :headline, required: true
  slot :subheadline
  slot :cta

  @spec cta_simple_centered(map()) :: Phoenix.LiveView.Rendered.t()
  def cta_simple_centered(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <.oat_container class="flex flex-col items-center gap-10">
        <div class="flex flex-col gap-6">
          <.oat_subheading class="max-w-4xl text-center">
            <%= render_slot(@headline) %>
          </.oat_subheading>
          <%= for sub <- @subheadline do %>
            <.oat_text class="flex max-w-3xl flex-col gap-4 text-center text-pretty">
              <%= render_slot(sub) %>
            </.oat_text>
          <% end %>
        </div>
        <%= render_slot(@cta) %>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Navbar
  # Source: sections/navbar-with-logo-actions-and-left-aligned-links.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Sticky navbar with logo, left-aligned links, and actions.
  Source: sections/navbar-with-logo-actions-and-left-aligned-links.tsx
  """
  attr :class, :string, default: ""
  slot :links
  slot :actions

  @spec oat_navbar(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_navbar(assigns) do
    ~H"""
    <header class={["sticky top-0 z-10 bg-oat-100", @class]}>
      <nav>
        <div class="mx-auto flex h-[5.25rem] max-w-7xl items-center gap-4 px-6 lg:px-10">
          <div class="flex flex-1 items-center gap-12">
            <.logo class="text-2xl" text_color="text-oat-950" />
            <div class="flex gap-8 max-lg:hidden">
              <%= render_slot(@links) %>
            </div>
          </div>
          <div class="flex flex-1 items-center justify-end gap-4">
            <div class="flex shrink-0 items-center gap-5">
              <%= render_slot(@actions) %>
            </div>
          </div>
        </div>
      </nav>
    </header>
    """
  end

  @doc """
  Individual navbar link.
  Source: sections/navbar-with-logo-actions-and-left-aligned-links.tsx — NavbarLink
  """
  attr :href, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_nav_link(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_nav_link(assigns) do
    ~H"""
    <a href={@href} class={["text-sm/7 font-medium text-oat-950", @class]}>
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Footer with Links and Social Icons
  # Source: sections/footer-with-links-and-social-icons.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Simple centered footer with links and fineprint.
  Source: sections/footer-with-links-and-social-icons.tsx
  """
  attr :class, :string, default: ""
  slot :links, required: true
  slot :fineprint, required: true

  @spec oat_footer(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_footer(assigns) do
    ~H"""
    <footer class={["pt-16", @class]}>
      <div class="bg-oat-950/[0.025] py-16 text-oat-950">
        <.oat_container class="flex flex-col gap-10 text-center text-sm/7">
          <div class="flex flex-col gap-6">
            <nav>
              <ul class="flex flex-wrap items-center justify-center gap-x-10 gap-y-2">
                <%= render_slot(@links) %>
              </ul>
            </nav>
          </div>
          <div class="text-oat-600">
            <%= render_slot(@fineprint) %>
          </div>
        </.oat_container>
      </div>
    </footer>
    """
  end

  @doc """
  Individual footer link.
  Source: sections/footer-with-links-and-social-icons.tsx — FooterLink
  """
  attr :href, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_footer_link(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_footer_link(assigns) do
    ~H"""
    <li class={["text-oat-700", @class]}>
      <a href={@href}><%= render_slot(@inner_block) %></a>
    </li>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Hero Centered with Demo
  # Source: home-03/sections/hero-centered-with-demo.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Hero section with centered text above and a full-width demo block below.
  Source: home-03/sections/hero-centered-with-demo.tsx
  """
  attr :class, :string, default: ""
  slot :eyebrow
  slot :headline, required: true
  slot :subheadline
  slot :cta
  slot :demo
  slot :footer

  @spec hero_centered_with_demo(map()) :: Phoenix.LiveView.Rendered.t()
  def hero_centered_with_demo(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <.oat_container class="flex flex-col gap-16">
        <div class="flex flex-col items-center gap-8">
          <div class="flex flex-col items-center gap-6">
            <%= render_slot(@eyebrow) %>
            <.oat_heading class="max-w-4xl text-center">
              <%= render_slot(@headline) %>
            </.oat_heading>
            <%= render_slot(@subheadline) %>
            <%= render_slot(@cta) %>
          </div>
          <%= render_slot(@demo) %>
        </div>
        <%= render_slot(@footer) %>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Features Stacked Alternating
  # Source: home-03/sections/features-stacked-alternating-with-demos.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual alternating feature with text on one side and demo on the other.
  Text/demo sides alternate on desktop using group-even CSS.
  Source: home-03/sections/features-stacked-alternating-with-demos.tsx — Feature
  """
  attr :class, :string, default: ""
  slot :headline, required: true
  slot :subheadline
  slot :cta
  slot :demo

  @spec oat_alternating_feature(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_alternating_feature(assigns) do
    ~H"""
    <div class={[
      "group grid grid-flow-dense grid-cols-1 gap-2 rounded-lg bg-oat-950/[0.025] p-2 lg:grid-cols-2",
      @class
    ]}>
      <div class="flex flex-col justify-between gap-6 p-6 sm:p-10 lg:p-6 lg:group-even:col-start-2">
        <div class="flex flex-col gap-4">
          <h3 class="font-familjen text-xl/8 font-medium tracking-tight text-oat-950 sm:text-2xl/9">
            <%= render_slot(@headline) %>
          </h3>
          <div class="text-base/7 text-oat-700">
            <%= render_slot(@subheadline) %>
          </div>
        </div>
        <%= render_slot(@cta) %>
      </div>
      <div class="relative overflow-hidden rounded-sm lg:group-even:col-start-1">
        <%= render_slot(@demo) %>
      </div>
    </div>
    """
  end

  @doc """
  Stacked alternating features section with section header.
  Source: home-03/sections/features-stacked-alternating-with-demos.tsx
  """
  attr :eyebrow, :string, default: nil
  attr :headline, :string, default: nil
  attr :subheadline, :string, default: nil
  attr :id, :string, default: nil
  attr :class, :string, default: ""
  slot :features, required: true

  @spec features_stacked_alternating(map()) :: Phoenix.LiveView.Rendered.t()
  def features_stacked_alternating(assigns) do
    ~H"""
    <.oat_section id={@id} eyebrow={@eyebrow} headline={@headline} subheadline={@subheadline} class={@class}>
      <div class="grid grid-cols-1 gap-6">
        <%= render_slot(@features) %>
      </div>
    </.oat_section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Brands Cards Multi Column
  # Source: home-03/sections/brands-cards-multi-column.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual brand/community card with icon, text, and footnote.
  Source: home-03/sections/brands-cards-multi-column.tsx — BrandCard
  """
  attr :icon, :string, required: true
  attr :text, :string, required: true
  attr :footnote, :string, required: true
  attr :class, :string, default: ""

  @spec oat_brand_card(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_brand_card(assigns) do
    ~H"""
    <div class={["flex flex-col justify-between gap-6 rounded-xl bg-oat-950/[0.025] p-6", @class]}>
      <div class="flex flex-col items-start gap-2">
        <div class="flex h-8 shrink-0 items-center text-2xl"><%= @icon %></div>
        <p class="text-sm/7 text-oat-700"><%= @text %></p>
      </div>
      <p class="text-xs/6 text-oat-500"><%= @footnote %></p>
    </div>
    """
  end

  @doc """
  Multi-column brand/community cards section.
  Source: home-03/sections/brands-cards-multi-column.tsx
  """
  attr :eyebrow, :string, default: nil
  attr :headline, :string, default: nil
  attr :subheadline, :string, default: nil
  attr :id, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec brands_cards_multi_column(map()) :: Phoenix.LiveView.Rendered.t()
  def brands_cards_multi_column(assigns) do
    ~H"""
    <.oat_section id={@id} eyebrow={@eyebrow} headline={@headline} subheadline={@subheadline} class={@class}>
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 md:grid-cols-3">
        <%= render_slot(@inner_block) %>
      </div>
    </.oat_section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Testimonial Two Column with Large Photo
  # Source: home-03/sections/testimonial-two-column-with-large-photo.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Two-column testimonial with large photo on one side and quote on the other.
  Source: home-03/sections/testimonial-two-column-with-large-photo.tsx
  """
  attr :name, :string, required: true
  attr :byline, :string, required: true
  attr :class, :string, default: ""
  slot :quote, required: true
  slot :photo

  @spec testimonial_two_column_large_photo(map()) :: Phoenix.LiveView.Rendered.t()
  def testimonial_two_column_large_photo(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <.oat_container>
        <figure class="grid grid-cols-1 gap-x-2 rounded-xl bg-oat-950/[0.025] p-2 lg:grid-cols-2">
          <div class="flex flex-col items-start justify-between gap-10 p-6 sm:p-10">
            <blockquote class="testimonial-hanging relative flex flex-col gap-4 text-xl/8 text-oat-950 sm:text-2xl/9">
              <%= render_slot(@quote) %>
            </blockquote>
            <figcaption class="flex flex-col gap-1">
              <p class="text-sm/7 font-semibold text-oat-950"><%= @name %></p>
              <p class="text-sm/7 text-oat-700"><%= @byline %></p>
            </figcaption>
          </div>
          <div class="flex min-h-64 overflow-hidden rounded-sm">
            <%= render_slot(@photo) %>
          </div>
        </figure>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Stats with Graph
  # Source: home-03/sections/stats-with-graph.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual stat item with left border accent.
  Source: home-03/sections/stats-with-graph.tsx — Stat
  """
  attr :stat, :string, required: true
  attr :text, :string, required: true
  attr :class, :string, default: ""

  @spec oat_graph_stat(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_graph_stat(assigns) do
    ~H"""
    <div class={["border-l border-oat-950/20 pl-6", @class]}>
      <div class="font-familjen text-2xl/10 tracking-tight text-oat-950"><%= @stat %></div>
      <p class="mt-2 text-sm/7 text-oat-700"><%= @text %></p>
    </div>
    """
  end

  @doc """
  Stats section with a decorative SVG graph and stat items.
  Source: home-03/sections/stats-with-graph.tsx
  """
  attr :eyebrow, :string, default: nil
  attr :headline, :string, default: nil
  attr :subheadline, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec stats_with_graph(map()) :: Phoenix.LiveView.Rendered.t()
  def stats_with_graph(assigns) do
    clip_id = "stats-graph-clip-#{System.unique_integer([:positive])}"
    assigns = assign(assigns, :clip_id, clip_id)

    ~H"""
    <.oat_section eyebrow={@eyebrow} headline={@headline} subheadline={@subheadline} class={@class}>
      <div class="grid grid-cols-1 gap-10 lg:grid-cols-2">
        <%!-- Stats column --%>
        <div class="flex flex-col justify-center gap-8">
          <%= render_slot(@inner_block) %>
        </div>
        <%!-- Decorative SVG graph --%>
        <div class="relative overflow-hidden rounded-lg bg-oat-950/[0.025] p-6 text-oat-950">
          <svg viewBox="0 0 400 220" class="w-full" aria-hidden="true">
            <defs>
              <clipPath id={@clip_id}>
                <rect width="400" height="220" />
              </clipPath>
            </defs>
            <%!-- Dashed vertical grid lines --%>
            <line x1="80" y1="10" x2="80" y2="190" stroke="currentColor" stroke-width="1" stroke-dasharray="4 4" stroke-opacity="0.15" />
            <line x1="160" y1="10" x2="160" y2="190" stroke="currentColor" stroke-width="1" stroke-dasharray="4 4" stroke-opacity="0.15" />
            <line x1="240" y1="10" x2="240" y2="190" stroke="currentColor" stroke-width="1" stroke-dasharray="4 4" stroke-opacity="0.15" />
            <line x1="320" y1="10" x2="320" y2="190" stroke="currentColor" stroke-width="1" stroke-dasharray="4 4" stroke-opacity="0.15" />
            <%!-- Horizontal baseline --%>
            <line x1="0" y1="190" x2="400" y2="190" stroke="currentColor" stroke-width="1" stroke-opacity="0.15" />
            <%!-- Area fill under curve --%>
            <path
              d="M 0 175 C 30 172, 55 162, 80 152 C 115 138, 135 128, 160 112 C 190 94, 210 82, 240 64 C 270 46, 295 30, 320 20 C 348 10, 378 8, 400 7 L 400 190 L 0 190 Z"
              fill="currentColor"
              fill-opacity="0.06"
              clip-path={"url(##{@clip_id})"}
            />
            <%!-- Bezier curve line --%>
            <path
              d="M 0 175 C 30 172, 55 162, 80 152 C 115 138, 135 128, 160 112 C 190 94, 210 82, 240 64 C 270 46, 295 30, 320 20 C 348 10, 378 8, 400 7"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-opacity="0.45"
              clip-path={"url(##{@clip_id})"}
            />
            <%!-- Data point dots --%>
            <circle cx="80" cy="152" r="4" fill="currentColor" fill-opacity="0.6" />
            <circle cx="160" cy="112" r="4" fill="currentColor" fill-opacity="0.6" />
            <circle cx="240" cy="64" r="4" fill="currentColor" fill-opacity="0.6" />
            <circle cx="320" cy="20" r="4" fill="currentColor" fill-opacity="0.6" />
            <%!-- X-axis month labels --%>
            <text x="80" y="210" text-anchor="middle" font-size="11" fill="currentColor" fill-opacity="0.4">Jan</text>
            <text x="160" y="210" text-anchor="middle" font-size="11" fill="currentColor" fill-opacity="0.4">Apr</text>
            <text x="240" y="210" text-anchor="middle" font-size="11" fill="currentColor" fill-opacity="0.4">Jul</text>
            <text x="320" y="210" text-anchor="middle" font-size="11" fill="currentColor" fill-opacity="0.4">Oct</text>
          </svg>
        </div>
      </div>
    </.oat_section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Hero Left-Aligned with Photo
  # Source: sections/hero-left-aligned-with-photo.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Left-aligned hero with text block above full-width photo/placeholder.
  Source: sections/hero-left-aligned-with-photo.tsx
  """
  attr :class, :string, default: ""
  slot :eyebrow
  slot :headline, required: true
  slot :subheadline, required: true
  slot :cta
  slot :photo
  slot :footer

  @spec hero_left_aligned_with_photo(map()) :: Phoenix.LiveView.Rendered.t()
  def hero_left_aligned_with_photo(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <.oat_container class="flex flex-col gap-16">
        <div class="flex flex-col gap-16">
          <div class="flex flex-col items-start gap-6">
            <%= render_slot(@eyebrow) %>
            <.oat_heading>
              <%= render_slot(@headline) %>
            </.oat_heading>
            <.oat_text size="lg" class="max-w-2xl text-pretty">
              <%= render_slot(@subheadline) %>
            </.oat_text>
            <%= render_slot(@cta) %>
          </div>
          <%= if @photo != [] do %>
            <div class="overflow-hidden rounded-xl outline -outline-offset-1 outline-black/5">
              <%= render_slot(@photo) %>
            </div>
          <% end %>
        </div>
        <%= render_slot(@footer) %>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Team Member Card
  # Source: sections/team-four-column-grid.tsx — TeamMember
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual team member card with photo, name, and byline.
  Source: sections/team-four-column-grid.tsx — TeamMember
  """
  attr :name, :string, required: true
  attr :byline, :string, required: true
  attr :class, :string, default: ""
  slot :photo, required: true

  @spec oat_team_member(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_team_member(assigns) do
    ~H"""
    <div class={["flex flex-col gap-3", @class]}>
      <div class="aspect-[4/5] overflow-hidden rounded-xl bg-oat-950/[0.025]">
        <%= render_slot(@photo) %>
      </div>
      <div class="flex flex-col gap-0.5">
        <p class="text-sm font-semibold text-oat-950"><%= @name %></p>
        <p class="text-sm text-oat-700"><%= @byline %></p>
      </div>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Team Four Column Grid
  # Source: sections/team-four-column-grid.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Four-column team grid with section header.
  Source: sections/team-four-column-grid.tsx
  """
  attr :headline, :string, default: nil
  attr :subheadline, :string, default: nil
  attr :id, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec team_four_column_grid(map()) :: Phoenix.LiveView.Rendered.t()
  def team_four_column_grid(assigns) do
    ~H"""
    <.oat_section id={@id} headline={@headline} subheadline={@subheadline} class={@class}>
      <div class="grid grid-cols-2 gap-6 sm:grid-cols-3 lg:grid-cols-4">
        <%= render_slot(@inner_block) %>
      </div>
    </.oat_section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Pricing Plan Card
  # Source: sections/pricing-hero-multi-tier.tsx — Plan
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Individual pricing plan card with feature list.
  Source: sections/pricing-hero-multi-tier.tsx — Plan
  """
  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :period, :string, required: true
  attr :badge, :string, default: nil
  attr :class, :string, default: ""
  slot :subheadline, required: true
  slot :features, required: true
  slot :cta, required: true

  @spec oat_plan(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_plan(assigns) do
    ~H"""
    <div class={[
      "flex flex-col justify-between gap-8 rounded-xl bg-oat-950/[0.025] p-8 ring-1 ring-oat-950/[0.06]",
      @class
    ]}>
      <div class="flex flex-col gap-6">
        <%= if @badge do %>
          <div>
            <span class="rounded-full bg-oat-950 px-3 py-1 text-xs text-white">
              <%= @badge %>
            </span>
          </div>
        <% end %>
        <div>
          <h3 class="font-familjen text-xl font-medium text-oat-950"><%= @name %></h3>
          <div class="mt-1 text-sm text-oat-700">
            <%= render_slot(@subheadline) %>
          </div>
        </div>
        <div class="flex items-baseline gap-1">
          <span class="font-familjen text-4xl/10 tracking-tight text-oat-950"><%= @price %></span>
          <span class="text-sm text-oat-500"><%= @period %></span>
        </div>
        <hr class="border-oat-950/10" />
        <ul class="flex flex-col gap-3 text-sm/7 text-oat-700">
          <%= render_slot(@features) %>
        </ul>
      </div>
      <%= render_slot(@cta) %>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # SECTION: Pricing Hero (multi-tier, no toggle)
  # Source: sections/pricing-hero-multi-tier.tsx
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Pricing hero section with plan cards. No monthly/yearly toggle (free product).
  Source: sections/pricing-hero-multi-tier.tsx
  """
  attr :headline, :string, required: true
  attr :subheadline, :string, default: nil
  attr :id, :string, default: nil
  attr :class, :string, default: ""
  slot :plans, required: true
  slot :footer

  @spec pricing_hero(map()) :: Phoenix.LiveView.Rendered.t()
  def pricing_hero(assigns) do
    ~H"""
    <section id={@id} class={["py-16", @class]}>
      <.oat_container class="flex flex-col gap-10 sm:gap-16">
        <div class="flex flex-col items-center gap-4 text-center">
          <.oat_heading class="max-w-3xl text-center">
            <%= @headline %>
          </.oat_heading>
          <%= if @subheadline do %>
            <.oat_text size="lg" class="max-w-2xl text-center text-pretty">
              <%= @subheadline %>
            </.oat_text>
          <% end %>
        </div>
        <div class="mx-auto grid w-full max-w-4xl grid-cols-1 gap-4 lg:grid-cols-2">
          <%= render_slot(@plans) %>
        </div>
        <%= if @footer != [] do %>
          <div class="text-center text-sm text-oat-600">
            <%= render_slot(@footer) %>
          </div>
        <% end %>
      </.oat_container>
    </section>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOCUMENT CENTERED
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Centered narrow prose wrapper for legal/document pages.
  Source: privacy-policy-01.tsx → DocumentCentered
  """
  attr :headline, :string, required: true
  attr :subheadline, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec oat_document(map()) :: Phoenix.LiveView.Rendered.t()
  def oat_document(assigns) do
    ~H"""
    <section class={["py-16", @class]}>
      <div class="mx-auto max-w-3xl px-6 lg:px-10">
        <div class="flex flex-col gap-8">
          <div class="flex flex-col gap-2">
            <.oat_heading><%= @headline %></.oat_heading>
            <%= if @subheadline do %>
              <.oat_text size="lg"><%= @subheadline %></.oat_text>
            <% end %>
          </div>
          <div class={[
            "flex flex-col gap-6",
            "[&_h2]:mt-4 [&_h2]:font-familjen [&_h2]:text-2xl [&_h2]:font-medium [&_h2]:text-oat-950",
            "[&_p]:text-base/7 [&_p]:text-oat-700",
            "[&_ul]:text-base/7 [&_ul]:text-oat-700 [&_ul]:list-disc [&_ul]:pl-6 [&_ul]:flex [&_ul]:flex-col [&_ul]:gap-1",
            "[&_a]:text-oat-950 [&_a]:underline [&_a]:underline-offset-2"
          ]}>
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
