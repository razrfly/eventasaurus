defmodule EventasaurusWeb.Components.VenueCards do
  @moduledoc """
  Reusable venue card components for displaying venues in grid or list layouts.
  """
  use Phoenix.Component
  import EventasaurusWeb.CoreComponents
  use Phoenix.VerifiedRoutes, endpoint: EventasaurusWeb.Endpoint, router: EventasaurusWeb.Router
  alias EventasaurusApp.Images.VenueImages

  @doc """
  Renders a grid of venue cards.

  ## Examples

      <VenueCards.venue_grid venues={@venues} city={@city} />
  """
  attr :venues, :list, required: true
  attr :city, :map, required: true

  def venue_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
      <%= for venue_data <- @venues do %>
        <.venue_card venue={venue_data.venue} city={@city} events_count={venue_data.upcoming_events_count} />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a list of venue cards.

  ## Examples

      <VenueCards.venue_list venues={@venues} city={@city} />
  """
  attr :venues, :list, required: true
  attr :city, :map, required: true

  def venue_list(assigns) do
    ~H"""
    <div class="flex flex-col space-y-4">
      <%= for venue_data <- @venues do %>
        <.venue_list_item venue={venue_data.venue} city={@city} events_count={venue_data.upcoming_events_count} />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a single venue card for grid layout.

  Displays venue image (with Unsplash fallback), name, address, and upcoming events count.
  """
  attr :venue, :map, required: true
  attr :city, :map, required: true
  attr :events_count, :integer, default: 0

  def venue_card(assigns) do
    assigns =
      assign(
        assigns,
        :image_url,
        VenueImages.get_image(assigns.venue, assigns.city,
          width: 400,
          height: 300,
          quality: 85
        )
      )

    ~H"""
    <.link
      navigate={~p"/venues/#{@venue.slug}"}
      class="block bg-white dark:bg-gray-800 rounded-lg shadow-md hover:shadow-lg transition-shadow overflow-hidden"
    >
      <div class="h-48 bg-gray-200 dark:bg-gray-700 rounded-t-lg relative overflow-hidden">
        <%= if @image_url do %>
          <img
            src={@image_url}
            alt={"Photo of #{@venue.name}"}
            class="w-full h-full object-cover"
            loading="lazy"
            referrerpolicy="no-referrer"
          />
        <% else %>
          <div class="w-full h-full flex items-center justify-center">
            <.icon name="hero-building-office-2" class="h-16 w-16 text-gray-400 dark:text-gray-500" />
          </div>
        <% end %>

        <%!-- Event Count Badge - MOVED TO TOP LEFT to match city page --%>
        <%= if @events_count > 0 do %>
          <div class="absolute top-3 left-3 bg-blue-600 text-white px-2 py-1 rounded-md text-xs font-medium">
            <%= @events_count %><%= if @events_count == 1, do: " event", else: " events" %>
          </div>
        <% end %>
      </div>

      <div class="p-4">
        <h3 class="font-semibold text-lg text-gray-900 dark:text-gray-100 line-clamp-2">
          <%= @venue.name %>
        </h3>

        <%= if @venue.address do %>
          <div class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            <%= @venue.address %>
          </div>
        <% end %>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a single venue list item for list layout.

  Displays compact venue information in a horizontal layout.
  """
  attr :venue, :map, required: true
  attr :city, :map, required: true
  attr :events_count, :integer, default: 0

  def venue_list_item(assigns) do
    assigns =
      assign(
        assigns,
        :image_url,
        VenueImages.get_image(assigns.venue, assigns.city,
          width: 192,
          height: 192,
          quality: 85
        )
      )

    ~H"""
    <.link
      navigate={~p"/venues/#{@venue.slug}"}
      class="group flex items-start gap-4 p-4 bg-white dark:bg-gray-800 rounded-lg shadow-md hover:shadow-lg transition-shadow"
    >
      <div class="flex-shrink-0">
        <%= if @image_url do %>
          <img
            src={@image_url}
            alt={"Photo of #{@venue.name}"}
            class="w-24 h-24 object-cover rounded-lg"
            loading="lazy"
            referrerpolicy="no-referrer"
          />
        <% else %>
          <div class="w-24 h-24 bg-gray-200 dark:bg-gray-700 rounded-lg flex items-center justify-center">
            <.icon name="hero-building-office-2" class="h-10 w-10 text-gray-400 dark:text-gray-500" />
          </div>
        <% end %>
      </div>

      <div class="flex-1 min-w-0">
        <h3 class="font-semibold text-lg text-gray-900 dark:text-gray-100">
          <%= @venue.name %>
        </h3>

        <%= if @venue.address do %>
          <div class="mt-1 text-sm text-gray-600 dark:text-gray-400">
            <%= @venue.address %>
          </div>
        <% end %>

        <%= if @events_count > 0 do %>
          <div class="mt-2 flex items-center text-sm text-blue-600 dark:text-blue-400">
            <%= @events_count %><%= if @events_count == 1, do: " upcoming event", else: " upcoming events" %>
          </div>
        <% end %>
      </div>

      <div class="flex-shrink-0">
        <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400" />
      </div>
    </.link>
    """
  end

  @doc """
  Renders an empty state when no venues are found.
  """
  attr :search_term, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <.icon name="hero-map-pin" class="mx-auto h-12 w-12 text-gray-400" />
      <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-gray-100">No venues found</h3>
      <%= if @search_term do %>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          Try adjusting your search term "<%= @search_term %>"
        </p>
      <% else %>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          There are no venues in this city yet.
        </p>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a loading skeleton for venue cards.
  """
  attr :count, :integer, default: 12
  attr :layout, :atom, default: :grid, values: [:grid, :list]

  def loading_skeleton(assigns) do
    ~H"""
    <%= if @layout == :grid do %>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        <%= for _i <- 1..@count do %>
          <div class="animate-pulse">
            <div class="aspect-[4/3] bg-gray-200 dark:bg-gray-700 rounded-lg"></div>
            <div class="p-4 space-y-3">
              <div class="h-4 bg-gray-200 dark:bg-gray-700 rounded w-3/4"></div>
              <div class="h-3 bg-gray-200 dark:bg-gray-700 rounded w-1/2"></div>
              <div class="h-6 bg-gray-200 dark:bg-gray-700 rounded w-1/3"></div>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      <div class="flex flex-col space-y-4">
        <%= for _i <- 1..@count do %>
          <div class="animate-pulse flex items-start gap-4 p-4">
            <div class="w-24 h-24 bg-gray-200 dark:bg-gray-700 rounded-lg"></div>
            <div class="flex-1 space-y-3">
              <div class="h-4 bg-gray-200 dark:bg-gray-700 rounded w-3/4"></div>
              <div class="h-3 bg-gray-200 dark:bg-gray-700 rounded w-1/2"></div>
              <div class="h-6 bg-gray-200 dark:bg-gray-700 rounded w-1/4"></div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
