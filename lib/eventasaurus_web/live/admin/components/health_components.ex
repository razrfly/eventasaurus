defmodule EventasaurusWeb.Admin.Components.HealthComponents do
  @moduledoc """
  Shared UI components for health dashboards.

  Provides reusable components for displaying health scores, status indicators,
  progress bars, sparklines, and stat cards. Used by both the City Health Dashboard
  index and detail pages.

  ## Components

  - `health_score_pill/1` - Compact status pill with score and color
  - `health_score_large/1` - Large score display with progress ring
  - `progress_bar/1` - Configurable progress bar
  - `sparkline/1` - 7-day trend mini bar chart
  - `stat_card/1` - Stat card with icon and border
  - `health_component_bar/1` - Individual health component with label and weight
  - `trend_indicator/1` - Trend arrow with percentage

  ## Usage

      use EventasaurusWeb, :html
      import EventasaurusWeb.Admin.Components.HealthComponents

      # In template:
      <.health_score_pill score={85} status={:healthy} />
      <.sparkline data={[10, 15, 12, 18, 22, 20, 25]} />
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: EventasaurusWeb.Endpoint, router: EventasaurusWeb.Router

  # ============================================================================
  # Health Score Pill
  # ============================================================================

  @doc """
  Renders a compact health score pill with status color.

  ## Attributes

  - `score` - The health score (0-100)
  - `status` - One of :healthy, :warning, :critical, :disabled, :unknown
  - `show_score` - Whether to show the numeric score (default: true)
  - `size` - Size variant: :sm, :md, :lg (default: :md)

  ## Examples

      <.health_score_pill score={85} status={:healthy} />
      <.health_score_pill score={45} status={:critical} show_score={false} />
  """
  attr :score, :integer, default: 0
  attr :status, :atom, required: true
  attr :show_score, :boolean, default: true
  attr :size, :atom, default: :md

  def health_score_pill(assigns) do
    {emoji, label, _color} = status_indicator(assigns.status)

    size_classes =
      case assigns.size do
        :sm -> "px-2 py-0.5 text-xs"
        :md -> "px-2.5 py-0.5 text-xs"
        :lg -> "px-3 py-1 text-sm"
      end

    assigns =
      assigns
      |> assign(:emoji, emoji)
      |> assign(:label, label)
      |> assign(:size_classes, size_classes)
      |> assign(:status_classes, status_classes(assigns.status))

    ~H"""
    <span class={"inline-flex items-center rounded-full font-medium #{@size_classes} #{@status_classes}"}>
      <%= @emoji %>
      <%= if @show_score do %>
        <span class="ml-1"><%= @score %>%</span>
      <% else %>
        <span class="ml-1"><%= @label %></span>
      <% end %>
    </span>
    """
  end

  # ============================================================================
  # Health Score Large Display
  # ============================================================================

  @doc """
  Renders a large health score display with optional progress ring.

  ## Attributes

  - `score` - The health score (0-100)
  - `status` - One of :healthy, :warning, :critical, :disabled, :unknown
  - `show_ring` - Whether to show the progress ring (default: true)
  - `label` - Optional label below the score

  ## Examples

      <.health_score_large score={72} status={:warning} />
      <.health_score_large score={95} status={:healthy} label="City Health" />
  """
  attr :score, :integer, default: 0
  attr :status, :atom, required: true
  attr :show_ring, :boolean, default: true
  attr :label, :string, default: nil

  def health_score_large(assigns) do
    {emoji, status_label, _color} = status_indicator(assigns.status)

    # Calculate ring circumference and offset for SVG circle
    # Circle has radius 45, circumference = 2 * pi * 45 ≈ 283
    circumference = 283
    offset = circumference - (assigns.score / 100 * circumference)

    assigns =
      assigns
      |> assign(:emoji, emoji)
      |> assign(:status_label, status_label)
      |> assign(:circumference, circumference)
      |> assign(:offset, offset)
      |> assign(:ring_color, ring_color(assigns.status))
      |> assign(:text_color, text_color(assigns.status))

    ~H"""
    <div class="flex flex-col items-center">
      <%= if @show_ring do %>
        <div class="relative w-32 h-32">
          <!-- Background circle -->
          <svg class="w-32 h-32 transform -rotate-90">
            <circle
              cx="64"
              cy="64"
              r="45"
              stroke="currentColor"
              stroke-width="10"
              fill="none"
              class="text-gray-200"
            />
            <!-- Progress circle -->
            <circle
              cx="64"
              cy="64"
              r="45"
              stroke="currentColor"
              stroke-width="10"
              fill="none"
              class={@ring_color}
              stroke-dasharray={@circumference}
              stroke-dashoffset={@offset}
              stroke-linecap="round"
            />
          </svg>
          <!-- Score in center -->
          <div class="absolute inset-0 flex flex-col items-center justify-center">
            <span class={"text-3xl font-bold #{@text_color}"}><%= @score %></span>
            <span class="text-xs text-gray-500">/ 100</span>
          </div>
        </div>
      <% else %>
        <div class={"text-5xl font-bold #{@text_color}"}><%= @score %>%</div>
      <% end %>

      <!-- Status badge -->
      <div class="mt-2 flex items-center gap-1">
        <span class="text-lg"><%= @emoji %></span>
        <span class={"font-medium #{@text_color}"}><%= @status_label %></span>
      </div>

      <!-- Optional label -->
      <%= if @label do %>
        <p class="mt-1 text-sm text-gray-500"><%= @label %></p>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Progress Bar
  # ============================================================================

  @doc """
  Renders a configurable progress bar.

  ## Attributes

  - `value` - The current value (0-100 or any number if max is provided)
  - `max` - Maximum value (default: 100)
  - `color` - Bar color: :blue, :green, :yellow, :red, :purple, :indigo (default: :blue)
  - `size` - Size variant: :xs, :sm, :md, :lg (default: :md)
  - `show_label` - Show percentage label (default: false)
  - `animate` - Enable animation (default: true)

  ## Examples

      <.progress_bar value={75} />
      <.progress_bar value={45} color={:red} show_label />
      <.progress_bar value={120} max={200} color={:green} />
  """
  attr :value, :integer, default: 0
  attr :max, :integer, default: 100
  attr :color, :atom, default: :blue
  attr :size, :atom, default: :md
  attr :show_label, :boolean, default: false
  attr :animate, :boolean, default: true

  def progress_bar(assigns) do
    percentage = min(100, round(assigns.value / max(assigns.max, 1) * 100))

    height_class =
      case assigns.size do
        :xs -> "h-1"
        :sm -> "h-1.5"
        :md -> "h-2"
        :lg -> "h-3"
      end

    bar_color = bar_color_class(assigns.color)
    animation = if assigns.animate, do: "transition-all duration-300", else: ""

    assigns =
      assigns
      |> assign(:percentage, percentage)
      |> assign(:height_class, height_class)
      |> assign(:bar_color, bar_color)
      |> assign(:animation, animation)

    ~H"""
    <div class="w-full">
      <%= if @show_label do %>
        <div class="flex justify-between items-center mb-1">
          <span class="text-xs text-gray-500"></span>
          <span class="text-xs font-medium text-gray-700"><%= @percentage %>%</span>
        </div>
      <% end %>
      <div class={"w-full bg-gray-200 rounded-full #{@height_class}"}>
        <div
          class={"#{@bar_color} #{@height_class} rounded-full #{@animation}"}
          style={"width: #{@percentage}%"}
        ></div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sparkline
  # ============================================================================

  @doc """
  Renders a 7-day sparkline mini bar chart.

  ## Attributes

  - `data` - List of values (typically 7 days)
  - `highlight_last` - Highlight the last bar (default: true)
  - `color` - Bar color: :blue, :green, :gray (default: :blue)
  - `height` - Container height in pixels (default: 16)

  ## Examples

      <.sparkline data={[10, 15, 12, 18, 22, 20, 25]} />
      <.sparkline data={@weekly_counts} highlight_last={false} color={:green} />
  """
  attr :data, :list, default: []
  attr :highlight_last, :boolean, default: true
  attr :color, :atom, default: :blue
  attr :height, :integer, default: 16

  def sparkline(assigns) do
    heights = sparkline_heights(assigns.data)

    bar_color =
      case assigns.color do
        :blue -> "bg-blue-500"
        :green -> "bg-green-500"
        :gray -> "bg-gray-400"
        _ -> "bg-blue-500"
      end

    inactive_color = "bg-gray-300"

    assigns =
      assigns
      |> assign(:heights, heights)
      |> assign(:bar_color, bar_color)
      |> assign(:inactive_color, inactive_color)

    ~H"""
    <div
      class="flex items-end gap-0.5"
      style={"height: #{@height}px"}
      title={"Last #{length(@data)} days: #{Enum.join(@data, ", ")}"}
    >
      <%= for {height, idx} <- Enum.with_index(@heights) do %>
        <% is_last = idx == length(@heights) - 1 %>
        <% color = if @highlight_last && is_last, do: @bar_color, else: @inactive_color %>
        <div
          class={"w-1 rounded-t #{color}"}
          style={"height: #{max(height * (@height / 100), 1)}px"}
        ></div>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Stat Card (Legacy - emoji-based)
  # ============================================================================

  @doc """
  Renders a stat card with icon and value (legacy version with emoji).

  ## Attributes

  - `title` - Card title
  - `value` - The main value to display
  - `icon` - Emoji or icon string
  - `color` - Border color: :blue, :green, :yellow, :red, :purple, :indigo, :gray (default: :blue)
  - `subtitle` - Optional subtitle below the value

  ## Examples

      <.stat_card title="Total Events" value={1234} icon="📊" color={:blue} />
      <.stat_card title="Active Sources" value={8} icon="🔌" color={:purple} subtitle="3 healthy" />
  """
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :atom, default: :blue
  attr :subtitle, :string, default: nil

  def stat_card(assigns) do
    border_color = border_color_class(assigns.color)

    assigns = assign(assigns, :border_color, border_color)

    ~H"""
    <div class={"bg-white shadow rounded-lg p-5 border-l-4 #{@border_color}"}>
      <div class="flex items-center justify-between">
        <span class="text-2xl"><%= @icon %></span>
        <span class="text-2xl font-bold text-gray-900"><%= format_value(@value) %></span>
      </div>
      <p class="mt-1 text-sm text-gray-600"><%= @title %></p>
      <%= if @subtitle do %>
        <p class="text-xs text-gray-400 mt-0.5"><%= @subtitle %></p>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Admin Stat Card (Admin Dashboard Style)
  # ============================================================================

  @doc """
  Renders a stat card matching the admin dashboard pattern.

  Features border-l-4 colored accent, label on top, large number below,
  and SVG icon in a circular background on the right side.

  ## Attributes

  - `title` - Card title (displayed as label)
  - `value` - The main value to display (large, prominent)
  - `icon` - SVG icon slot (or use icon_type for built-in icons)
  - `icon_type` - Built-in icon: :chart, :plug, :location, :tag, :calendar, :users (default: :chart)
  - `color` - Accent color: :blue, :green, :yellow, :red, :purple, :indigo (default: :blue)
  - `subtitle` - Optional subtitle below the main content

  ## Examples

      <.admin_stat_card title="Total Events" value="1,234" icon_type={:chart} color={:blue} />
      <.admin_stat_card title="Active Sources" value={8} icon_type={:plug} color={:purple} subtitle="3 healthy" />
  """
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon_type, :atom, default: :chart
  attr :color, :atom, default: :blue
  attr :subtitle, :string, default: nil

  def admin_stat_card(assigns) do
    border_color = border_color_class(assigns.color)
    bg_color = bg_color_class(assigns.color)
    icon_color = icon_color_class(assigns.color)
    text_color = admin_text_color_class(assigns.color)

    assigns =
      assigns
      |> assign(:border_color, border_color)
      |> assign(:bg_color, bg_color)
      |> assign(:icon_color, icon_color)
      |> assign(:text_color, text_color)

    ~H"""
    <div class={"bg-white shadow rounded-lg p-5 border-l-4 #{@border_color}"}>
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm font-medium text-gray-500"><%= @title %></div>
          <div class={"text-3xl font-bold mt-1 #{@text_color}"}><%= format_value(@value) %></div>
        </div>
        <div class={"flex items-center justify-center w-12 h-12 rounded-full #{@bg_color}"}>
          <.admin_icon type={@icon_type} class={@icon_color} />
        </div>
      </div>
      <%= if @subtitle do %>
        <div class="text-sm mt-2 text-gray-500"><%= @subtitle %></div>
      <% end %>
    </div>
    """
  end

  @doc false
  attr :type, :atom, required: true
  attr :class, :string, default: "w-6 h-6"

  def admin_icon(assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <%= case @type do %>
        <% :chart -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        <% :plug -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
        <% :location -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
        <% :tag -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
        <% :calendar -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
        <% :users -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
        <% _ -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      <% end %>
    </svg>
    """
  end

  # ============================================================================
  # Health Metric Card (Compact 4-column layout)
  # ============================================================================

  @doc """
  Renders a compact health metric card for 4-column grid layout.

  Designed for displaying health score breakdown components in a horizontal grid.

  ## Attributes

  - `label` - Component name (e.g., "Event Coverage")
  - `value` - Percentage value (0-100)
  - `weight` - Weight description (e.g., "40%")
  - `description` - Brief description of what the metric measures
  - `target` - Optional target threshold
  - `color` - Bar color based on status

  ## Examples

      <.health_metric_card
        label="Event Coverage"
        value={85}
        weight="40%"
        description="7-day availability"
        target={80}
      />
  """
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :weight, :string, required: true
  attr :description, :string, default: nil
  attr :target, :integer, default: nil
  attr :color, :atom, default: :blue

  def health_metric_card(assigns) do
    bar_color = bar_color_class(assigns.color)
    text_color = text_color_class(assigns.color)

    meets_target =
      if assigns.target do
        assigns.value >= assigns.target
      else
        nil
      end

    assigns =
      assigns
      |> assign(:bar_color, bar_color)
      |> assign(:text_color, text_color)
      |> assign(:meets_target, meets_target)

    ~H"""
    <div class="bg-white shadow rounded-lg p-4 border-l-4 border-gray-200 hover:border-gray-300 transition-colors">
      <!-- Header: Label + Weight Badge -->
      <div class="flex items-start justify-between mb-2">
        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-semibold text-gray-900 truncate"><%= @label %></h3>
          <%= if @description do %>
            <p class="text-xs text-gray-500 mt-0.5 truncate"><%= @description %></p>
          <% end %>
        </div>
        <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600 flex-shrink-0">
          <%= @weight %>
        </span>
      </div>

      <!-- Value + Status -->
      <div class="flex items-end justify-between mb-2">
        <span class={"text-2xl font-bold #{@text_color}"}><%= @value %>%</span>
        <%= if @meets_target != nil do %>
          <%= if @meets_target do %>
            <span class="inline-flex items-center text-green-600 text-sm">
              <svg class="w-4 h-4 mr-0.5" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
              </svg>
              On target
            </span>
          <% else %>
            <span class="inline-flex items-center text-red-600 text-sm">
              <svg class="w-4 h-4 mr-0.5" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
              </svg>
              Below
            </span>
          <% end %>
        <% end %>
      </div>

      <!-- Progress Bar -->
      <div class="w-full bg-gray-200 rounded-full h-2">
        <div
          class={"#{@bar_color} h-2 rounded-full transition-all duration-300"}
          style={"width: #{min(@value, 100)}%"}
        ></div>
      </div>

      <!-- Target indicator -->
      <%= if @target do %>
        <div class="mt-1.5 text-xs text-gray-400">
          Target: <%= @target %>%
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Health Component Bar
  # ============================================================================

  @doc """
  Renders a health component bar with label, value, and weight.

  ## Attributes

  - `label` - Component name (e.g., "Event Coverage")
  - `value` - Percentage value (0-100)
  - `weight` - Weight description (e.g., "40%")
  - `color` - Bar color: :blue, :green, :yellow, :purple, :red (default: :blue)
  - `target` - Optional target threshold
  - `show_status` - Show ✓/✗ based on target (default: false)

  ## Examples

      <.health_component_bar label="Event Coverage" value={85} weight="40%" color={:blue} />
      <.health_component_bar label="Source Activity" value={45} weight="30%" color={:green} target={90} show_status />
  """
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :weight, :string, required: true
  attr :color, :atom, default: :blue
  attr :target, :integer, default: nil
  attr :show_status, :boolean, default: false
  attr :description, :string, default: nil

  def health_component_bar(assigns) do
    bar_color = bar_color_class(assigns.color)
    text_color = text_color_class(assigns.color)

    meets_target =
      if assigns.target do
        assigns.value >= assigns.target
      else
        nil
      end

    assigns =
      assigns
      |> assign(:bar_color, bar_color)
      |> assign(:text_color, text_color)
      |> assign(:meets_target, meets_target)

    ~H"""
    <div class="bg-white rounded-lg p-3 border border-gray-200">
      <div class="flex justify-between items-center mb-1">
        <div>
          <span class="text-xs font-medium text-gray-600"><%= @label %></span>
          <%= if @description do %>
            <p class="text-xs text-gray-400 mt-0.5"><%= @description %></p>
          <% end %>
        </div>
        <div class="flex items-center gap-1">
          <span class={"text-xs font-bold #{@text_color}"}><%= @value %>%</span>
          <%= if @show_status && @meets_target != nil do %>
            <%= if @meets_target do %>
              <span class="text-green-500 text-xs">✓</span>
            <% else %>
              <span class="text-red-500 text-xs">✗</span>
            <% end %>
          <% end %>
        </div>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2">
        <div
          class={"#{@bar_color} h-2 rounded-full transition-all duration-300"}
          style={"width: #{min(@value, 100)}%"}
        ></div>
      </div>
      <div class="flex justify-between items-center mt-1">
        <span class="text-xs text-gray-400">Weight: <%= @weight %></span>
        <%= if @target do %>
          <span class="text-xs text-gray-400">Target: <%= @target %>%</span>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Trend Indicator
  # ============================================================================

  @doc """
  Renders a trend indicator with arrow and percentage.

  ## Attributes

  - `change` - Percentage change (positive, negative, or zero)
  - `show_arrow` - Show arrow indicator (default: true)
  - `size` - Size variant: :sm, :md, :lg (default: :md)

  ## Examples

      <.trend_indicator change={15} />
      <.trend_indicator change={-8} />
      <.trend_indicator change={0} show_arrow={false} />
  """
  attr :change, :integer, required: true
  attr :show_arrow, :boolean, default: true
  attr :size, :atom, default: :md

  def trend_indicator(assigns) do
    {arrow, color} =
      cond do
        assigns.change > 0 -> {"↑", "text-green-600"}
        assigns.change < 0 -> {"↓", "text-red-600"}
        true -> {"→", "text-gray-500"}
      end

    size_class =
      case assigns.size do
        :sm -> "text-xs"
        :md -> "text-sm"
        :lg -> "text-base"
      end

    formatted = format_change(assigns.change)

    assigns =
      assigns
      |> assign(:arrow, arrow)
      |> assign(:color, color)
      |> assign(:size_class, size_class)
      |> assign(:formatted, formatted)

    ~H"""
    <span class={"font-medium #{@color} #{@size_class}"}>
      <%= if @show_arrow do %><%= @arrow %><% end %><%= @formatted %>
    </span>
    """
  end

  # ============================================================================
  # Status Badge (for issues)
  # ============================================================================

  @doc """
  Renders a status badge for job states.

  ## Attributes

  - `state` - Job state: "success", "failure", "cancelled", "discarded", etc.

  ## Examples

      <.status_badge state="success" />
      <.status_badge state="failure" />
  """
  attr :state, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={badge_classes(@state)}>
      <%= badge_icon(@state) %> <%= badge_label(@state) %>
    </span>
    """
  end

  # ============================================================================
  # Source Table
  # ============================================================================

  @doc """
  Renders an expandable source table with job statistics and error details.

  ## Attributes

  - `sources` - List of source maps with :id, :name, :slug, :event_count, :success_rate, :health_status, :total_jobs
  - `expanded` - MapSet of expanded source slugs
  - `source_errors` - Map of source_id -> list of error maps

  ## Events

  This component emits the following events that must be handled by the parent LiveView:
  - `toggle_source` with `source` param
  - `expand_all_sources`
  - `collapse_all_sources`

  ## Examples

      <.source_table
        sources={@source_data}
        expanded={@expanded_sources}
        source_errors={@source_errors}
      />
  """
  attr :sources, :list, required: true
  attr :expanded, :any, required: true
  attr :source_errors, :map, default: %{}

  def source_table(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border mb-6">
      <div class="px-6 py-4 border-b flex items-center justify-between">
        <h2 class="text-lg font-semibold text-gray-900">Active Sources</h2>
        <div class="flex items-center gap-2">
          <%= if MapSet.size(@expanded) > 0 do %>
            <button
              phx-click="collapse_all_sources"
              class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-1"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
              </svg>
              Collapse All
            </button>
          <% else %>
            <button
              phx-click="expand_all_sources"
              class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-1"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
              Expand All
            </button>
          <% end %>
        </div>
      </div>

      <%= if Enum.empty?(@sources) do %>
        <div class="px-6 py-12 text-center text-gray-500">
          <p>No active sources found for this city.</p>
        </div>
      <% else %>
        <div class="divide-y">
          <%= for source <- @sources do %>
            <.source_row
              source={source}
              is_expanded={MapSet.member?(@expanded, source.slug)}
              errors={Map.get(@source_errors, source.id, [])}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc false
  attr :source, :map, required: true
  attr :is_expanded, :boolean, required: true
  attr :errors, :list, default: []

  def source_row(assigns) do
    ~H"""
    <div>
      <button
        phx-click="toggle_source"
        phx-value-source={@source.slug}
        class="w-full px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
      >
        <div class="flex items-center gap-4">
          <!-- Expand Arrow -->
          <svg
            class={"w-4 h-4 text-gray-400 transition-transform #{if @is_expanded, do: "rotate-90"}"}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
          <!-- Source Name -->
          <span class="font-medium text-gray-900"><%= @source.name %></span>
        </div>

        <div class="flex items-center gap-6">
          <!-- Event Count -->
          <span class="text-sm text-gray-500">
            <%= @source.event_count %> events
          </span>
          <!-- Success Rate -->
          <span class="text-sm text-gray-500">
            <%= @source.success_rate %>% success
          </span>
          <!-- Health Status -->
          <.health_score_pill
            score={@source.success_rate}
            status={@source.health_status}
            show_score={false}
          />
        </div>
      </button>

      <!-- Expanded Content -->
      <%= if @is_expanded do %>
        <div class="px-6 pb-6 pt-2 bg-gray-50 border-t">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- Health Breakdown -->
            <div>
              <h4 class="text-sm font-semibold text-gray-700 mb-3">Source Statistics</h4>
              <div class="space-y-3">
                <.health_component_bar
                  label="Job Success Rate"
                  value={@source.success_rate}
                  weight=""
                  color={component_color(@source.success_rate)}
                  target={90}
                  description="Last 7 days"
                  show_status={true}
                />
                <div class="flex items-center justify-between text-sm">
                  <span class="text-gray-600">Total Jobs (7d)</span>
                  <span class="font-medium"><%= @source.total_jobs %></span>
                </div>
                <div class="flex items-center justify-between text-sm">
                  <span class="text-gray-600">Events Created</span>
                  <span class="font-medium"><%= @source.event_count %></span>
                </div>
              </div>
            </div>

            <!-- Recent Errors -->
            <div>
              <h4 class="text-sm font-semibold text-gray-700 mb-3">Recent Errors (24h)</h4>
              <%= if Enum.empty?(@errors) do %>
                <div class="text-sm text-gray-500 py-2">
                  ✓ No errors in the last 24 hours
                </div>
              <% else %>
                <div class="space-y-2 max-h-48 overflow-y-auto">
                  <%= for error <- Enum.take(@errors, 5) do %>
                    <div class="text-sm p-2 bg-white rounded border">
                      <div class="flex items-center gap-2 mb-1">
                        <.status_badge state={error.state} />
                        <span class="text-gray-500 text-xs">
                          <%= time_ago_in_words(error.attempted_at) %>
                        </span>
                      </div>
                      <div class="text-gray-700">
                        <span class="font-medium"><%= format_worker_name(error.worker) %></span>
                        <%= if error.error_category do %>
                          <span class="text-gray-400 mx-1">•</span>
                          <span class="text-orange-600"><%= error.error_category %></span>
                        <% end %>
                      </div>
                      <%= if error.error_message do %>
                        <div class="text-gray-500 text-xs mt-1 truncate" title={error.error_message}>
                          <%= String.slice(error.error_message || "", 0, 100) %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <%= if length(@errors) > 5 do %>
                    <div class="text-xs text-gray-500 pt-1">
                      + <%= length(@errors) - 5 %> more errors
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Quick Actions -->
          <div class="mt-4 pt-4 border-t flex items-center gap-4">
            <.link
              navigate={~p"/admin/job-executions?source=#{@source.slug}"}
              class="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
              </svg>
              View Job Executions
            </.link>
            <.link
              navigate={~p"/admin/error-trends?source=#{@source.slug}"}
              class="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
              </svg>
              View Error Trends
            </.link>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Source Health Summary Grid (Shared Component)
  # ============================================================================

  @doc """
  Renders a 4-card summary grid showing source health breakdown.

  This is a shared component used by both the City Health Detail page and
  the Discovery Dashboard for consistent source health visualization.

  ## Attributes

  - `sources` - List of source maps with `:success_rate` field
  - `show_link` - Whether to show "View Details" link (default: false)
  - `link_path` - Path for the "View Details" link

  ## Examples

      <.source_health_summary sources={@source_data} />
      <.source_health_summary sources={@sources} show_link={true} link_path={~p"/admin/discovery/stats"} />
  """
  attr :sources, :list, required: true
  attr :show_link, :boolean, default: false
  attr :link_path, :string, default: nil

  def source_health_summary(assigns) do
    total = length(assigns.sources)
    healthy = Enum.count(assigns.sources, fn s -> Map.get(s, :success_rate, 0) >= 95 end)
    warning = Enum.count(assigns.sources, fn s ->
      rate = Map.get(s, :success_rate, 0)
      rate >= 80 and rate < 95
    end)
    critical = Enum.count(assigns.sources, fn s -> Map.get(s, :success_rate, 0) < 80 end)

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:healthy, healthy)
      |> assign(:warning, warning)
      |> assign(:critical, critical)

    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
      <div class="p-4 bg-blue-50 rounded-lg text-center">
        <p class="text-2xl font-bold text-blue-900"><%= @total %></p>
        <p class="text-sm text-blue-700 mt-1">Active Sources</p>
      </div>

      <div class="p-4 bg-green-50 rounded-lg text-center">
        <p class="text-2xl font-bold text-green-900"><%= @healthy %></p>
        <p class="text-sm text-green-700 mt-1">Healthy (≥95%)</p>
      </div>

      <div class="p-4 bg-yellow-50 rounded-lg text-center">
        <p class="text-2xl font-bold text-yellow-900"><%= @warning %></p>
        <p class="text-sm text-yellow-700 mt-1">Warning (80-95%)</p>
      </div>

      <div class="p-4 bg-red-50 rounded-lg text-center">
        <p class="text-2xl font-bold text-red-900"><%= @critical %></p>
        <p class="text-sm text-red-700 mt-1">Critical (&lt;80%)</p>
      </div>
    </div>

    <%= if @show_link && @link_path do %>
      <div class="text-center mb-4">
        <.link
          navigate={@link_path}
          class="inline-flex items-center text-blue-600 hover:text-blue-800 text-sm font-medium"
        >
          View all sources and detailed metrics →
        </.link>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # Job History Timeline (Shared Component)
  # ============================================================================

  @doc """
  Renders a visual timeline of recent job runs with status indicators.

  Shows a horizontal bar of job status indicators (success/failure) with
  tooltips showing details. Optionally shows recent failure details below.

  ## Attributes

  - `jobs` - List of job maps with `:state`, `:completed_at`, `:duration_seconds`, `:errors` fields
  - `show_failures` - Whether to show failure details below the timeline (default: true)
  - `max_failures` - Maximum number of failures to show (default: 3)

  ## Examples

      <.job_history_timeline jobs={source.recent_jobs} />
      <.job_history_timeline jobs={@jobs} show_failures={false} />
  """
  attr :jobs, :list, required: true
  attr :show_failures, :boolean, default: true
  attr :max_failures, :integer, default: 3

  def job_history_timeline(assigns) do
    failures = Enum.filter(assigns.jobs, fn j -> Map.get(j, :state) != "success" end)

    assigns =
      assigns
      |> assign(:failures, failures)

    ~H"""
    <%= if Enum.empty?(@jobs) do %>
      <div class="text-sm text-gray-500 py-2">
        No job history available
      </div>
    <% else %>
      <div class="flex items-center gap-1 mb-2">
        <%= for job <- @jobs do %>
          <% is_success = Map.get(job, :state) == "success" %>
          <div
            class={"flex-1 h-8 rounded flex items-center justify-center text-xs #{if is_success, do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}
            title={"#{if is_success, do: "✅ Success", else: "❌ Failed"} - #{format_job_time(job)} - #{Map.get(job, :duration_seconds, 0)}s"}
          >
            <%= if is_success, do: "✅", else: "❌" %>
          </div>
        <% end %>
      </div>

      <%= if @show_failures and not Enum.empty?(@failures) do %>
        <div class="mt-2 space-y-1">
          <p class="text-xs font-medium text-gray-700"><%= length(@failures) %> Recent Failures:</p>
          <%= for failure <- Enum.take(@failures, @max_failures) do %>
            <div class="text-xs text-red-700 bg-red-50 p-2 rounded">
              <span class="font-mono"><%= format_job_time(failure) %></span>
              <%= if Map.get(failure, :errors) do %>
                - <span class="font-medium"><%= Map.get(failure, :errors) %></span>
              <% else %>
                - <span class="text-orange-700">Failed with no error message</span>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    <% end %>
    """
  end

  # ============================================================================
  # Enhanced Source Table with Timeline (Shared Component)
  # ============================================================================

  @doc """
  Renders the enhanced source table with job history timeline.

  This is an upgraded version of `source_table` that includes:
  - Summary stats grid at the top
  - Job history timeline in expanded view
  - Consistent styling with Discovery Dashboard

  ## Attributes

  - `sources` - List of source data maps
  - `expanded` - MapSet of expanded source slugs
  - `source_errors` - Map of source_id => list of errors
  - `show_summary` - Whether to show the summary grid (default: true)

  ## Examples

      <.source_table_enhanced
        sources={@source_data}
        expanded={@expanded_sources}
        source_errors={@source_errors}
      />
  """
  attr :sources, :list, required: true
  attr :expanded, :any, required: true
  attr :source_errors, :map, default: %{}
  attr :show_summary, :boolean, default: true

  def source_table_enhanced(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border mb-6">
      <div class="px-6 py-4 border-b flex items-center justify-between">
        <h2 class="text-lg font-semibold text-gray-900">Active Sources</h2>
        <div class="flex items-center gap-2">
          <%= if MapSet.size(@expanded) > 0 do %>
            <button
              phx-click="collapse_all_sources"
              class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-1"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
              </svg>
              Collapse All
            </button>
          <% else %>
            <button
              phx-click="expand_all_sources"
              class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-1"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
              Expand All
            </button>
          <% end %>
        </div>
      </div>

      <%= if @show_summary do %>
        <div class="px-6 py-4 border-b bg-gray-50">
          <.source_health_summary sources={@sources} />
        </div>
      <% end %>

      <%= if Enum.empty?(@sources) do %>
        <div class="px-6 py-12 text-center text-gray-500">
          <p>No active sources found for this city.</p>
        </div>
      <% else %>
        <div class="divide-y">
          <%= for source <- @sources do %>
            <.source_row_enhanced
              source={source}
              is_expanded={MapSet.member?(@expanded, source.slug)}
              errors={Map.get(@source_errors, source.id, [])}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc false
  attr :source, :map, required: true
  attr :is_expanded, :boolean, required: true
  attr :errors, :list, default: []

  def source_row_enhanced(assigns) do
    ~H"""
    <div>
      <button
        phx-click="toggle_source"
        phx-value-source={@source.slug}
        class="w-full px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
      >
        <div class="flex items-center gap-4">
          <!-- Expand Arrow -->
          <svg
            class={"w-4 h-4 text-gray-400 transition-transform #{if @is_expanded, do: "rotate-90"}"}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
          <!-- Source Name -->
          <span class="font-medium text-gray-900"><%= @source.name %></span>
        </div>

        <div class="flex items-center gap-4">
          <!-- Event Count Badge -->
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
            <%= @source.event_count %> events
          </span>
          <!-- Success Rate Badge (colored) -->
          <span class={"px-3 py-1 rounded text-sm font-semibold #{success_rate_badge_color(@source.success_rate)}"}>
            <%= @source.success_rate %>%
          </span>
        </div>
      </button>

      <!-- Expanded Content with Job Timeline -->
      <%= if @is_expanded do %>
        <div class="px-6 pb-6 pt-2 bg-gray-50 border-t">
          <!-- Job History Timeline -->
          <%= if Map.has_key?(@source, :recent_jobs) and not Enum.empty?(@source.recent_jobs) do %>
            <div class="mb-4">
              <div class="flex items-center justify-between mb-2">
                <h4 class="text-sm font-semibold text-gray-700">Recent Job History</h4>
                <span class="text-xs text-gray-500"><%= length(@source.recent_jobs) %> runs</span>
              </div>
              <.job_history_timeline jobs={@source.recent_jobs} />
            </div>
          <% end %>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- Source Statistics -->
            <div>
              <h4 class="text-sm font-semibold text-gray-700 mb-3">Source Statistics</h4>
              <div class="space-y-3">
                <.health_component_bar
                  label="Job Success Rate"
                  value={@source.success_rate}
                  weight=""
                  color={component_color(@source.success_rate)}
                  target={90}
                  description="Last 7 days"
                  show_status={true}
                />
                <div class="flex items-center justify-between text-sm">
                  <span class="text-gray-600">Total Jobs (7d)</span>
                  <span class="font-medium"><%= Map.get(@source, :total_jobs, 0) %></span>
                </div>
                <div class="flex items-center justify-between text-sm">
                  <span class="text-gray-600">Events Created</span>
                  <span class="font-medium"><%= @source.event_count %></span>
                </div>
              </div>
            </div>

            <!-- Recent Errors -->
            <div>
              <h4 class="text-sm font-semibold text-gray-700 mb-3">Recent Errors (24h)</h4>
              <%= if Enum.empty?(@errors) do %>
                <div class="text-sm text-gray-500 py-2">
                  ✓ No errors in the last 24 hours
                </div>
              <% else %>
                <div class="space-y-2 max-h-48 overflow-y-auto">
                  <%= for error <- Enum.take(@errors, 5) do %>
                    <div class="text-sm p-2 bg-white rounded border">
                      <div class="flex items-center gap-2 mb-1">
                        <.status_badge state={error.state} />
                        <span class="text-gray-500 text-xs">
                          <%= time_ago_in_words(error.attempted_at) %>
                        </span>
                      </div>
                      <div class="text-gray-700">
                        <span class="font-medium"><%= format_worker_name(error.worker) %></span>
                        <%= if error.error_category do %>
                          <span class="text-gray-400 mx-1">•</span>
                          <span class="text-orange-600"><%= error.error_category %></span>
                        <% end %>
                      </div>
                      <%= if error.error_message do %>
                        <div class="text-gray-500 text-xs mt-1 truncate" title={error.error_message}>
                          <%= String.slice(error.error_message || "", 0, 100) %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <%= if length(@errors) > 5 do %>
                    <div class="text-xs text-gray-500 pt-1">
                      + <%= length(@errors) - 5 %> more errors
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Quick Actions -->
          <div class="mt-4 pt-4 border-t flex items-center gap-4">
            <.link
              navigate={~p"/admin/job-executions?source=#{@source.slug}"}
              class="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
              </svg>
              View Job Executions
            </.link>
            <.link
              navigate={~p"/admin/error-trends?source=#{@source.slug}"}
              class="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
              </svg>
              View Error Trends
            </.link>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Helper Functions (Public for use in LiveViews)
  # ============================================================================

  @doc """
  Returns success rate badge color classes based on the rate.
  Used for the colored success rate badges in source rows.

  - ≥95%: Green (healthy)
  - ≥80%: Yellow (warning)
  - <80%: Red (critical)
  """
  def success_rate_badge_color(rate) when rate >= 95, do: "bg-green-100 text-green-800"
  def success_rate_badge_color(rate) when rate >= 80, do: "bg-yellow-100 text-yellow-800"
  def success_rate_badge_color(_rate), do: "bg-red-100 text-red-800"

  @doc """
  Formats job timestamp for display in timeline tooltips.
  """
  def format_job_time(%{completed_at: completed_at}) when not is_nil(completed_at) do
    Calendar.strftime(completed_at, "%Y-%m-%d %H:%M")
  end
  def format_job_time(%{attempted_at: attempted_at}) when not is_nil(attempted_at) do
    Calendar.strftime(attempted_at, "%Y-%m-%d %H:%M")
  end
  def format_job_time(_), do: "Unknown time"

  @doc """
  Returns status indicator tuple: {emoji, label, color_class}
  """
  def status_indicator(:healthy), do: {"🟢", "Healthy", "text-green-600"}
  def status_indicator(:warning), do: {"🟡", "Warning", "text-yellow-600"}
  def status_indicator(:critical), do: {"🔴", "Critical", "text-red-600"}
  def status_indicator(:disabled), do: {"⚪", "Disabled", "text-gray-400"}
  def status_indicator(:unknown), do: {"⚫", "Unknown", "text-gray-500"}
  def status_indicator(_), do: {"⚫", "Unknown", "text-gray-500"}

  @doc """
  Returns CSS classes for status backgrounds and text.
  """
  def status_classes(:healthy), do: "bg-green-100 text-green-800"
  def status_classes(:warning), do: "bg-yellow-100 text-yellow-800"
  def status_classes(:critical), do: "bg-red-100 text-red-800"
  def status_classes(:disabled), do: "bg-gray-100 text-gray-800"
  def status_classes(:unknown), do: "bg-gray-100 text-gray-600"
  def status_classes(_), do: "bg-gray-100 text-gray-600"

  @doc """
  Calculates sparkline bar heights from data (0-100 scale).
  """
  def sparkline_heights(data) when is_list(data) and length(data) > 0 do
    max_val = Enum.max(data, fn -> 1 end)
    max_val = if max_val == 0, do: 1, else: max_val

    Enum.map(data, fn val ->
      percentage = round(val / max_val * 100)
      # Ensure minimum visible height if there's any data
      if val > 0, do: max(percentage, 10), else: 0
    end)
  end

  def sparkline_heights(_), do: List.duplicate(0, 7)

  @doc """
  Formats a change value with + prefix for positive numbers.
  """
  def format_change(change) when change > 0, do: "+#{change}%"
  def format_change(change), do: "#{change}%"

  @doc """
  Formats time ago in human-readable words.
  """
  def time_ago_in_words(nil), do: "Never"

  def time_ago_in_words(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      true -> "#{div(diff, 86400)} days ago"
    end
  end

  @doc """
  Returns the appropriate color atom based on a percentage value.
  Used for health component bars and source statistics.
  """
  def component_color(value) when value >= 80, do: :green
  def component_color(value) when value >= 50, do: :yellow
  def component_color(_), do: :red

  @doc """
  Formats an Oban worker module name for display.
  Extracts the job type from the full module path.

  ## Examples

      iex> format_worker_name("EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob")
      "Sync"

      iex> format_worker_name("EventasaurusDiscovery.Sources.WeekPl.Jobs.EventDetailJob")
      "EventDetail"
  """
  def format_worker_name(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> List.last()
    |> String.replace(~r/Job$/, "")
  end

  def format_worker_name(_), do: "Unknown"

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp ring_color(:healthy), do: "text-green-500"
  defp ring_color(:warning), do: "text-yellow-500"
  defp ring_color(:critical), do: "text-red-500"
  defp ring_color(:disabled), do: "text-gray-300"
  defp ring_color(_), do: "text-gray-400"

  defp text_color(:healthy), do: "text-green-600"
  defp text_color(:warning), do: "text-yellow-600"
  defp text_color(:critical), do: "text-red-600"
  defp text_color(:disabled), do: "text-gray-400"
  defp text_color(_), do: "text-gray-600"

  defp bar_color_class(:blue), do: "bg-blue-500"
  defp bar_color_class(:green), do: "bg-green-500"
  defp bar_color_class(:yellow), do: "bg-yellow-500"
  defp bar_color_class(:red), do: "bg-red-500"
  defp bar_color_class(:purple), do: "bg-purple-500"
  defp bar_color_class(:indigo), do: "bg-indigo-500"
  defp bar_color_class(_), do: "bg-gray-400"

  defp text_color_class(:blue), do: "text-blue-600"
  defp text_color_class(:green), do: "text-green-600"
  defp text_color_class(:yellow), do: "text-yellow-600"
  defp text_color_class(:red), do: "text-red-600"
  defp text_color_class(:purple), do: "text-purple-600"
  defp text_color_class(:indigo), do: "text-indigo-600"
  defp text_color_class(_), do: "text-gray-600"

  defp border_color_class(:blue), do: "border-blue-500"
  defp border_color_class(:green), do: "border-green-500"
  defp border_color_class(:yellow), do: "border-yellow-500"
  defp border_color_class(:red), do: "border-red-500"
  defp border_color_class(:purple), do: "border-purple-500"
  defp border_color_class(:indigo), do: "border-indigo-500"
  defp border_color_class(:gray), do: "border-gray-400"
  defp border_color_class(_), do: "border-gray-400"

  # Background colors for icon circles (admin_stat_card)
  defp bg_color_class(:blue), do: "bg-blue-100"
  defp bg_color_class(:green), do: "bg-green-100"
  defp bg_color_class(:yellow), do: "bg-yellow-100"
  defp bg_color_class(:red), do: "bg-red-100"
  defp bg_color_class(:purple), do: "bg-purple-100"
  defp bg_color_class(:indigo), do: "bg-indigo-100"
  defp bg_color_class(_), do: "bg-gray-100"

  # Icon colors for admin_stat_card
  defp icon_color_class(:blue), do: "w-6 h-6 text-blue-600"
  defp icon_color_class(:green), do: "w-6 h-6 text-green-600"
  defp icon_color_class(:yellow), do: "w-6 h-6 text-yellow-600"
  defp icon_color_class(:red), do: "w-6 h-6 text-red-600"
  defp icon_color_class(:purple), do: "w-6 h-6 text-purple-600"
  defp icon_color_class(:indigo), do: "w-6 h-6 text-indigo-600"
  defp icon_color_class(_), do: "w-6 h-6 text-gray-600"

  # Admin text colors (darker for large numbers)
  defp admin_text_color_class(:blue), do: "text-blue-900"
  defp admin_text_color_class(:green), do: "text-green-900"
  defp admin_text_color_class(:yellow), do: "text-yellow-900"
  defp admin_text_color_class(:red), do: "text-red-900"
  defp admin_text_color_class(:purple), do: "text-purple-900"
  defp admin_text_color_class(:indigo), do: "text-indigo-900"
  defp admin_text_color_class(_), do: "text-gray-900"

  defp format_value(nil), do: "0"
  defp format_value(num) when is_integer(num), do: Integer.to_string(num)

  defp format_value(num) when is_float(num) do
    num |> round() |> Integer.to_string()
  end

  defp format_value(val), do: to_string(val)

  defp badge_classes("success"), do: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
  defp badge_classes("failure"), do: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
  defp badge_classes("cancelled"), do: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800"
  defp badge_classes("discarded"), do: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
  defp badge_classes(_), do: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600"

  defp badge_icon("success"), do: "✓"
  defp badge_icon("failure"), do: "✗"
  defp badge_icon("cancelled"), do: "⊘"
  defp badge_icon("discarded"), do: "⊗"
  defp badge_icon(_), do: "?"

  defp badge_label("success"), do: "Success"
  defp badge_label("failure"), do: "Failed"
  defp badge_label("cancelled"), do: "Cancelled"
  defp badge_label("discarded"), do: "Discarded"
  defp badge_label(state), do: String.capitalize(state)
end
