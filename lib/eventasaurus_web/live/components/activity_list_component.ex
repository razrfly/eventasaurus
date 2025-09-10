defmodule EventasaurusWeb.Components.ActivityListComponent do
  use EventasaurusWeb, :live_component
  
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg">
      <div class="px-4 sm:px-6 py-4 sm:py-5 border-b border-gray-200">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h3 class="text-lg font-medium text-gray-900">Group Activities</h3>
            <p class="text-sm text-gray-500">Things your group has done together</p>
          </div>
        </div>
        
        <!-- Filter Controls -->
        <div class="flex flex-wrap items-center gap-3">
          <div class="text-sm font-medium text-gray-700">Filter by type:</div>
          
          <select 
            phx-change="filter_activities"
            name="activity_type"
            value={@activity_filter}
            class="appearance-none bg-white border border-gray-300 rounded-md pl-3 pr-8 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="all" selected={@activity_filter == "all"}>All Activities</option>
            <option value="movie_watched" selected={@activity_filter == "movie_watched"}>Movies</option>
            <option value="tv_watched" selected={@activity_filter == "tv_watched"}>TV Shows</option>
            <option value="game_played" selected={@activity_filter == "game_played"}>Games</option>
            <option value="book_read" selected={@activity_filter == "book_read"}>Books</option>
            <option value="restaurant_visited" selected={@activity_filter == "restaurant_visited"}>Restaurants</option>
            <option value="place_visited" selected={@activity_filter == "place_visited"}>Places</option>
            <option value="activity_completed" selected={@activity_filter == "activity_completed"}>Activities</option>
            <option value="custom" selected={@activity_filter == "custom"}>Custom</option>
          </select>
        </div>
      </div>
      
      <!-- Activities List -->
      <%= if @activities != [] do %>
        <div class="divide-y divide-gray-200">
          <%= for activity <- @activities do %>
            <div class="px-4 sm:px-6 py-4 sm:py-6 hover:bg-gray-50 transition-colors">
              <div class="flex items-start gap-3 sm:gap-4">
                <!-- Activity Icon/Image -->
                <div class="flex-shrink-0">
                  <%= if get_activity_image(activity) do %>
                    <img 
                      src={get_activity_image(activity)} 
                      alt={get_activity_title(activity)}
                      class="h-16 w-16 rounded-lg object-cover"
                    />
                  <% else %>
                    <div class="h-16 w-16 rounded-lg bg-gray-200 flex items-center justify-center">
                      <svg class="h-8 w-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <%= Phoenix.HTML.raw(activity_icon(activity.activity_type)) %>
                      </svg>
                    </div>
                  <% end %>
                </div>
                
                <!-- Activity Details -->
                <div class="flex-1 min-w-0">
                  <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-2">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-start justify-between gap-2">
                        <h4 class="text-sm font-medium text-gray-900 line-clamp-2 sm:truncate flex-1">
                          <%= get_activity_title(activity) %>
                        </h4>
                        <!-- Activity Type Badge - Top right on mobile -->
                        <span class={[
                          "flex-shrink-0 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                          activity_type_badge_class(activity.activity_type)
                        ]}>
                          <%= activity_type_display(activity.activity_type) %>
                        </span>
                      </div>
                      
                      <%= if get_activity_description(activity) do %>
                        <p class="mt-1 text-sm text-gray-500 line-clamp-2">
                          <%= get_activity_description(activity) %>
                        </p>
                      <% end %>
                      
                      <div class="mt-3 flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-4 text-xs text-gray-400">
                        <span class="flex items-center gap-1">
                          <svg class="h-3 w-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                          </svg>
                          <%= format_activity_date(activity.occurred_at) %>
                        </span>
                        <%= if activity.event do %>
                          <.link navigate={"/events/#{activity.event.slug}"} class="flex items-center gap-1 hover:text-blue-600 truncate">
                            <svg class="h-3 w-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                            </svg>
                            <span class="truncate"><%= activity.event.title %></span>
                          </.link>
                        <% end %>
                        <%= if activity.created_by do %>
                          <span class="flex items-center gap-1 truncate">
                            <svg class="h-3 w-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                            </svg>
                            <span class="truncate"><%= activity.created_by.name || "Unknown" %></span>
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="px-4 sm:px-6 py-12 text-center">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No activities yet</h3>
          <p class="mt-1 text-sm text-gray-500">
            Activities will appear here as your group completes events.
          </p>
        </div>
      <% end %>
    </div>
    """
  end
  
  # Helper functions
  
  defp get_activity_title(activity) do
    case activity.metadata do
      nil -> "Untitled Activity"
      metadata -> metadata["title"] || metadata["name"] || "Untitled Activity"
    end
  end
  
  defp get_activity_description(activity) do
    case activity.metadata do
      nil -> nil
      metadata -> metadata["description"] || metadata["overview"]
    end
  end
  
  defp get_activity_image(activity) do
    case activity.metadata do
      nil -> nil
      metadata -> metadata["image_url"] || metadata["poster_url"] || metadata["thumbnail_url"]
    end
  end
  
  defp format_activity_date(nil), do: "Unknown date"
  defp format_activity_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
  
  defp activity_type_display("movie_watched"), do: "Movie"
  defp activity_type_display("tv_watched"), do: "TV Show"
  defp activity_type_display("game_played"), do: "Game"
  defp activity_type_display("book_read"), do: "Book"
  defp activity_type_display("restaurant_visited"), do: "Restaurant"
  defp activity_type_display("place_visited"), do: "Place"
  defp activity_type_display("activity_completed"), do: "Activity"
  defp activity_type_display("custom"), do: "Custom"
  defp activity_type_display(_), do: "Other"
  
  defp activity_type_badge_class("movie_watched"), do: "bg-purple-100 text-purple-800"
  defp activity_type_badge_class("tv_watched"), do: "bg-indigo-100 text-indigo-800"
  defp activity_type_badge_class("game_played"), do: "bg-green-100 text-green-800"
  defp activity_type_badge_class("book_read"), do: "bg-yellow-100 text-yellow-800"
  defp activity_type_badge_class("restaurant_visited"), do: "bg-orange-100 text-orange-800"
  defp activity_type_badge_class("place_visited"), do: "bg-blue-100 text-blue-800"
  defp activity_type_badge_class("activity_completed"), do: "bg-pink-100 text-pink-800"
  defp activity_type_badge_class(_), do: "bg-gray-100 text-gray-800"
  
  defp activity_icon("movie_watched") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4" />)
  end
  
  defp activity_icon("tv_watched") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />)
  end
  
  defp activity_icon("game_played") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 4a2 2 0 114 0v1a1 1 0 001 1h3a1 1 0 011 1v3a1 1 0 01-1 1h-1a2 2 0 100 4h1a1 1 0 011 1v3a1 1 0 01-1 1h-3a1 1 0 01-1-1v-1a2 2 0 10-4 0v1a1 1 0 01-1 1H7a1 1 0 01-1-1v-3a1 1 0 00-1-1H4a2 2 0 110-4h1a1 1 0 001-1V7a1 1 0 011-1h3a1 1 0 001-1V4z" />)
  end
  
  defp activity_icon("book_read") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />)
  end
  
  defp activity_icon("restaurant_visited") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z" />)
  end
  
  defp activity_icon("place_visited") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />)
  end
  
  defp activity_icon(_) do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />)
  end
end