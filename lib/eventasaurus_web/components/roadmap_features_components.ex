defmodule EventasaurusWeb.RoadmapFeaturesComponents do
  @moduledoc """
  Components for the combined Roadmap Features page.

  Combines the three-column Kanban layout from FutureFeaturesComponents
  with the simpler, cleaner card design from RoadmapComponents.

  ## Design Philosophy
  - Three-column layout (Now/Next/Later) for clear visual organization
  - Clean, simple cards with status strip indicator
  - Colorful tag badges for visual categorization
  - Status pills matching the roadmap style
  """
  use Phoenix.Component
  use EventasaurusWeb, :html

  # =============================================================================
  # Main Board Component
  # =============================================================================

  @doc """
  Renders the main three-column roadmap board.
  """
  attr :now_items, :list, required: true
  attr :next_items, :list, required: true
  attr :later_items, :list, required: true

  def board(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <%!-- Desktop: Three columns --%>
      <div class="hidden lg:grid lg:grid-cols-3 lg:gap-8">
        <.column
          status="now"
          title="Now"
          subtitle="In Progress"
          items={@now_items}
        />
        <.column
          status="next"
          title="Next"
          subtitle="Planned"
          items={@next_items}
        />
        <.column
          status="later"
          title="Later"
          subtitle="Considering"
          items={@later_items}
        />
      </div>

      <%!-- Tablet: Two columns + one below --%>
      <div class="hidden md:block lg:hidden">
        <div class="grid grid-cols-2 gap-6 mb-8">
          <.column
            status="now"
            title="Now"
            subtitle="In Progress"
            items={@now_items}
          />
          <.column
            status="next"
            title="Next"
            subtitle="Planned"
            items={@next_items}
          />
        </div>
        <.column
          status="later"
          title="Later"
          subtitle="Considering"
          items={@later_items}
        />
      </div>

      <%!-- Mobile: Stacked sections --%>
      <div class="md:hidden space-y-8">
        <.mobile_section
          status="now"
          title="Now"
          subtitle="In Progress"
          items={@now_items}
          default_open={true}
        />
        <.mobile_section
          status="next"
          title="Next"
          subtitle="Planned"
          items={@next_items}
          default_open={false}
        />
        <.mobile_section
          status="later"
          title="Later"
          subtitle="Considering"
          items={@later_items}
          default_open={false}
        />
      </div>
    </div>
    """
  end

  # =============================================================================
  # Column Component (Desktop/Tablet)
  # =============================================================================

  attr :status, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :items, :list, required: true

  def column(assigns) do
    ~H"""
    <section aria-label={"#{@title} - #{@subtitle}"}>
      <.column_header
        status={@status}
        title={@title}
        subtitle={@subtitle}
        count={length(@items)}
      />
      <div class="mt-4 space-y-4">
        <%= if Enum.empty?(@items) do %>
          <.empty_state status={@status} />
        <% else %>
          <.feature_card :for={item <- @items} item={item} status={@status} />
        <% end %>
      </div>
    </section>
    """
  end

  # =============================================================================
  # Column Header Component
  # =============================================================================

  attr :status, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :count, :integer, required: true

  def column_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-3 border-b border-zinc-200">
      <div class="flex items-center gap-3">
        <span class={[
          "inline-flex items-center rounded-full px-3 py-1 text-sm font-bold ring-1 ring-inset bg-white shadow-sm",
          header_badge_color(@status)
        ]}>
          <%= @title %>
        </span>
        <span class="text-sm text-zinc-500"><%= @subtitle %></span>
      </div>
      <span class={[
        "inline-flex items-center justify-center w-6 h-6 text-xs font-semibold rounded-full",
        count_badge_class(@status)
      ]}>
        <%= @count %>
      </span>
    </div>
    """
  end

  # =============================================================================
  # Mobile Section Component (Collapsible)
  # =============================================================================

  attr :status, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :items, :list, required: true
  attr :default_open, :boolean, default: false

  def mobile_section(assigns) do
    ~H"""
    <details class="group" open={@default_open}>
      <summary class={[
        "flex items-center justify-between p-4 cursor-pointer rounded-xl",
        "focus:outline-none focus:ring-2 focus:ring-offset-2",
        mobile_summary_class(@status)
      ]}>
        <div class="flex items-center gap-3">
          <span class={[
            "inline-flex items-center rounded-full px-3 py-1 text-sm font-bold ring-1 ring-inset bg-white shadow-sm",
            header_badge_color(@status)
          ]}>
            <%= @title %>
          </span>
          <span class="text-sm text-zinc-500"><%= @subtitle %></span>
          <span class={[
            "inline-flex items-center justify-center w-5 h-5 text-xs font-semibold rounded-full",
            count_badge_class(@status)
          ]}>
            <%= length(@items) %>
          </span>
        </div>
        <svg
          class="w-5 h-5 text-zinc-400 transition-transform group-open:rotate-180"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
        </svg>
      </summary>
      <div class="mt-4 space-y-4">
        <%= if Enum.empty?(@items) do %>
          <.empty_state status={@status} />
        <% else %>
          <.feature_card :for={item <- @items} item={item} status={@status} />
        <% end %>
      </div>
    </details>
    """
  end

  # =============================================================================
  # Feature Card Component (Simple style from RoadmapComponents)
  # =============================================================================

  @doc """
  Renders a single feature card with the clean roadmap style.
  """
  attr :item, :map, required: true
  attr :status, :string, required: true

  def feature_card(assigns) do
    # Get strip color from first tag (more colorful) or fall back to status
    first_tag = List.first(assigns.item.tags || [])
    strip_color = if first_tag, do: tag_strip_color(first_tag), else: status_strip_color(assigns.status)
    assigns = assign(assigns, :strip_color, strip_color)

    ~H"""
    <article class="bg-white rounded-2xl p-6 shadow-sm border border-zinc-200/60 hover:shadow-md transition-shadow relative overflow-hidden group">
      <%!-- Status Indicator Strip (colored by first tag for variety) --%>
      <div class={["absolute top-0 left-0 w-1 h-full", @strip_color]}></div>

      <div class="pl-2">
        <%!-- Tags row (status shown in column header, not repeated here) --%>
        <div class="flex flex-wrap items-center gap-2 mb-3">
          <.tag_badge :for={tag <- @item.tags} tag={tag} />
        </div>

        <%!-- Title --%>
        <h3 class="text-xl font-bold text-zinc-900 mb-2 group-hover:text-indigo-600 transition-colors">
          <%= @item.title %>
        </h3>

        <%!-- Description --%>
        <p class="text-zinc-600 leading-relaxed"><%= @item.description %></p>
      </div>
    </article>
    """
  end

  # =============================================================================
  # Tag Badge Component (Colorful style)
  # =============================================================================

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
  # Empty State Component
  # =============================================================================

  attr :status, :string, required: true

  def empty_state(assigns) do
    message = empty_state_message(assigns.status)
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="p-6 text-center bg-zinc-50/50 rounded-xl border-2 border-dashed border-zinc-200">
      <p class="text-zinc-500 text-sm"><%= @message %></p>
    </div>
    """
  end

  defp empty_state_message(status) do
    case status do
      "now" -> "We're planning our next sprint. Check back soon!"
      "next" -> "Nothing planned yet. Have a suggestion?"
      "later" -> "We're always exploring new ideas."
      _ -> "No items to display."
    end
  end

  # =============================================================================
  # Styling Helpers
  # =============================================================================

  # Column header badge colors
  defp header_badge_color(status) do
    case status do
      "now" -> "text-indigo-700 ring-indigo-700/20"
      "next" -> "text-amber-700 ring-amber-700/20"
      "later" -> "text-zinc-600 ring-zinc-600/20"
      _ -> "text-zinc-600 ring-zinc-600/20"
    end
  end

  # Count badge colors
  defp count_badge_class(status) do
    case status do
      "now" -> "bg-indigo-100 text-indigo-700"
      "next" -> "bg-amber-100 text-amber-700"
      "later" -> "bg-zinc-200 text-zinc-600"
      _ -> "bg-zinc-200 text-zinc-600"
    end
  end

  # Mobile summary background colors
  defp mobile_summary_class(status) do
    case status do
      "now" -> "bg-indigo-50/50 focus:ring-indigo-500"
      "next" -> "bg-amber-50/50 focus:ring-amber-500"
      "later" -> "bg-zinc-100/50 focus:ring-zinc-400"
      _ -> "bg-zinc-100/50 focus:ring-zinc-400"
    end
  end

  # Status strip on left side of card
  defp status_strip_color(status) do
    case status do
      "now" -> "bg-indigo-500"
      "next" -> "bg-amber-500"
      "later" -> "bg-zinc-300"
      _ -> "bg-zinc-300"
    end
  end

  # Tag strip colors - solid colors for card left strip (based on first tag)
  defp tag_strip_color(tag) do
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
      # Social & Community
      "social" -> "bg-violet-500"
      "matching" -> "bg-violet-500"
      "activities" -> "bg-violet-400"
      "chat" -> "bg-violet-500"
      "communication" -> "bg-violet-400"
      "collaboration" -> "bg-purple-500"
      "groups" -> "bg-purple-500"
      # Music & Entertainment
      "music" -> "bg-pink-500"
      "spotify" -> "bg-green-500"
      "gaming" -> "bg-red-500"
      "boardgames" -> "bg-red-500"
      # Events & Scheduling
      "calendar" -> "bg-blue-500"
      "recurring" -> "bg-blue-400"
      "templates" -> "bg-indigo-500"
      "productivity" -> "bg-indigo-400"
      "festivals" -> "bg-amber-500"
      "multi-day" -> "bg-amber-500"
      # Commerce & Transactions
      "ticketing" -> "bg-green-500"
      "payments" -> "bg-green-500"
      "crowdfunding" -> "bg-green-400"
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
      # Lists & Organization
      "lists" -> "bg-cyan-500"
      "contributions" -> "bg-cyan-400"
      # Gamification
      "leagues" -> "bg-orange-500"
      "gamification" -> "bg-orange-500"
      "notifications" -> "bg-amber-500"
      # Default
      _ -> "bg-zinc-400"
    end
  end

  # Tag colors - colorful badges (lighter for tag pills)
  defp tag_color(tag) do
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
      # Social & Community
      "social" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "matching" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "activities" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "chat" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "communication" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "collaboration" -> {"bg-purple-50", "text-purple-700", "ring-purple-700/10"}
      "groups" -> {"bg-purple-50", "text-purple-700", "ring-purple-700/10"}
      # Music & Entertainment
      "music" -> {"bg-pink-50", "text-pink-700", "ring-pink-700/10"}
      "spotify" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "gaming" -> {"bg-red-50", "text-red-700", "ring-red-700/10"}
      "boardgames" -> {"bg-red-50", "text-red-700", "ring-red-700/10"}
      # Events & Scheduling
      "calendar" -> {"bg-blue-50", "text-blue-700", "ring-blue-700/10"}
      "recurring" -> {"bg-blue-50", "text-blue-700", "ring-blue-700/10"}
      "templates" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}
      "productivity" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}
      "festivals" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}
      "multi-day" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}
      "scheduling" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}
      # Commerce & Transactions
      "ticketing" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "payments" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
      "crowdfunding" -> {"bg-green-50", "text-green-700", "ring-green-700/10"}
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
      # Lists & Organization
      "lists" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      "contributions" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      # Gamification
      "leagues" -> {"bg-orange-50", "text-orange-700", "ring-orange-700/10"}
      "gamification" -> {"bg-orange-50", "text-orange-700", "ring-orange-700/10"}
      # Design & UX
      "design" -> {"bg-pink-50", "text-pink-700", "ring-pink-700/10"}
      "ux" -> {"bg-rose-50", "text-rose-700", "ring-rose-700/10"}
      "accessibility" -> {"bg-indigo-50", "text-indigo-700", "ring-indigo-700/10"}
      # Features
      "analytics" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      "business" -> {"bg-gray-50", "text-gray-700", "ring-gray-700/10"}
      "notifications" -> {"bg-amber-50", "text-amber-700", "ring-amber-700/10"}
      "performance" -> {"bg-orange-50", "text-orange-700", "ring-orange-700/10"}
      # Default
      _ -> {"bg-zinc-50", "text-zinc-700", "ring-zinc-700/10"}
    end
  end
end
