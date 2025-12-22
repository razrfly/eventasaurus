defmodule EventasaurusWeb.PublicEventsHomeLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.CityStats
  alias EventasaurusDiscovery.CategoryStats
  alias EventasaurusDiscovery.FeaturedEvents
  alias EventasaurusWeb.Components.CityCards
  alias EventasaurusWeb.Components.CategoryCards
  alias EventasaurusWeb.Components.FeaturedEventCard
  alias EventasaurusWeb.Components.EventCards

  def mount(_params, _session, socket) do
    # Load data in parallel for performance
    tasks = [
      Task.async(fn -> CityStats.list_top_cities_by_events(limit: 8) end),
      Task.async(fn -> CategoryStats.list_top_categories_by_events(limit: 12) end),
      Task.async(fn -> FeaturedEvents.list_featured_events(limit: 10) end)
    ]

    [top_cities, top_categories, featured_events] = Task.await_many(tasks)

    # Get IDs to exclude from upcoming list
    exclude_ids = Enum.map(featured_events, & &1.id)

    upcoming_events =
      FeaturedEvents.list_diverse_upcoming_events(limit: 24, exclude_ids: exclude_ids)

    socket =
      socket
      |> assign(:page_title, "Discover Events & Activities")
      |> assign(:top_cities, top_cities)
      |> assign(:top_categories, top_categories)
      |> assign(:featured_events, featured_events)
      |> assign(:upcoming_events, upcoming_events)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-gray-50 min-h-screen pb-20">
      <!-- Hero Section -->
      <div class="relative bg-gray-900 text-white overflow-hidden">
        <div class="absolute inset-0">
          <img
            src="https://images.unsplash.com/photo-1492684223066-81342ee5ff30?ixlib=rb-4.0.3&auto=format&fit=crop&w=1600&q=80"
            alt="Hero background"
            class="w-full h-full object-cover opacity-40"
          />
        </div>
        <div class="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24 text-center">
          <h1 class="text-4xl md:text-5xl font-extrabold tracking-tight mb-8">
            Unforgettable experiences start here
          </h1>
          <p class="text-xl text-gray-300">
            Discover events and activities in cities around the world
          </p>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 space-y-16 py-12">
        <!-- Section 1: Discover events in your city -->
        <section>
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-2xl font-bold text-gray-900">Discover events in your city</h2>
            <.link navigate={~p"/cities"} class="text-blue-600 hover:text-blue-800 font-medium">
              View all cities &rarr;
            </.link>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
            <%= for city <- @top_cities do %>
              <CityCards.city_card city={city} event_count={city.event_count} />
            <% end %>
          </div>
        </section>

        <!-- Section 2: Browse by category -->
        <section>
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-2xl font-bold text-gray-900">Browse by category</h2>
          </div>
          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-4">
            <%= for category <- @top_categories do %>
              <CategoryCards.category_card category={category} event_count={category.event_count} />
            <% end %>
          </div>
        </section>

        <!-- Section 3: Featured experiences -->
        <%= if @featured_events != [] do %>
          <section>
            <h2 class="text-2xl font-bold text-gray-900 mb-6">Featured experiences</h2>
            <div class="relative">
              <div class="flex overflow-x-auto pb-6 space-x-6 scrollbar-hide snap-x">
                <%= for {event, index} <- Enum.with_index(@featured_events, 1) do %>
                  <div class="snap-start">
                    <FeaturedEventCard.featured_event_card
                      event={event}
                      rank={index}
                      badge_text={"#{event.occurrence_count} dates"}
                    />
                  </div>
                <% end %>
              </div>
            </div>
          </section>
        <% end %>

        <!-- Section 4: Upcoming experiences -->
        <section>
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-2xl font-bold text-gray-900">Upcoming experiences</h2>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for event <- @upcoming_events do %>
              <EventCards.event_card event={event} show_city={true} />
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end
end
