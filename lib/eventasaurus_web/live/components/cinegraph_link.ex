defmodule EventasaurusWeb.Live.Components.CinegraphLink do
  @moduledoc """
  Utility component for generating cross-site links to Cinegraph.

  This component creates styled external links to Cinegraph's movie pages,
  allowing users to get more detailed movie information, reviews, and ratings.

  ## Features

  - Generates correct Cinegraph URLs based on TMDB ID
  - Supports multiple link styles (button, text, pill)
  - Opens in new tab with proper security attributes
  - Includes Cinegraph branding/icon

  ## Props

  - `tmdb_id` - TMDB ID of the movie (required)
  - `title` - Movie title for display (optional, uses default text if not provided)
  - `variant` - `:button` | `:text` | `:pill` | `:compact` | `:dark` (default: `:button`)
  - `class` - Additional CSS classes to apply
  """

  use Phoenix.Component
  import EventasaurusWeb.CoreComponents

  @cinegraph_base_url "https://cinegraph.com"

  attr :tmdb_id, :any, required: true
  attr :title, :string, default: nil
  attr :variant, :atom, default: :button
  attr :class, :string, default: nil

  def cinegraph_link(assigns) do
    assigns =
      assigns
      |> assign_new(:url, fn -> build_cinegraph_url(assigns.tmdb_id) end)
      |> assign_new(:display_text, fn ->
        if assigns.title do
          "View #{assigns.title} on Cinegraph"
        else
          "View on Cinegraph"
        end
      end)

    ~H"""
    <a
      href={@url}
      target="_blank"
      rel="noopener noreferrer"
      class={[link_classes(@variant), @class]}
      title={@display_text}
    >
      <.cinegraph_icon variant={@variant} />
      <span><%= link_text(@variant, @title) %></span>
      <.icon name="hero-arrow-top-right-on-square" class={external_icon_classes(@variant)} />
    </a>
    """
  end

  # Slot-based version for custom content
  attr :tmdb_id, :any, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def cinegraph_link_custom(assigns) do
    assigns = assign_new(assigns, :url, fn -> build_cinegraph_url(assigns.tmdb_id) end)

    ~H"""
    <a
      href={@url}
      target="_blank"
      rel="noopener noreferrer"
      class={@class}
      title="View on Cinegraph"
    >
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  # Simple badge component showing Cinegraph availability
  attr :tmdb_id, :any, required: true
  attr :variant, :atom, default: :light

  def cinegraph_badge(assigns) do
    assigns = assign_new(assigns, :url, fn -> build_cinegraph_url(assigns.tmdb_id) end)

    ~H"""
    <a
      href={@url}
      target="_blank"
      rel="noopener noreferrer"
      class={badge_classes(@variant)}
      title="View more on Cinegraph"
    >
      <.cinegraph_icon variant={:badge} />
      <span class="text-xs font-semibold">Cinegraph</span>
    </a>
    """
  end

  # Private components

  defp cinegraph_icon(assigns) do
    # Using a film icon as placeholder - in production this could be Cinegraph's actual logo
    ~H"""
    <svg
      class={icon_classes(@variant)}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M18 4l2 4h-3l-2-4h-2l2 4h-3l-2-4H8l2 4H7L5 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V4h-4z" />
    </svg>
    """
  end

  # CSS class helpers

  defp link_classes(:button) do
    [
      "inline-flex items-center gap-2 px-4 py-2",
      "bg-gradient-to-r from-purple-600 to-indigo-600",
      "text-white font-medium rounded-lg",
      "hover:from-purple-700 hover:to-indigo-700",
      "transition-all shadow-sm hover:shadow-md"
    ]
  end

  defp link_classes(:text) do
    [
      "inline-flex items-center gap-1.5",
      "text-indigo-600 hover:text-indigo-800",
      "font-medium transition-colors"
    ]
  end

  defp link_classes(:pill) do
    [
      "inline-flex items-center gap-1.5 px-3 py-1.5",
      "bg-indigo-100 text-indigo-700",
      "rounded-full text-sm font-medium",
      "hover:bg-indigo-200 transition-colors"
    ]
  end

  defp link_classes(:compact) do
    [
      "inline-flex items-center gap-1",
      "text-sm text-gray-500 hover:text-indigo-600",
      "transition-colors"
    ]
  end

  defp link_classes(:dark) do
    [
      "inline-flex items-center gap-2 px-4 py-2",
      "bg-white/10 backdrop-blur-sm border border-white/20",
      "text-white font-medium rounded-lg",
      "hover:bg-white/20 hover:border-white/30",
      "transition-all"
    ]
  end

  # Fallback for unknown variants - defaults to button style
  defp link_classes(_), do: link_classes(:button)

  defp icon_classes(:button), do: "w-5 h-5"
  defp icon_classes(:text), do: "w-4 h-4"
  defp icon_classes(:pill), do: "w-4 h-4"
  defp icon_classes(:compact), do: "w-3.5 h-3.5"
  defp icon_classes(:dark), do: "w-5 h-5"
  defp icon_classes(:badge), do: "w-3.5 h-3.5"
  defp icon_classes(_), do: "w-4 h-4"

  defp external_icon_classes(:button), do: "w-4 h-4 opacity-70"
  defp external_icon_classes(:text), do: "w-3.5 h-3.5 opacity-60"
  defp external_icon_classes(:pill), do: "w-3 h-3 opacity-60"
  defp external_icon_classes(:compact), do: "w-3 h-3 opacity-50"
  defp external_icon_classes(:dark), do: "w-4 h-4 opacity-70"
  defp external_icon_classes(_), do: "w-3.5 h-3.5 opacity-60"

  defp badge_classes(:light) do
    [
      "inline-flex items-center gap-1 px-2 py-1",
      "bg-gray-100 text-gray-700 rounded",
      "hover:bg-gray-200 transition-colors"
    ]
  end

  defp badge_classes(:dark) do
    [
      "inline-flex items-center gap-1 px-2 py-1",
      "bg-white/10 text-white/80 rounded",
      "hover:bg-white/20 transition-colors"
    ]
  end

  defp link_text(:button, nil), do: "View on Cinegraph"
  defp link_text(:button, _title), do: "More on Cinegraph"
  defp link_text(:text, nil), do: "View on Cinegraph"
  defp link_text(:text, _title), do: "More details"
  defp link_text(:pill, _), do: "Cinegraph"
  defp link_text(:compact, _), do: "Cinegraph"
  defp link_text(:dark, nil), do: "View on Cinegraph"
  defp link_text(:dark, _title), do: "More on Cinegraph"
  defp link_text(_, _), do: "Cinegraph"

  # URL building

  defp build_cinegraph_url(tmdb_id) when is_integer(tmdb_id) do
    "#{@cinegraph_base_url}/movies/#{tmdb_id}"
  end

  defp build_cinegraph_url(tmdb_id) when is_binary(tmdb_id) do
    sanitized_id = tmdb_id |> String.trim() |> URI.encode()
    "#{@cinegraph_base_url}/movies/#{sanitized_id}"
  end

  defp build_cinegraph_url(nil), do: @cinegraph_base_url

  defp build_cinegraph_url(%{"id" => id}), do: build_cinegraph_url(id)
  defp build_cinegraph_url(%{id: id}), do: build_cinegraph_url(id)
  defp build_cinegraph_url(_), do: @cinegraph_base_url
end
