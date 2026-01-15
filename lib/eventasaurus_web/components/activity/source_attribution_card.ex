defmodule EventasaurusWeb.Components.Activity.SourceAttributionCard do
  @moduledoc """
  Sidebar component displaying event source attribution.

  Shows where event data comes from with links, logos, and timestamps.
  Optionally includes a refresh availability button for supported sources.
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN
  alias EventasaurusWeb.Helpers.SourceAttribution

  @doc """
  Renders the source attribution card for the sidebar.

  ## Attributes

    * `:sources` - Required. List of event sources.
    * `:is_refreshable` - Whether the event supports availability refresh.
    * `:refreshing` - Whether a refresh is currently in progress.
    * `:class` - Optional. Additional CSS classes for the container.

  ## Examples

      <SourceAttributionCard.source_attribution_card
        sources={@event.sources}
        is_refreshable={EventRefresh.refreshable?(@event)}
        refreshing={@refreshing_availability}
      />
  """
  attr :sources, :list, required: true
  attr :is_refreshable, :boolean, default: false
  attr :refreshing, :boolean, default: false
  attr :class, :string, default: ""

  def source_attribution_card(assigns) do
    assigns =
      assign(
        assigns,
        :deduplicated_sources,
        SourceAttribution.deduplicate_sources(assigns.sources)
      )

    ~H"""
    <div class={["bg-white rounded-xl border border-gray-200 p-4", @class]}>
      <!-- Header with optional refresh button -->
      <div class="flex items-center justify-between mb-3">
        <h4 class="text-sm font-medium text-gray-500">
          <%= gettext("Event Sources") %>
        </h4>

        <%= if @is_refreshable do %>
          <button
            phx-click="refresh_availability"
            disabled={@refreshing}
            class={[
              "inline-flex items-center px-2 py-1 text-xs font-medium rounded transition-colors",
              if(@refreshing,
                do: "bg-gray-100 text-gray-400 cursor-not-allowed",
                else: "bg-gray-100 text-gray-600 hover:bg-gray-200"
              )
            ]}
          >
            <%= if @refreshing do %>
              <svg
                class="animate-spin w-3 h-3 mr-1"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                >
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
              <%= gettext("Refreshing") %>
            <% else %>
              <Heroicons.arrow_path class="w-3 h-3 mr-1" />
              <%= gettext("Refresh") %>
            <% end %>
          </button>
        <% end %>
      </div>

      <!-- Source List -->
      <ul class="space-y-2">
        <%= for source <- @deduplicated_sources do %>
          <.source_item source={source} />
        <% end %>
      </ul>
    </div>
    """
  end

  # Renders a single source item in the list with logo thumbnail.
  attr :source, :map, required: true

  defp source_item(assigns) do
    logo_url = SourceAttribution.get_source_logo_url(assigns.source)

    assigns =
      assigns
      |> assign(:source_url, SourceAttribution.get_source_url(assigns.source))
      |> assign(:source_name, SourceAttribution.get_source_name(assigns.source))
      |> assign(:source_initial, SourceAttribution.get_source_initial(assigns.source))
      |> assign(:logo_url, logo_url && CDN.url(logo_url, width: 48, height: 48, fit: "contain"))
      |> assign(
        :relative_time,
        SourceAttribution.format_relative_time(assigns.source.last_seen_at)
      )

    ~H"""
    <li class="flex items-center gap-3 text-sm">
      <!-- Logo or Initial Fallback -->
      <div class="flex-shrink-0">
        <%= if @logo_url do %>
          <img
            src={@logo_url}
            alt={@source_name}
            class="w-6 h-6 rounded-md object-contain bg-gray-50"
          />
        <% else %>
          <div class="w-6 h-6 rounded-md bg-indigo-100 flex items-center justify-center">
            <span class="text-xs font-semibold text-indigo-600">
              <%= @source_initial %>
            </span>
          </div>
        <% end %>
      </div>
      <!-- Source Name and Link -->
      <div class="flex-1 min-w-0">
        <%= if @source_url do %>
          <a
            href={@source_url}
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-indigo-600 hover:text-indigo-800 truncate block"
          >
            <%= @source_name %>
            <Heroicons.arrow_top_right_on_square class="w-3 h-3 inline ml-0.5" />
          </a>
        <% else %>
          <span class="font-medium text-gray-700 truncate block">
            <%= @source_name %>
          </span>
        <% end %>
      </div>
      <!-- Last Seen Timestamp -->
      <span class="text-gray-400 text-xs flex-shrink-0">
        <%= @relative_time %>
      </span>
    </li>
    """
  end
end
