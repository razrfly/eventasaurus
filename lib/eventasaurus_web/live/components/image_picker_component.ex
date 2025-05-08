defmodule EventasaurusWeb.Live.Components.ImagePickerComponent do
  use EventasaurusWeb, :live_component

  alias EventasaurusWeb.Services.UnsplashService

  @impl true
  def mount(socket) do
    {:ok,
      socket
      |> assign(:tab, "unsplash")
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:selected_image, nil)
      |> assign(:page, 1)
      |> assign(:per_page, 20)
    }
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
      socket
      |> assign(assigns)
      |> assign(:tab, Map.get(assigns, :tab, "unsplash"))
    }
  end

  @impl true
  def handle_event("change-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_event("search", %{"search_query" => query}, socket) when query == "" do
    {:noreply,
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:error, nil)
    }
  end

  @impl true
  def handle_event("search", %{"search_query" => query}, socket) do
    {:noreply,
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)
      |> assign(:page, 1)
      |> do_search()
    }
  end

  @impl true
  def handle_event("load-more", _, socket) do
    {:noreply,
      socket
      |> assign(:page, socket.assigns.page + 1)
      |> assign(:loading, true)
      |> do_search()
    }
  end

  @impl true
  def handle_event("select-image", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.search_results, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      image ->
        selected_image = %{
          id: image.id,
          description: image.description,
          url: image.urls.regular,
          user: %{
            name: image.user.name,
            username: image.user.username,
            profile_url: image.user.profile_url
          },
          download_location: image.download_location
        }

        # Track the download as per Unsplash API requirements
        UnsplashService.track_download(image.download_location)

        # Create the unsplash_data map to be stored in the database
        unsplash_data = %{
          "photo_id" => image.id,
          "url" => image.urls.regular,
          "full_url" => image.urls.full,
          "raw_url" => image.urls.raw,
          "photographer_name" => image.user.name,
          "photographer_username" => image.user.username,
          "photographer_url" => image.user.profile_url,
          "download_location" => image.download_location
        }

        # Send the selected image back to the parent
        send(self(), {:image_selected, %{
          cover_image_url: image.urls.regular,
          unsplash_data: unsplash_data
        }})

        # Also send close event to parent
        send(self(), {:close_image_picker, nil})

        {:noreply, assign(socket, :selected_image, selected_image)}
    end
  end

  defp do_search(socket) do
    case UnsplashService.search_photos(
      socket.assigns.search_query,
      socket.assigns.page,
      socket.assigns.per_page
    ) do
      {:ok, results} ->
        # If this is page 1, replace results, otherwise append
        updated_results =
          if socket.assigns.page == 1 do
            results
          else
            socket.assigns.search_results ++ results
          end

        socket
        |> assign(:search_results, updated_results)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, "Error searching Unsplash: #{reason}")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"image-picker-component-#{@id}"} class="w-full">
      <!-- Tabs -->
      <div class="border-b border-gray-200 mb-6">
        <nav class="-mb-px flex" aria-label="Tabs">
          <button
            phx-click="change-tab"
            phx-value-tab="unsplash"
            phx-target={@myself}
            class={[
              "px-4 py-2 text-sm font-medium border-b-2",
              @tab == "unsplash" && "border-indigo-500 text-indigo-600" || "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
            ]}
          >
            Search Unsplash
          </button>
        </nav>
      </div>

      <!-- Unsplash Search Tab -->
      <div class={@tab == "unsplash" && "block" || "hidden"}>
        <form phx-submit="search" phx-target={@myself} class="mb-6">
          <div class="flex">
            <div class="relative flex-grow">
              <input
                type="text"
                name="search_query"
                id={"search-query-#{@id}"}
                value={@search_query}
                class="w-full px-4 py-2 border border-gray-300 rounded-l-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
                placeholder="Search for images..."
                aria-label="Search for images"
              />
            </div>
            <button
              type="submit"
              class="px-4 py-2 bg-indigo-600 border border-transparent rounded-r-md shadow-sm text-sm font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              Search
            </button>
          </div>
        </form>

        <%= if @loading and @page == 1 do %>
          <div class="flex justify-center my-12">
            <div class="w-12 h-12 border-t-2 border-b-2 border-indigo-500 rounded-full animate-spin"></div>
          </div>
        <% end %>

        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded relative mb-6" role="alert">
            <span class="block sm:inline"><%= @error %></span>
          </div>
        <% end %>

        <%= if length(@search_results) > 0 do %>
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4 mb-6">
            <%= for image <- @search_results do %>
              <div
                phx-click="select-image"
                phx-value-id={image.id}
                phx-target={@myself}
                class="relative group cursor-pointer overflow-hidden rounded-md"
              >
                <img
                  src={image.urls.small}
                  alt={image.description}
                  class="w-full h-40 object-cover transform transition-transform duration-300 group-hover:scale-110"
                />
                <div class="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-40 transition-opacity duration-300"></div>
                <div class="absolute bottom-0 left-0 right-0 p-2 text-white bg-gradient-to-t from-black to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                  <p class="text-xs truncate">Photo by <%= image.user.name %></p>
                </div>
              </div>
            <% end %>
          </div>

          <%= if @loading and @page > 1 do %>
            <div class="flex justify-center my-6">
              <div class="w-8 h-8 border-t-2 border-b-2 border-indigo-500 rounded-full animate-spin"></div>
            </div>
          <% else %>
            <div class="flex justify-center mb-6">
              <button
                phx-click="load-more"
                phx-target={@myself}
                class="px-4 py-2 bg-white border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                Load More
              </button>
            </div>
          <% end %>
        <% else %>
          <%= if @search_query == "" do %>
            <div class="text-center py-12 text-gray-500">
              <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"></path>
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"></path>
              </svg>
              <p class="mt-2 text-sm">Search for images on Unsplash</p>
            </div>
          <% else %>
            <%= if not @loading do %>
              <div class="text-center py-12 text-gray-500">
                <p class="mt-2 text-sm">No results found for "<%= @search_query %>"</p>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
