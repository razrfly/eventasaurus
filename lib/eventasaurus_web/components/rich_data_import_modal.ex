defmodule EventasaurusWeb.Components.RichDataImportModal do
  @moduledoc """
  Modal component for importing rich data from external APIs.

  Allows users to search for and import comprehensive metadata from
  providers like TMDB, Spotify, etc. into their events.
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && "show-rich-data-modal"}
      phx-remove={@show && "hide-rich-data-modal"}
      class="relative z-50"
      style={unless @show, do: "display: none;"}
    >
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-black bg-opacity-50 transition-opacity" phx-click={@on_close}></div>

      <!-- Modal -->
      <div class="fixed inset-0 z-50 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center p-4">
          <div class="w-full max-w-4xl bg-white rounded-lg shadow-xl">
            <!-- Header -->
            <div class="flex items-center justify-between p-6 border-b border-gray-200">
              <h2 class="text-xl font-semibold text-gray-900">Import Rich Data</h2>
              <button
                type="button"
                phx-click="close_modal"
                phx-target={@myself}
                class="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <!-- Content -->
            <div class="p-6">
              <!-- Search Section -->
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Search for content to import
                </label>
                <.form for={%{}} as={:search} phx-submit="search" phx-target={@myself} class="flex gap-2">
                  <input
                    type="text"
                    name="search[query]"
                    placeholder="Search for movies, TV shows, music..."
                    class="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    phx-target={@myself}
                    phx-keyup="search_input"
                    phx-change="search_input"
                    phx-debounce="300"
                    value={@search_query}
                  />
                  <button
                    type="submit"
                    class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                  >
                    Search
                  </button>
                </.form>
              </div>

              <!-- Provider Tabs -->
              <div class="mb-6">
                <div class="border-b border-gray-200">
                  <nav class="-mb-px flex space-x-8">
                    <button
                      type="button"
                      phx-click="set_provider"
                      phx-value-provider="tmdb"
                      phx-target={@myself}
                      class={[
                        "py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                        if(@current_provider == "tmdb",
                          do: "border-blue-500 text-blue-600",
                          else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                        )
                      ]}
                    >
                      Movies & TV
                    </button>
                    <button
                      type="button"
                      phx-click="set_provider"
                      phx-value-provider="spotify"
                      phx-target={@myself}
                      class={[
                        "py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                        if(@current_provider == "spotify",
                          do: "border-blue-500 text-blue-600",
                          else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                        )
                      ]}
                    >
                      Music
                    </button>
                  </nav>
                </div>
              </div>

              <!-- Loading State -->
              <%= if @loading do %>
                <div class="text-center py-8">
                  <div class="inline-flex items-center text-gray-600">
                    <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-gray-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    Searching...
                  </div>
                </div>
              <% end %>

              <!-- Error State -->
              <%= if @error do %>
                <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-4">
                  <div class="flex items-center">
                    <svg class="w-5 h-5 text-red-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
                    </svg>
                    <span class="text-sm text-red-700"><%= @error %></span>
                  </div>
                </div>
              <% end %>

              <!-- Search Results -->
              <%= if @search_results && is_list(@search_results) && length(@search_results) > 0 do %>
                <div class="space-y-4 mb-6">
                  <%= for result <- @search_results do %>
                    <div
                      class="p-4 border rounded-lg hover:bg-gray-50 cursor-pointer transition-colors"
                      phx-click="import_result"
                      phx-value-id={result.id}
                      phx-value-provider={@current_provider}
                      phx-value-type={result.type}
                      phx-target={@myself}
                    >
                      <div class="flex items-start space-x-4">
                        <%# Get poster image from images list %>
                        <% poster_image = Enum.find(result.images || [], fn img -> img.type == :poster end) %>
                        <%= if poster_image do %>
                          <img src={poster_image.url} alt={result.title} class="w-16 h-24 object-cover rounded-lg flex-shrink-0" />
                        <% end %>
                        <div class="flex-1 min-w-0">
                          <h3 class="font-medium text-gray-900 truncate"><%= result.title %></h3>
                          <%# Extract year from metadata %>
                          <% year = case result.metadata do
                               %{release_date: date} when is_binary(date) and date != "" -> String.slice(date, 0, 4)
                               %{first_air_date: date} when is_binary(date) and date != "" -> String.slice(date, 0, 4)
                               _ -> nil
                             end %>
                          <%= if year do %>
                            <p class="text-sm text-gray-500"><%= year %></p>
                          <% end %>
                          <%= if result.description && result.description != "" do %>
                            <p class="text-sm text-gray-600 mt-1 line-clamp-2"><%= result.description %></p>
                          <% end %>
                          <div class="flex items-center mt-2">
                            <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                              <%= String.upcase(to_string(result.provider)) %>
                            </span>
                            <span class="ml-2 inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                              <%= String.capitalize(to_string(result.type)) %>
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <%= if @search_results && is_list(@search_results) && length(@search_results) == 0 do %>
                  <div class="text-center py-8">
                    <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                    <h3 class="mt-2 text-sm font-medium text-gray-900">No results found</h3>
                    <p class="mt-1 text-sm text-gray-500">Try a different search term or check your spelling.</p>
                  </div>
                <% end %>
              <% end %>


            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    require Logger
    Logger.debug("RichDataImportModal update called with assigns: #{inspect(Map.keys(assigns))}")

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:search_query, fn -> "" end)
     |> assign_new(:current_provider, fn -> "tmdb" end)
     |> assign_new(:search_results, fn -> [] end)
     |> assign_new(:preview_data, fn -> nil end)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:error, fn -> nil end)}
  end

  @impl true
  def handle_event("search_input", %{"search" => %{"query" => query}}, socket) do
    perform_search(query, socket)
  end

  @impl true
  def handle_event("search_input", %{"value" => query}, socket) do
    # Handle direct input change events
    perform_search(query, socket)
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    # Handle form submission
    perform_search(query, socket)
  end

  # Remove the duplicate search handler and replace with a helper function
  defp perform_search(query, socket) do
    if String.trim(query) == "" do
      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:error, nil)
       |> assign(:loading, false)}
    else
      send(self(), {:rich_data_search, query, socket.assigns.current_provider})

      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:loading, true)
       |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_event("set_provider", %{"provider" => provider}, socket) do
    {:noreply,
     socket
     |> assign(:current_provider, provider)
     |> assign(:search_results, [])
     |> assign(:preview_data, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("import_result", %{"id" => id, "provider" => provider, "type" => type}, socket) do
    require Logger
    Logger.debug("RichDataImportModal import_result called with id: #{id}, provider: #{provider}, type: #{type}")

    # Send message to parent to trigger import
    send(self(), {:rich_data_import, id, provider, type})

    {:noreply,
     socket
     |> assign(:loading, true)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("preview_result", %{"id" => id, "provider" => provider, "type" => type}, socket) do
    require Logger
    Logger.debug("RichDataImportModal handle_event preview_result called with id: #{id}, provider: #{provider}, type: #{type}")

    # Send message to parent to get preview data
    send(self(), {:rich_data_preview, id, provider, type})

    {:noreply,
     socket
     |> assign(:loading, true)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("cancel_preview", _params, socket) do
    {:noreply,
     socket
     |> assign(:preview_data, nil)}
  end

  @impl true
  def handle_event("import_data", _params, socket) do
    if socket.assigns.preview_data do
      send(self(), {:rich_data_import, socket.assigns.preview_data})

      # Close modal and show success feedback
      {:noreply,
       socket
       |> assign(:preview_data, nil)
       |> assign(:search_results, [])
       |> assign(:search_query, "")
       |> assign(:show_success, true)
      }
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_rich_data_modal})
    {:noreply, socket}
  end
end
