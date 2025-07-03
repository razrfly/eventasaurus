defmodule EventasaurusWeb.Components.ImagePickerModal do
  use EventasaurusWeb, :html

  def image_picker_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        id={"#{@id}-modal"}
        class="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        phx-window-keydown={@on_close}
        phx-key="escape"
        tabindex="-1"
      >
        <div class="bg-white rounded-lg shadow-xl w-full max-w-5xl max-h-[90vh] flex flex-col" phx-click-away={@on_close}>
          <!-- Header -->
          <div class="p-4 border-b border-gray-200 flex justify-between items-center">
            <h2 id={"#{@id}-title"} class="text-xl font-bold">Choose a Cover Image</h2>
            <button type="button" phx-click={@on_close} aria-label="Close image picker" class="text-gray-500 hover:text-gray-700">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>

          <!-- Unified Content -->
          <div class="flex flex-1 overflow-hidden">
            <!-- Left Sidebar - Categories -->
            <div class="w-1/4 p-4 border-r border-gray-200 overflow-y-auto">
              <h3 class="font-semibold text-gray-900 mb-3">Categories</h3>
              <ul class="space-y-1">
                <!-- Dynamic Categories -->
                <%= for category <- @default_categories do %>
                  <li>
                    <button
                      type="button"
                      phx-click="select_category"
                      phx-value-category={category.name}
                      class={[
                        "w-full text-left px-3 py-2 rounded-md text-sm",
                        if(@selected_category == category.name, do: "bg-indigo-100 text-indigo-700 font-medium", else: "text-gray-700 hover:bg-gray-100")
                      ]}
                    >
                      <%= category.display_name %>
                    </button>
                  </li>
                <% end %>
              </ul>
            </div>

            <!-- Main Content Area -->
            <div class="flex-1 p-4 overflow-y-auto">
              <!-- Upload Section -->
              <div class="mb-6">
                <div class="flex flex-col items-center justify-center border-2 border-dashed border-gray-300 rounded-lg p-6 bg-gray-50">
                  <svg class="w-12 h-12 text-gray-400 mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path>
                  </svg>
                  <p class="text-lg font-medium text-gray-900 mb-1">Drag and drop or click here to upload</p>
                  <p class="text-sm text-gray-500 mb-3">PNG, JPG, or WEBP up to 10MB</p>
                  <input
                    type="file"
                    accept="image/*"
                    phx-hook="SupabaseImageUpload"
                    id={"#{@id}-upload-input"}
                    class="hidden"
                    data-access-token={@supabase_access_token}
                  />
                  <label for={"#{@id}-upload-input"} class="cursor-pointer inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                    Choose File
                  </label>
                </div>
              </div>

              <!-- Search Section -->
              <div class="mb-6">
                <form phx-submit="unified_search" class="flex">
                  <div class="relative flex-grow">
                    <input
                      type="text"
                      name="search_query"
                      value={@search_query}
                      phx-change="unified_search"
                      phx-debounce="500"
                      class="w-full px-4 py-2 border border-gray-300 rounded-l-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
                      placeholder="Search for more photos"
                      aria-label="Search for more photos"
                    />
                    <!-- Search indicator -->
                    <%= if @loading do %>
                      <div class="absolute inset-y-0 right-2 flex items-center">
                        <div class="w-4 h-4 border-t-2 border-b-2 border-indigo-500 rounded-full animate-spin"></div>
                      </div>
                    <% else %>
                      <div class="absolute inset-y-0 right-2 flex items-center">
                        <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                        </svg>
                      </div>
                    <% end %>
                  </div>
                  <button
                    type="submit"
                    class="px-4 py-2 bg-indigo-600 border border-transparent rounded-r-md shadow-sm text-sm font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                  >
                    Search
                  </button>
                </form>
              </div>

              <!-- Loading State -->
              <%= if @loading do %>
                <div class="flex justify-center my-8">
                  <div class="w-8 h-8 border-t-2 border-b-2 border-indigo-500 rounded-full animate-spin"></div>
                </div>
              <% end %>

              <!-- Error State -->
              <%= if @error do %>
                <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded relative mb-6" role="alert">
                  <span class="block sm:inline"><%= @error %></span>
                </div>
              <% end %>

              <!-- Images Grid -->
              <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
                <!-- Default Images -->
                <%= if @search_query == "" do %>
                  <%= for image <- @default_images do %>
                    <div
                      class="relative group cursor-pointer overflow-hidden rounded-md bg-gray-100"
                      phx-click="select_default_image"
                      phx-value-image_url={image.url}
                      phx-value-filename={image.filename}
                      phx-value-category={image.category}
                      tabindex="0"
                      role="button"
                      aria-label={"Select #{image.title}"}
                    >
                      <img
                        src={image.url}
                        alt={image.title}
                        class="w-full h-32 object-cover transform transition-transform duration-300 group-hover:scale-110"
                      />
                      <div class="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-40 transition-opacity duration-300"></div>
                      <div class="absolute bottom-0 left-0 right-0 p-2 text-white bg-gradient-to-t from-black to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                        <p class="text-xs truncate"><%= image.title %></p>
                      </div>
                    </div>
                  <% end %>
                <% else %>
                  <!-- Search Results - Unsplash -->
                  <% unsplash = @search_results[:unsplash] || [] %>
                  <%= for image <- unsplash do %>
                    <div
                      id={"unsplash-image-#{image[:id]}"}
                      data-image={Jason.encode!(%{cover_image_url: image[:urls][:regular], unsplash_data: image})}
                      phx-hook="ImagePicker"
                      class="relative group cursor-pointer overflow-hidden rounded-md"
                      tabindex="0"
                      role="button"
                      aria-label={"Select image by " <> (image.user[:name] || "Unsplash photographer")}
                    >
                      <img
                        src={image[:urls][:small]}
                        alt={image[:description] || "Unsplash image"}
                        class="w-full h-32 object-cover transform transition-transform duration-300 group-hover:scale-110"
                      />
                      <div class="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-40 transition-opacity duration-300"></div>
                      <div class="absolute bottom-0 left-0 right-0 p-2 text-white bg-gradient-to-t from-black to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                        <p class="text-xs truncate">Photo by <%= image.user[:name] || "Unsplash photographer" %></p>
                      </div>
                    </div>
                  <% end %>

                  <!-- Search Results - TMDB -->
                  <% tmdb = @search_results[:tmdb] || [] %>
                  <%= for item <- tmdb, (item.type != :person or (item.profile_path && item.profile_path != "")),
                    src = (item.type == :person && item.profile_path && ("https://image.tmdb.org/t/p/w500" <> item.profile_path)) ||
                          (item.type != :person && item.poster_path && ("https://image.tmdb.org/t/p/w500" <> item.poster_path)) ||
                          "/images/placeholder.png",
                    src != "/images/placeholder.png" do %>
                    <% display_name = item[:title] || item[:name] || item["title"] || item["name"] %>
                    <div
                      id={"tmdb-image-#{item[:id] || item["id"]}"}
                      data-image={Jason.encode!(%{
                        cover_image_url: src,
                        tmdb_data: item,
                        source: "tmdb"
                      })}
                      phx-hook="ImagePicker"
                      class="relative group cursor-pointer overflow-hidden rounded-md bg-gray-50"
                      tabindex="0"
                      role="button"
                      aria-label={"Select image: " <> display_name}
                    >
                      <img
                        src={src}
                        alt={display_name}
                        class="w-full h-32 object-cover transform transition-transform duration-300 group-hover:scale-110"
                      />
                      <div class="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-40 transition-opacity duration-300"></div>
                      <div class="absolute bottom-0 left-0 right-0 p-2 text-white bg-gradient-to-t from-black to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                        <div class="font-bold text-xs truncate"><%= display_name %></div>
                        <div class="flex justify-between items-center gap-2 text-xs text-gray-200 mt-1">
                          <span class="inline-block px-1 py-0.5 rounded bg-indigo-600 bg-opacity-80 text-xs">
                            <%= if item.type == :movie do %>Movie<% end %>
                            <%= if item.type == :tv do %>TV Show<% end %>
                            <%= if item.type == :person do %>Person<% end %>
                            <%= if item.type == :collection do %>Collection<% end %>
                          </span>
                          <span class="text-xs">
                            <%= if item.type == :movie and item.release_date do %><%= String.slice(item.release_date, 0, 4) %><% end %>
                            <%= if item.type == :tv and item.first_air_date do %><%= String.slice(item.first_air_date, 0, 4) %><% end %>
                          </span>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <!-- Empty States -->
              <%= if @search_query == "" and length(@default_images) == 0 do %>
                <div class="text-center py-12 text-gray-500">
                  <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"></path>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"></path>
                  </svg>
                  <p class="mt-2 text-sm">No images available in this category</p>
                </div>
              <% end %>

              <%= if @search_query != "" and not @loading and length((@search_results[:unsplash] || []) ++ (@search_results[:tmdb] || [])) == 0 do %>
                <div class="text-center py-12 text-gray-500">
                  <p class="mt-2 text-sm">No results found for "<%= @search_query %>"</p>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Footer -->
          <div class="p-4 border-t border-gray-200 flex justify-end">
            <button
              type="button"
              phx-click={@on_close}
              class="px-4 py-2 bg-gray-200 text-gray-800 rounded-md hover:bg-gray-300"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
