defmodule EventasaurusWeb.RichDataSearchComponent do
  @moduledoc """
  A reusable LiveView component for searching and selecting rich data from external APIs.

  This component provides a unified interface for searching content from various providers
  (TMDB for movies, Google Places for locations, etc.) and can be used in different contexts
  like poll options, activity creation, and event metadata.

  ## Features
  - Provider-agnostic search interface
  - Configurable search behavior and display
  - Loading states and error handling
  - Customizable result rendering
  - Callback-based selection handling

  ## Attributes
  - id: Component ID (required)
  - provider: Provider atom (:tmdb, :google_places, etc.) (required)
  - on_select: Function to call when item is selected (required)
  - search_placeholder: Placeholder text for search input
  - content_type: Type of content to search (:movie, :place, etc.)
  - show_search: Whether to show the search interface
  - result_limit: Maximum number of results to display
  - class: Additional CSS classes

  ## Usage
      <.live_component
        module={EventasaurusWeb.RichDataSearchComponent}
        id="movie-search"
        provider={:tmdb}
        content_type={:movie}
        on_select={fn result -> send(self(), {:movie_selected, result}) end}
        search_placeholder="Search for movies..."
        result_limit={10}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusWeb.Services.RichDataManager

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:search_loading, false)
     |> assign(:selected_item, nil)
     |> assign(:show_results, false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:search_placeholder, fn -> default_placeholder(assigns[:provider]) end)
     |> assign_new(:content_type, fn -> default_content_type(assigns[:provider]) end)
     |> assign_new(:show_search, fn -> true end)
     |> assign_new(:result_limit, fn -> 10 end)
     |> assign_new(:class, fn -> "" end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["rich-data-search", @class]}>
      <%= if @show_search do %>
        <div class="space-y-4">
          <!-- Search Input -->
          <div class="relative">
            <input
              type="text"
              value={@search_query}
              phx-keyup="search"
              phx-debounce="300"
              phx-target={@myself}
              placeholder={@search_placeholder}
              class="w-full px-4 py-2 pl-10 pr-4 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
            />
            <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
              <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
            <%= if @search_loading do %>
              <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                <svg class="animate-spin h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
              </div>
            <% end %>
          </div>
          
          <!-- Search Results -->
          <%= if @show_results && length(@search_results) > 0 do %>
            <div class="bg-white border border-gray-200 rounded-lg shadow-lg max-h-96 overflow-y-auto">
              <div class="divide-y divide-gray-100">
                <%= for result <- @search_results do %>
                  <button
                    type="button"
                    phx-click="select_item"
                    phx-value-item-id={result.id}
                    phx-target={@myself}
                    class="w-full px-4 py-3 text-left hover:bg-gray-50 focus:bg-gray-50 focus:outline-none transition-colors"
                  >
                    <%= render_result_item(assigns, result) %>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
          
          <!-- No Results Message -->
          <%= if @show_results && length(@search_results) == 0 && @search_query != "" && !@search_loading do %>
            <div class="text-center py-8 text-gray-500">
              <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <p class="mt-2 text-sm">No results found for "<%= @search_query %>"</p>
            </div>
          <% end %>
        </div>
      <% end %>
      
      <!-- Selected Item Display (optional) -->
      <%= if @selected_item do %>
        <div class="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <%= render_selected_item(assigns, @selected_item) %>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_result_item(assigns, %{type: :movie} = result) do
    assigns = assign(assigns, :result, result)

    ~H"""
    <div class="flex items-start space-x-3">
      <%= if @result.image_url do %>
        <img 
          src={@result.image_url} 
          alt={@result.title}
          class="w-16 h-24 object-cover rounded"
        />
      <% else %>
        <div class="w-16 h-24 bg-gray-200 rounded flex items-center justify-center">
          <svg class="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4" />
          </svg>
        </div>
      <% end %>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-gray-900 truncate">
          <%= @result.title %>
          <%= if @result.metadata["release_date"] do %>
            <span class="text-gray-500">(<%= String.slice(@result.metadata["release_date"], 0..3) %>)</span>
          <% end %>
        </p>
        <%= if @result.description do %>
          <p class="mt-1 text-sm text-gray-500 line-clamp-2">
            <%= @result.description %>
          </p>
        <% end %>
        <%= if @result.metadata["vote_average"] do %>
          <div class="mt-1 flex items-center">
            <svg class="w-4 h-4 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
              <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
            </svg>
            <span class="ml-1 text-xs text-gray-600"><%= Float.round(@result.metadata["vote_average"], 1) %>/10</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_result_item(assigns, %{type: :tv} = result) do
    assigns = assign(assigns, :result, result)

    ~H"""
    <div class="flex items-start space-x-3">
      <%= if @result.image_url do %>
        <img 
          src={@result.image_url} 
          alt={@result.title}
          class="w-16 h-24 object-cover rounded"
        />
      <% else %>
        <div class="w-16 h-24 bg-purple-100 rounded flex items-center justify-center">
          <svg class="w-8 h-8 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
          </svg>
        </div>
      <% end %>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-gray-900 truncate">
          <%= @result.title %>
          <%= if @result.metadata["first_air_date"] do %>
            <span class="text-gray-500">(<%= String.slice(@result.metadata["first_air_date"], 0..3) %>)</span>
          <% end %>
        </p>
        <%= if @result.description do %>
          <p class="mt-1 text-sm text-gray-500 line-clamp-2">
            <%= @result.description %>
          </p>
        <% end %>
        <%= if @result.metadata["vote_average"] do %>
          <div class="mt-1 flex items-center">
            <svg class="w-4 h-4 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
              <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
            </svg>
            <span class="ml-1 text-xs text-gray-600"><%= Float.round(@result.metadata["vote_average"], 1) %>/10</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_result_item(assigns, %{type: :place} = result) do
    assigns = assign(assigns, :result, result)

    ~H"""
    <div class="flex items-start space-x-3">
      <div class="flex-shrink-0">
        <%= if @result.image_url do %>
          <img 
            src={@result.image_url} 
            alt={@result.title}
            class="w-12 h-12 object-cover rounded-lg"
          />
        <% else %>
          <div class="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center">
            <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </div>
        <% end %>
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-gray-900 truncate">
          <%= @result.title %>
        </p>
        <%= if @result.metadata["address"] do %>
          <p class="mt-1 text-sm text-gray-500">
            <%= @result.metadata["address"] %>
          </p>
        <% end %>
        <%= if @result.metadata["rating"] do %>
          <div class="mt-1 flex items-center">
            <svg class="w-4 h-4 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
              <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
            </svg>
            <span class="ml-1 text-xs text-gray-600">
              <%= @result.metadata["rating"] %>
              <%= if @result.metadata["user_ratings_total"] do %>
                (<%= @result.metadata["user_ratings_total"] %> reviews)
              <% end %>
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_result_item(assigns, result) do
    # Generic fallback for other content types
    assigns = assign(assigns, :result, result)

    ~H"""
    <div class="py-2">
      <p class="text-sm font-medium text-gray-900"><%= @result.title %></p>
      <%= if @result.description do %>
        <p class="mt-1 text-sm text-gray-500 truncate"><%= @result.description %></p>
      <% end %>
    </div>
    """
  end

  defp render_selected_item(assigns, %{type: :movie} = item) do
    assigns = assign(assigns, :item, item)

    ~H"""
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-3">
        <svg class="w-5 h-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
        </svg>
        <span class="text-sm font-medium text-gray-900">
          Selected: <%= @item.title %>
          <%= if @item.metadata["release_date"] do %>
            (<%= String.slice(@item.metadata["release_date"], 0..3) %>)
          <% end %>
        </span>
      </div>
      <button
        type="button"
        phx-click="clear_selection"
        phx-target={@myself}
        class="text-sm text-blue-600 hover:text-blue-800"
      >
        Change
      </button>
    </div>
    """
  end

  defp render_selected_item(assigns, item) do
    # Generic selected item display
    assigns = assign(assigns, :item, item)

    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-gray-900">Selected: <%= @item.title %></span>
      <button
        type="button"
        phx-click="clear_selection"
        phx-target={@myself}
        class="text-sm text-blue-600 hover:text-blue-800"
      >
        Change
      </button>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    require Logger

    Logger.error(
      "RichDataSearchComponent: search event called with query='#{query}', content_type=#{socket.assigns.content_type}"
    )

    if String.length(String.trim(query)) >= 2 do
      Logger.error("RichDataSearchComponent: triggering search for query='#{query}'")
      socket = assign(socket, :search_loading, true)

      # Configure search based on provider
      search_options = %{
        providers: [socket.assigns.provider],
        limit: socket.assigns.result_limit,
        content_type: socket.assigns.content_type
      }

      Logger.error("RichDataSearchComponent: search_options=#{inspect(search_options)}")

      case RichDataManager.search(query, search_options) do
        {:ok, results_by_provider} ->
          Logger.error(
            "RichDataSearchComponent: search succeeded, results_by_provider=#{inspect(results_by_provider)}"
          )

          # Extract results for the specific provider
          results =
            case Map.get(results_by_provider, socket.assigns.provider) do
              {:ok, results} when is_list(results) -> results
              {:ok, result} -> [result]
              _ -> []
            end

          Logger.error(
            "Search results for content_type #{socket.assigns.content_type}: #{length(results)} results"
          )

          if length(results) > 0 do
            Logger.error(
              "First result: type=#{List.first(results).type}, id=#{List.first(results).id}, title='#{List.first(results).title}'"
            )
          end

          {:noreply,
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, Enum.take(results, socket.assigns.result_limit))
           |> assign(:search_loading, false)
           |> assign(:show_results, true)}

        {:error, reason} ->
          Logger.error("RichDataSearchComponent: search failed with reason: #{inspect(reason)}")

          {:noreply,
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, [])
           |> assign(:search_loading, false)
           |> assign(:show_results, true)}
      end
    else
      Logger.error(
        "RichDataSearchComponent: query too short (#{String.length(String.trim(query))} chars), not searching"
      )

      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:search_results, [])
       |> assign(:show_results, false)}
    end
  end

  @impl true
  def handle_event("select_item", %{"item-id" => item_id}, socket) do
    require Logger

    Logger.error(
      "RichDataSearchComponent: select_item ACTUALLY CALLED with item_id=#{item_id}, content_type=#{socket.assigns.content_type}"
    )

    Logger.debug(
      "RichDataSearchComponent: select_item called with item_id=#{item_id}, content_type=#{socket.assigns.content_type}"
    )

    # Find the selected item in search results
    selected =
      Enum.find(socket.assigns.search_results, fn item ->
        to_string(item.id) == item_id
      end)

    if selected do
      Logger.debug(
        "RichDataSearchComponent: Found selected item: #{selected.title} (type: #{selected.type})"
      )

      # Get detailed data if provider supports it
      case get_detailed_data(socket.assigns.provider, selected, socket.assigns.content_type) do
        {:ok, detailed_item} ->
          # Send event to parent based on content type
          event_name =
            case socket.assigns.content_type do
              :movie -> "movie_selected"
              :tv -> "tv_show_selected"
              :place -> "place_selected"
              _ -> "item_selected"
            end

          Logger.debug(
            "RichDataSearchComponent: Sending event #{event_name} with detailed item: #{detailed_item.title}"
          )

          # Send message to parent LiveView
          send(self(), {__MODULE__, :selection_made, event_name, detailed_item})

          {:noreply,
           socket
           |> assign(:selected_item, detailed_item)
           |> assign(:show_results, false)
           |> assign(:search_query, "")}

        {:error, reason} ->
          Logger.debug(
            "RichDataSearchComponent: Failed to get detailed data: #{inspect(reason)}, falling back to search result"
          )

          # Fall back to using the search result data
          event_name =
            case socket.assigns.content_type do
              :movie -> "movie_selected"
              :tv -> "tv_show_selected"
              :place -> "place_selected"
              _ -> "item_selected"
            end

          Logger.debug(
            "RichDataSearchComponent: Sending fallback event #{event_name} with search result: #{selected.title}"
          )

          # Send message to parent LiveView
          send(self(), {__MODULE__, :selection_made, event_name, selected})

          {:noreply,
           socket
           |> assign(:selected_item, selected)
           |> assign(:show_results, false)
           |> assign(:search_query, "")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_item, nil)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  defp get_detailed_data(:tmdb, item, :movie) do
    RichDataManager.get_cached_details(:tmdb, item.id, :movie)
  end

  defp get_detailed_data(:tmdb, item, :tv) do
    RichDataManager.get_cached_details(:tmdb, item.id, :tv)
  end

  defp get_detailed_data(:google_places, item, :place) do
    RichDataManager.get_cached_details(:google_places, item.id, :place)
  end

  defp get_detailed_data(_provider, item, _type) do
    # For providers that don't support detailed data, return the item as-is
    {:ok, item}
  end

  defp default_placeholder(:tmdb), do: "Search for movies..."
  defp default_placeholder(:google_places), do: "Search for places..."
  defp default_placeholder(_), do: "Search..."

  defp default_content_type(:tmdb), do: :movie
  defp default_content_type(:google_places), do: :place
  defp default_content_type(_), do: :generic
end
