defmodule EventasaurusWeb.Live.Components.MovieCastComponent do
  @moduledoc """
  Cast section component for movie/TV show display.

  Displays cast members with photos, names, and character names
  in a responsive grid layout.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:cast, fn -> [] end)
     |> assign_new(:crew, fn -> [] end)
     |> assign_new(:director, fn -> nil end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-lg p-6">
      <div class="space-y-6">
        <!-- Top Billed Cast -->
        <%= if @display_cast && length(@display_cast) > 0 do %>
          <div>
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Top Billed Cast</h2>
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
              <%= for cast_member <- @display_cast do %>
                <.cast_card cast_member={cast_member} compact={@compact} />
              <% end %>
            </div>

            <%= if @has_more_cast do %>
              <div class="mt-4 text-center">
                <button
                  phx-click="toggle_full_cast"
                  phx-target={@myself}
                  class="text-indigo-600 hover:text-indigo-500 font-medium"
                >
                  <%= if @show_full_cast do %>
                    Show Less
                  <% else %>
                    View Full Cast (<%= length(@cast) %> total)
                  <% end %>
                </button>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- Featured Crew -->
        <%= if @featured_crew && length(@featured_crew) > 0 do %>
          <div>
            <h3 class="text-xl font-semibold text-gray-900 mb-4">Featured Crew</h3>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for crew_member <- @featured_crew do %>
                <.crew_card crew_member={crew_member} compact={@compact} />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_full_cast", _params, socket) do
    show_full_cast = !socket.assigns.show_full_cast
    display_cast = get_display_cast(socket.assigns.cast, show_full_cast, socket.assigns.compact)

    {:noreply,
     socket
     |> assign(:show_full_cast, show_full_cast)
     |> assign(:display_cast, display_cast)}
  end

  # Private function components

  defp cast_card(assigns) do
    ~H"""
    <div class="text-center">
      <div class="relative mb-3">
        <%= if @cast_member["profile_path"] do %>
          <img
            src={RichDataDisplayComponent.tmdb_image_url(@cast_member["profile_path"], "w185")}
            alt={@cast_member["name"]}
            class="w-full aspect-[2/3] object-cover rounded-lg shadow-sm"
            loading="lazy"
          />
        <% else %>
          <div class="w-full aspect-[2/3] bg-gray-200 rounded-lg flex items-center justify-center">
            <.icon name="hero-user" class="w-8 h-8 text-gray-400" />
          </div>
        <% end %>
      </div>

      <div class="space-y-1">
        <p class="text-sm font-medium text-gray-900 line-clamp-2">
          <%= @cast_member["name"] %>
        </p>
        <%= if @cast_member["character"] do %>
          <p class="text-xs text-gray-500 line-clamp-2">
            <%= @cast_member["character"] %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp crew_card(assigns) do
    ~H"""
    <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
      <%= if @crew_member["profile_path"] do %>
        <img
          src={RichDataDisplayComponent.tmdb_image_url(@crew_member["profile_path"], "w185")}
          alt={@crew_member["name"]}
          class="w-12 h-12 rounded-full object-cover flex-shrink-0"
          loading="lazy"
        />
      <% else %>
        <div class="w-12 h-12 rounded-full bg-gray-300 flex items-center justify-center flex-shrink-0">
          <.icon name="hero-user" class="w-6 h-6 text-gray-500" />
        </div>
      <% end %>

      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium text-gray-900 truncate">
          <%= @crew_member["name"] %>
        </p>
        <p class="text-sm text-gray-500 truncate">
          <%= @crew_member["job"] %>
        </p>
      </div>
    </div>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    cast = socket.assigns.cast || []
    crew = socket.assigns.crew || []

    socket
    |> assign(:show_full_cast, false)
    |> assign(:display_cast, get_display_cast(cast, false, socket.assigns.compact))
    |> assign(:has_more_cast, length(cast) > get_initial_cast_limit(socket.assigns.compact))
    |> assign(:featured_crew, get_featured_crew(crew))
  end

  defp get_display_cast(cast, show_full_cast, compact) do
    limit = if show_full_cast do
      length(cast)
    else
      get_initial_cast_limit(compact)
    end

    cast
    |> Enum.take(limit)
  end

  defp get_initial_cast_limit(true), do: 6   # Compact mode
  defp get_initial_cast_limit(false), do: 12 # Full mode

  defp get_featured_crew(crew) when is_list(crew) do
    # Get important crew members, excluding those already shown in overview
    important_jobs = [
      "Director of Photography", "Cinematography",
      "Original Music Composer", "Music",
      "Costume Design", "Costume Designer",
      "Production Design", "Production Designer",
      "Film Editor", "Editor", "Editing",
      "Casting", "Casting Director"
    ]

    crew
    |> Enum.filter(&(&1["job"] in important_jobs))
    |> Enum.uniq_by(&(&1["name"])) # Remove duplicates by name
    |> Enum.take(6) # Limit to 6 featured crew members
  end
  defp get_featured_crew(_), do: []
end
