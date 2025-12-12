defmodule EventasaurusWeb.Live.Components.CastCarouselComponent do
  @moduledoc """
  Reusable cast carousel component.

  Displays cast members in a horizontal scrolling carousel with
  circular profile images, names, and character names.

  ## Usage

      <.live_component
        module={CastCarouselComponent}
        id="movie-cast"
        cast={@cast}
        variant={:standalone}  # or :embedded
      />

  ## Variants

  - `:standalone` - Full width with container, border, and shadow (for event pages)
  - `:embedded` - Minimal styling, meant to be embedded in another card (for movie pages)
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:cast, fn -> [] end)
     |> assign_new(:variant, fn -> :standalone end)
     |> assign_new(:max_cast, fn -> 20 end)
     |> assign_new(:title, fn -> "Cast & Crew" end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={container_classes(@variant)}>
      <%= if @variant == :standalone do %>
        <div class="container mx-auto px-4 sm:px-6 max-w-7xl">
          <div class="bg-white border border-gray-200 rounded-xl p-6 mb-4 shadow-sm">
            <.carousel_content
              id={@id}
              myself={@myself}
              title={@title}
              display_cast={@display_cast}
              show_scroll_buttons={@show_scroll_buttons}
              variant={@variant}
            />
          </div>
        </div>
      <% else %>
        <.carousel_content
          id={@id}
          myself={@myself}
          title={@title}
          display_cast={@display_cast}
          show_scroll_buttons={@show_scroll_buttons}
          variant={@variant}
        />
      <% end %>
    </div>
    """
  end

  defp carousel_content(assigns) do
    ~H"""
    <h2 class={title_classes(@variant)}><%= @title %></h2>

    <%= if @display_cast && length(@display_cast) > 0 do %>
      <div class="relative">
        <!-- Scroll buttons -->
        <%= if @show_scroll_buttons do %>
          <button
            phx-click="scroll_left"
            phx-target={@myself}
            class={scroll_button_classes(:left)}
            aria-label="Scroll cast left"
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-gray-600">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
            </svg>
          </button>

          <button
            phx-click="scroll_right"
            phx-target={@myself}
            class={scroll_button_classes(:right)}
            aria-label="Scroll cast right"
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-gray-600">
              <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
            </svg>
          </button>
        <% end %>

        <!-- Scrollable container -->
        <div
          id={"cast-carousel-#{@id}"}
          class="flex gap-4 overflow-x-auto scrollbar-hide scroll-smooth py-1"
          style="scroll-behavior: smooth; -webkit-overflow-scrolling: touch;"
          role="region"
          aria-label="Cast and crew carousel"
          tabindex="0"
          phx-hook="CastCarouselKeyboard"
          data-component-id={@myself}
        >
          <%= for cast_member <- @display_cast do %>
            <.cast_card cast_member={cast_member} />
          <% end %>
        </div>
      </div>
    <% else %>
      <div class="text-center py-6">
        <div class="text-gray-500">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-12 h-12 mx-auto mb-3">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z" />
          </svg>
          <p>Cast information not available</p>
        </div>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_event("scroll_" <> direction, _params, socket) when direction in ["left", "right"] do
    scroll_amount = socket.assigns[:scroll_amount] || 300

    {:noreply,
     socket
     |> push_event("scroll_cast_carousel", %{
       target: "cast-carousel-#{socket.assigns.id}",
       direction: direction,
       amount: scroll_amount
     })}
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
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-8 h-8 text-gray-400">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
            </svg>
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

  # CSS class helpers

  defp container_classes(:standalone), do: "hidden md:block"
  defp container_classes(:embedded), do: ""

  defp title_classes(:standalone), do: "text-2xl font-bold text-gray-900 mb-6"
  defp title_classes(:embedded), do: "text-base font-bold text-gray-900 mb-4"

  defp scroll_button_classes(:left) do
    "absolute left-0 top-1/2 -translate-y-1/2 z-10 bg-white shadow-lg rounded-full p-2 hover:bg-gray-50 transition-colors -translate-x-1/2"
  end

  defp scroll_button_classes(:right) do
    "absolute right-0 top-1/2 -translate-y-1/2 z-10 bg-white shadow-lg rounded-full p-2 hover:bg-gray-50 transition-colors translate-x-1/2"
  end

  # Private functions

  defp assign_computed_data(socket) do
    cast = socket.assigns.cast || []
    max_cast = socket.assigns.max_cast

    display_cast = get_display_cast(cast, max_cast)

    socket
    |> assign(:display_cast, display_cast)
    |> assign(:show_scroll_buttons, length(display_cast) > 6)
  end

  defp get_display_cast(cast, max_cast) do
    cast
    |> Enum.filter(&has_name?/1)
    |> Enum.take(max_cast)
  end

  defp has_name?(cast_member) do
    name = cast_member["name"]
    is_binary(name) && String.trim(name) != ""
  end
end
