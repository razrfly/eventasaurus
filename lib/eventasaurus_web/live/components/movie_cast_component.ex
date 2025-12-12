defmodule EventasaurusWeb.Live.Components.MovieCastComponent do
  @moduledoc """
  Cast section component for movie/TV show display.

  Displays cast members with photos, names, and character names
  in a responsive grid layout. Includes top billing badges for
  the first 3 cast members (gold, silver, bronze).

  ## Props

  - `cast` - List of cast members from TMDB credits
  - `crew` - List of crew members from TMDB credits
  - `compact` - Boolean for compact display mode (default: false)
  - `show_badges` - Boolean to show top billing badges (default: true)
  - `variant` - `:card` | `:dark` (default: `:card`)
  - `max_cast` - Maximum number of cast to show initially (overrides compact default)
  - `show_crew` - Boolean to show featured crew section (default: true)
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
     |> assign_new(:show_badges, fn -> true end)
     |> assign_new(:variant, fn -> :card end)
     |> assign_new(:max_cast, fn -> nil end)
     |> assign_new(:show_crew, fn -> true end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={section_container_classes(@variant)}>
      <div class="space-y-6">
        <!-- Top Billed Cast -->
        <%= if @display_cast && length(@display_cast) > 0 do %>
          <div>
            <h2 class={section_title_classes(@variant)}>Top Billed Cast</h2>
            <div class={[cast_grid_classes(@compact), "transition-all duration-300 ease-in-out"]}>
              <%= for {cast_member, index} <- Enum.with_index(@display_cast) do %>
                <.cast_card
                  cast_member={cast_member}
                  compact={@compact}
                  billing_position={index + 1}
                  show_badge={@show_badges && index < 3}
                  variant={@variant}
                />
              <% end %>
            </div>

            <%= if @has_more_cast do %>
              <div class="mt-6 text-center">
                <button
                  phx-click="toggle_full_cast"
                  phx-target={@myself}
                  class={expand_button_classes(@variant)}
                >
                  <%= if @show_full_cast do %>
                    <.icon name="hero-chevron-up" class="w-4 h-4 mr-1" />
                    Show Less
                  <% else %>
                    <.icon name="hero-chevron-down" class="w-4 h-4 mr-1" />
                    View Full Cast (<%= length(@cast) %> total)
                  <% end %>
                </button>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- Featured Crew -->
        <%= if @show_crew && @featured_crew && length(@featured_crew) > 0 do %>
          <div>
            <h3 class={crew_title_classes(@variant)}>Featured Crew</h3>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for crew_member <- @featured_crew do %>
                <.crew_card crew_member={crew_member} compact={@compact} variant={@variant} />
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
    initial_limit = socket.assigns.initial_limit
    display_cast = get_display_cast(socket.assigns.cast, show_full_cast, initial_limit)

    {:noreply,
     socket
     |> assign(:show_full_cast, show_full_cast)
     |> assign(:display_cast, display_cast)}
  end

  # Private function components

  defp cast_card(assigns) do
    assigns = assign_new(assigns, :initials, fn -> get_initials(assigns.cast_member["name"]) end)

    ~H"""
    <div class={cast_card_classes(@variant)}>
      <div class="relative mb-3">
        <%= if @cast_member["profile_path"] do %>
          <img
            src={RichDataDisplayComponent.tmdb_image_url(@cast_member["profile_path"], "w185")}
            alt={@cast_member["name"]}
            class={cast_image_classes(@variant)}
            loading="lazy"
          />
        <% else %>
          <div class={cast_placeholder_classes(@variant)}>
            <span class={initials_classes(@variant)}><%= @initials %></span>
          </div>
        <% end %>

        <!-- Top Billing Badge -->
        <%= if @show_badge do %>
          <.billing_badge position={@billing_position} />
        <% end %>
      </div>

      <div class="space-y-1">
        <p class={cast_name_classes(@variant)}>
          <%= @cast_member["name"] %>
        </p>
        <%= if @cast_member["character"] do %>
          <p class={cast_character_classes(@variant)}>
            <%= @cast_member["character"] %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp billing_badge(assigns) do
    ~H"""
    <div class={[
      "absolute -top-2 -right-2 w-7 h-7 rounded-full flex items-center justify-center",
      "shadow-lg ring-2 ring-white font-bold text-xs",
      badge_color_classes(@position)
    ]}>
      <%= @position %>
    </div>
    """
  end

  defp badge_color_classes(1),
    do: "bg-gradient-to-br from-yellow-300 to-yellow-500 text-yellow-900"

  defp badge_color_classes(2), do: "bg-gradient-to-br from-gray-200 to-gray-400 text-gray-800"
  defp badge_color_classes(3), do: "bg-gradient-to-br from-amber-500 to-amber-700 text-amber-100"
  defp badge_color_classes(_), do: "bg-gray-100 text-gray-600"

  defp crew_card(assigns) do
    assigns = assign_new(assigns, :initials, fn -> get_initials(assigns.crew_member["name"]) end)

    ~H"""
    <div class={crew_card_classes(@variant)}>
      <%= if @crew_member["profile_path"] do %>
        <img
          src={RichDataDisplayComponent.tmdb_image_url(@crew_member["profile_path"], "w185")}
          alt={@crew_member["name"]}
          class={crew_image_classes(@variant)}
          loading="lazy"
        />
      <% else %>
        <div class={crew_placeholder_classes(@variant)}>
          <span class={crew_initials_classes(@variant)}><%= @initials %></span>
        </div>
      <% end %>

      <div class="min-w-0 flex-1">
        <p class={crew_name_classes(@variant)}>
          <%= @crew_member["name"] %>
        </p>
        <p class={crew_job_classes(@variant)}>
          <%= @crew_member["job"] %>
        </p>
      </div>
    </div>
    """
  end

  # CSS class helpers for variants

  defp section_container_classes(:card), do: "bg-white rounded-lg p-6"
  defp section_container_classes(:dark), do: "bg-gray-900/50 backdrop-blur-sm rounded-lg p-6"

  defp section_title_classes(:card), do: "text-2xl font-bold text-gray-900 mb-4"
  defp section_title_classes(:dark), do: "text-2xl font-bold text-white mb-4"

  defp crew_title_classes(:card), do: "text-xl font-semibold text-gray-900 mb-4"
  defp crew_title_classes(:dark), do: "text-xl font-semibold text-white mb-4"

  defp cast_grid_classes(true), do: "grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-3"

  defp cast_grid_classes(false),
    do: "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4"

  defp expand_button_classes(:card) do
    "inline-flex items-center text-indigo-600 hover:text-indigo-500 font-medium transition-colors"
  end

  defp expand_button_classes(:dark) do
    "inline-flex items-center text-indigo-400 hover:text-indigo-300 font-medium transition-colors"
  end

  defp cast_card_classes(:card), do: "text-center group"
  defp cast_card_classes(:dark), do: "text-center group"

  defp cast_image_classes(:card) do
    "w-full aspect-[2/3] object-cover rounded-lg shadow-sm group-hover:shadow-md transition-shadow"
  end

  defp cast_image_classes(:dark) do
    "w-full aspect-[2/3] object-cover rounded-lg shadow-lg ring-1 ring-white/10 group-hover:ring-white/20 transition-all"
  end

  defp cast_placeholder_classes(:card) do
    "w-full aspect-[2/3] bg-gray-200 rounded-lg flex items-center justify-center"
  end

  defp cast_placeholder_classes(:dark) do
    "w-full aspect-[2/3] bg-gray-800 rounded-lg flex items-center justify-center ring-1 ring-white/10"
  end

  defp cast_name_classes(:card), do: "text-sm font-medium text-gray-900 line-clamp-2"
  defp cast_name_classes(:dark), do: "text-sm font-medium text-white line-clamp-2"

  defp cast_character_classes(:card), do: "text-xs text-gray-500 line-clamp-2"
  defp cast_character_classes(:dark), do: "text-xs text-gray-400 line-clamp-2"

  defp crew_card_classes(:card), do: "flex items-center space-x-3 p-3 bg-gray-50 rounded-lg"
  defp crew_card_classes(:dark), do: "flex items-center space-x-3 p-3 bg-white/5 rounded-lg"

  defp crew_image_classes(:card), do: "w-12 h-12 rounded-full object-cover flex-shrink-0"

  defp crew_image_classes(:dark),
    do: "w-12 h-12 rounded-full object-cover flex-shrink-0 ring-1 ring-white/10"

  defp crew_placeholder_classes(:card) do
    "w-12 h-12 rounded-full bg-gray-300 flex items-center justify-center flex-shrink-0"
  end

  defp crew_placeholder_classes(:dark) do
    "w-12 h-12 rounded-full bg-gray-700 flex items-center justify-center flex-shrink-0"
  end

  defp crew_name_classes(:card), do: "text-sm font-medium text-gray-900 truncate"
  defp crew_name_classes(:dark), do: "text-sm font-medium text-white truncate"

  defp crew_job_classes(:card), do: "text-sm text-gray-500 truncate"
  defp crew_job_classes(:dark), do: "text-sm text-gray-400 truncate"

  defp initials_classes(:card), do: "text-xl font-bold text-gray-500"
  defp initials_classes(:dark), do: "text-xl font-bold text-gray-400"

  defp crew_initials_classes(:card), do: "text-sm font-bold text-gray-500"
  defp crew_initials_classes(:dark), do: "text-sm font-bold text-gray-400"

  # Private functions

  defp get_initials(nil), do: "?"

  defp get_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp get_initials(_), do: "?"

  defp assign_computed_data(socket) do
    cast = socket.assigns.cast || []
    crew = socket.assigns.crew || []
    max_cast = socket.assigns.max_cast
    compact = socket.assigns.compact
    initial_limit = get_initial_cast_limit(compact, max_cast)

    socket
    |> assign(:show_full_cast, false)
    |> assign(:display_cast, get_display_cast(cast, false, initial_limit))
    |> assign(:has_more_cast, length(cast) > initial_limit)
    |> assign(:featured_crew, get_featured_crew(crew))
    |> assign(:initial_limit, initial_limit)
  end

  defp get_display_cast(cast, show_full_cast, initial_limit) do
    limit =
      if show_full_cast do
        length(cast)
      else
        initial_limit
      end

    cast
    |> Enum.take(limit)
  end

  # Use explicit max_cast if provided
  defp get_initial_cast_limit(_compact, max_cast) when is_integer(max_cast) and max_cast > 0,
    do: max_cast

  # Compact mode default
  defp get_initial_cast_limit(true, _), do: 6
  # Full mode default
  defp get_initial_cast_limit(false, _), do: 12

  defp get_featured_crew(crew) when is_list(crew) do
    # Get important crew members, excluding those already shown in overview
    important_jobs = [
      "Director of Photography",
      "Cinematography",
      "Original Music Composer",
      "Music",
      "Costume Design",
      "Costume Designer",
      "Production Design",
      "Production Designer",
      "Film Editor",
      "Editor",
      "Editing",
      "Casting",
      "Casting Director"
    ]

    crew
    |> Enum.filter(&(&1["job"] in important_jobs))
    # Remove duplicates by name
    |> Enum.uniq_by(& &1["name"])
    # Limit to 6 featured crew members
    |> Enum.take(6)
  end

  defp get_featured_crew(_), do: []
end
