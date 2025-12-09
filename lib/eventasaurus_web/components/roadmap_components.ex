defmodule EventasaurusWeb.RoadmapComponents do
  @moduledoc """
  Components for the public Roadmap page.
  """
  use Phoenix.Component
  use EventasaurusWeb, :html

  @doc """
  Renders the main roadmap timeline container.
  """
  attr :items, :list, required: true

  def roadmap_timeline(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <div class="space-y-0 relative" role="list" aria-label="Roadmap items">
        <%!-- Continuous vertical line for the entire list --%>
        <div class="absolute left-4 md:left-[8.5rem] top-4 bottom-0 w-px bg-zinc-200 hidden md:block"></div>

        <.roadmap_quarter_section :for={section <- @items} section={section} />
      </div>
    </div>
    """
  end

  @doc """
  Renders a quarter section with its features.
  """
  attr :section, :map, required: true

  def roadmap_quarter_section(assigns) do
    ~H"""
    <div class="relative pb-16 last:pb-0">
       <%!-- Quarter Heading Marker --%>
       <div class="flex flex-col md:flex-row gap-6 md:gap-8 mb-8">
          <div class="md:w-32 md:shrink-0 md:text-right pt-1 relative">
             <span class={["inline-flex items-center rounded-full px-2.5 py-0.5 text-sm font-bold ring-1 ring-inset shadow-sm z-10 relative bg-white", status_badge_color(@section.status)]}>
               <%= @section.quarter %>
             </span>
          </div>
          <div class="flex-1">
             <div class="space-y-6">
                <.feature_card :for={feature <- @section.features} feature={feature} />
             </div>
          </div>
       </div>
    </div>
    """
  end

  @doc """
  Renders a single feature card.
  """
  attr :feature, :map, required: true

  def feature_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl p-6 shadow-sm border border-zinc-200/60 hover:shadow-md transition-shadow relative overflow-hidden group">
      <%!-- Status Indicator Strip --%>
      <div class={["absolute top-0 left-0 w-1 h-full", feature_status_color(@feature.status)]}></div>

      <div class="pl-2">
        <div class="flex flex-wrap items-center gap-3 mb-3">
          <span class={["inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset", feature_status_pill(@feature.status)]}>
            <%= @feature.status %>
          </span>
          <%= for tag <- @feature.tags do %>
            <.tag_badge tag={tag} />
          <% end %>
        </div>

        <h3 class="text-xl font-bold text-zinc-900 mb-2 group-hover:text-indigo-600 transition-colors"><%= @feature.title %></h3>
        <p class="text-zinc-600 leading-relaxed"><%= @feature.description %></p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a tag badge.
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
    <span class={["inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset", @bg_color, @text_color, @ring_color]}>
      <%= @tag %>
    </span>
    """
  end

  defp status_badge_color(status) do
    case status do
      "current" -> "text-indigo-700 ring-indigo-700/10"
      "upcoming" -> "text-zinc-700 ring-zinc-700/10"
      "future" -> "text-zinc-500 ring-zinc-500/10"
      _ -> "text-zinc-700 ring-zinc-700/10"
    end
  end

  defp feature_status_color(status) do
    case status do
      "In Progress" -> "bg-indigo-500"
      "Planned" -> "bg-blue-500"
      "Research" -> "bg-amber-500"
      "Concept" -> "bg-purple-500"
      _ -> "bg-zinc-300"
    end
  end

  defp feature_status_pill(status) do
    case status do
      "In Progress" -> "bg-indigo-50 text-indigo-700 ring-indigo-700/10"
      "Planned" -> "bg-blue-50 text-blue-700 ring-blue-700/10"
      "Research" -> "bg-amber-50 text-amber-700 ring-amber-700/10"
      "Concept" -> "bg-purple-50 text-purple-700 ring-purple-700/10"
      _ -> "bg-zinc-50 text-zinc-700 ring-zinc-700/10"
    end
  end

  defp tag_color(tag) do
    case String.downcase(tag) do
      "mobile" -> {"bg-sky-50", "text-sky-700", "ring-sky-700/10"}
      "platform" -> {"bg-slate-50", "text-slate-700", "ring-slate-700/10"}
      "api" -> {"bg-emerald-50", "text-emerald-700", "ring-emerald-700/10"}
      "devtools" -> {"bg-lime-50", "text-lime-700", "ring-lime-700/10"}
      "ai" -> {"bg-fuchsia-50", "text-fuchsia-700", "ring-fuchsia-700/10"}
      "social" -> {"bg-violet-50", "text-violet-700", "ring-violet-700/10"}
      "design" -> {"bg-pink-50", "text-pink-700", "ring-pink-700/10"}
      "analytics" -> {"bg-cyan-50", "text-cyan-700", "ring-cyan-700/10"}
      "business" -> {"bg-gray-50", "text-gray-700", "ring-gray-700/10"}
      _ -> {"bg-zinc-50", "text-zinc-700", "ring-zinc-700/10"}
    end
  end
end
