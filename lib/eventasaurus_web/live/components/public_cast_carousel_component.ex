defmodule EventasaurusWeb.Live.Components.PublicCastCarouselComponent do
  @moduledoc """
  Cast carousel component for public event pages.

  Displays cast members in a horizontal scrolling carousel with
  circular profile images, names, and character names.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:cast, fn -> [] end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white">
      <div class="max-w-6xl mx-auto px-4 py-8">
        <h2 class="text-2xl font-bold text-gray-900 mb-6">Cast & Crew</h2>

        <%= if @display_cast && length(@display_cast) > 0 do %>
          <!-- Desktop Carousel -->
          <div class="hidden md:block relative">
            <!-- Scroll buttons -->
            <%= if @show_scroll_buttons do %>
              <button
                phx-click="scroll_left"
                phx-target={@myself}
                class="absolute left-0 top-1/2 -translate-y-1/2 z-10 bg-white shadow-lg rounded-full p-2 hover:bg-gray-50 transition-colors"
                style="transform: translateX(-50%) translateY(-50%)"
                aria-label="Scroll cast left"
              >
                <.icon name="hero-chevron-left" class="w-5 h-5 text-gray-600" />
              </button>

              <button
                phx-click="scroll_right"
                phx-target={@myself}
                class="absolute right-0 top-1/2 -translate-y-1/2 z-10 bg-white shadow-lg rounded-full p-2 hover:bg-gray-50 transition-colors"
                style="transform: translateX(50%) translateY(-50%)"
                aria-label="Scroll cast right"
              >
                <.icon name="hero-chevron-right" class="w-5 h-5 text-gray-600" />
              </button>
            <% end %>

            <!-- Scrollable container -->
            <div
              id={"cast-carousel-#{@id}"}
              class="flex gap-4 overflow-x-auto scrollbar-hide scroll-smooth"
              style="scroll-behavior: smooth; -webkit-overflow-scrolling: touch;"
            >
              <%= for cast_member <- @display_cast do %>
                <.cast_card cast_member={cast_member} />
              <% end %>
            </div>
          </div>

          <!-- Mobile Grid -->
          <div class="md:hidden">
            <div class="grid grid-cols-3 gap-4">
              <%= for cast_member <- Enum.take(@display_cast, 6) do %>
                <.cast_card_mobile cast_member={cast_member} />
              <% end %>
            </div>

            <%= if length(@display_cast) > 6 do %>
              <div class="mt-4 text-center">
                <button
                  phx-click="show_all_cast"
                  phx-target={@myself}
                  class="text-indigo-600 hover:text-indigo-500 font-medium"
                >
                  View All <%= length(@display_cast) %> Cast Members
                </button>
              </div>
            <% end %>
          </div>

        <% else %>
          <div class="text-center py-8">
            <div class="text-gray-500">
              <.icon name="hero-user-group" class="w-12 h-12 mx-auto mb-3" />
              <p>Cast information not available</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("scroll_left", _params, socket) do
    {:noreply,
     socket
     |> push_event("scroll_cast_carousel", %{
       target: "cast-carousel-#{socket.assigns.id}",
       direction: "left",
       amount: 300
     })}
  end

  @impl true
  def handle_event("scroll_right", _params, socket) do
    {:noreply,
     socket
     |> push_event("scroll_cast_carousel", %{
       target: "cast-carousel-#{socket.assigns.id}",
       direction: "right",
       amount: 300
     })}
  end

  @impl true
  def handle_event("show_all_cast", _params, socket) do
    # For now, just show a message - this could be expanded to a modal
    {:noreply,
     socket
     |> put_flash(:info, "Full cast listing feature coming soon!")}
  end

  # Private function components

  defp cast_card(assigns) do
    ~H"""
    <div class="flex-shrink-0 text-center w-24">
      <!-- Profile Image -->
      <div class="relative mb-3">
        <%= if @cast_member["profile_path"] do %>
          <img
            src={RichDataDisplayComponent.tmdb_image_url(@cast_member["profile_path"], "w185")}
            alt={@cast_member["name"]}
            class="w-20 h-20 rounded-full object-cover mx-auto shadow-sm border-2 border-gray-100"
            loading="lazy"
          />
        <% else %>
          <div class="w-20 h-20 rounded-full bg-gray-200 flex items-center justify-center mx-auto border-2 border-gray-100">
            <.icon name="hero-user" class="w-8 h-8 text-gray-400" />
          </div>
        <% end %>
      </div>

      <!-- Actor Info -->
      <div class="space-y-1">
        <p class="text-sm font-semibold text-gray-900 line-clamp-2 leading-tight">
          <%= @cast_member["name"] %>
        </p>
        <%= if @cast_member["character"] do %>
          <p class="text-xs text-gray-500 line-clamp-2 leading-tight">
            <%= @cast_member["character"] %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp cast_card_mobile(assigns) do
    ~H"""
    <div class="text-center">
      <!-- Profile Image -->
      <div class="relative mb-2">
        <%= if @cast_member["profile_path"] do %>
          <img
            src={RichDataDisplayComponent.tmdb_image_url(@cast_member["profile_path"], "w185")}
            alt={@cast_member["name"]}
            class="w-16 h-16 rounded-full object-cover mx-auto shadow-sm border border-gray-100"
            loading="lazy"
          />
        <% else %>
          <div class="w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center mx-auto border border-gray-100">
            <.icon name="hero-user" class="w-6 h-6 text-gray-400" />
          </div>
        <% end %>
      </div>

      <!-- Actor Info -->
      <div class="space-y-1">
        <p class="text-xs font-medium text-gray-900 line-clamp-1">
          <%= @cast_member["name"] %>
        </p>
        <%= if @cast_member["character"] do %>
          <p class="text-xs text-gray-500 line-clamp-1">
            <%= @cast_member["character"] %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    cast = socket.assigns.cast || []

    socket
    |> assign(:display_cast, get_display_cast(cast))
    |> assign(:show_scroll_buttons, length(cast) > 8)
  end

  defp get_display_cast(cast) do
    # Show top billed cast, limit to reasonable number for display
    cast
    |> Enum.filter(&has_name?/1)
    |> Enum.take(20) # Limit to 20 cast members for performance
  end

  defp has_name?(cast_member) do
    name = cast_member["name"]
    is_binary(name) && String.trim(name) != ""
  end
end
