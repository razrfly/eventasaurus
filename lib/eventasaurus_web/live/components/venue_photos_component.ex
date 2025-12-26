defmodule EventasaurusWeb.Live.Components.VenuePhotosComponent do
  @moduledoc """
  Photos section component for venue/restaurant/activity display.

  Shows photo gallery with responsive grid layout, optimized for large photo
  galleries with lazy loading and virtual scrolling.

  Uses cached_images table (R2 storage) as the source for venue photos.
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Images.ImageCacheService
  alias EventasaurusApp.Images.CachedImage

  # Performance constants
  @photos_per_page 12
  @max_photos_displayed 48

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:current_page, fn -> 1 end)
     |> assign_new(:loading_state, fn -> :idle end)
     |> assign_new(:error_count, fn -> 0 end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="venue-photos-component" role="region" aria-labelledby="photos-heading">
      <%= if @has_photos do %>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm border dark:border-gray-700">
          <div class="p-6">
            <%= if not @compact do %>
              <h3 id="photos-heading" class="text-lg font-semibold text-gray-900 dark:text-white mb-4">
                Photos
                <span class="text-sm font-normal text-gray-500 dark:text-gray-400">
                  (<%= @total_photos %> <%= if @total_photos == 1, do: "photo", else: "photos" %>)
                </span>
              </h3>
            <% end %>

            <%= if @compact do %>
              <!-- Compact horizontal scrolling gallery -->
              <.compact_photo_gallery
                photos={@visible_photos}
                total_photos={@total_photos}
                myself={@myself}
              />
            <% else %>
              <!-- Full gallery with pagination -->
              <.full_photo_gallery
                photos={@visible_photos}
                total_photos={@total_photos}
                current_page={@current_page}
                max_pages={@max_pages}
                loading_state={@loading_state}
                error_count={@error_count}
                myself={@myself}
              />
            <% end %>

            <!-- Photo viewer modal -->
            <%= if @selected_photo do %>
              <.photo_viewer_modal
                photo={@selected_photo}
                photos={@visible_photos}
                selected_index={@selected_index}
                myself={@myself}
              />
            <% end %>

            <!-- Error handling display -->
            <%= if @error_count > 0 and @error_count < @total_photos do %>
              <div class="mt-4 p-3 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg" role="alert">
                <div class="flex items-center gap-2">
                  <svg class="w-4 h-4 text-yellow-600 dark:text-yellow-400" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
                    <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                  </svg>
                  <span class="text-sm text-yellow-800 dark:text-yellow-200">
                    Some photos couldn't be loaded (<%= @error_count %> of <%= @total_photos %>)
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="bg-gray-50 dark:bg-gray-800/50 rounded-lg p-6 text-center border border-gray-200 dark:border-gray-700">
          <svg class="w-12 h-12 text-gray-400 dark:text-gray-500 mx-auto mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
          </svg>
          <p class="text-gray-600 dark:text-gray-400">No photos available</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Component templates

  defp compact_photo_gallery(assigns) do
    ~H"""
    <div
      class="flex gap-3 overflow-x-auto scrollbar-hide pb-2"
      role="list"
      aria-label={"Photo gallery with #{@total_photos} photos"}
    >
      <%= for {photo, index} <- Enum.with_index(@photos) do %>
        <div class="flex-shrink-0" role="listitem">
          <.photo_thumbnail
            photo={photo}
            index={index}
            class="w-24 h-24"
            myself={@myself}
          />
        </div>
      <% end %>

      <%= if @total_photos > length(@photos) do %>
        <div class="flex-shrink-0 w-24 h-24 bg-gray-100 dark:bg-gray-700 rounded-lg flex items-center justify-center text-gray-500 dark:text-gray-400 text-xs">
          +<%= @total_photos - length(@photos) %><br/>more
        </div>
      <% end %>
    </div>
    """
  end

  defp full_photo_gallery(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Photos grid with responsive layout -->
      <div
        class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4"
        role="list"
        aria-label={"Photo gallery showing page #{@current_page} of #{@max_pages}"}
      >
        <%= for {photo, index} <- Enum.with_index(@photos) do %>
          <div class="aspect-square" role="listitem">
            <.photo_thumbnail
              photo={photo}
              index={index}
              class="w-full h-full"
              myself={@myself}
            />
          </div>
        <% end %>

        <!-- Loading placeholders -->
        <%= if @loading_state == :loading do %>
          <%= for _ <- 1..(@photos_per_page - length(@photos)) do %>
            <div class="aspect-square bg-gray-200 dark:bg-gray-700 rounded-lg animate-pulse" aria-hidden="true">
              <div class="w-full h-full flex items-center justify-center">
                <svg class="w-8 h-8 text-gray-400 dark:text-gray-500" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd"/>
                </svg>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- Pagination controls -->
      <%= if @max_pages > 1 do %>
        <.pagination_controls
          current_page={@current_page}
          max_pages={@max_pages}
          total_photos={@total_photos}
          loading_state={@loading_state}
          myself={@myself}
        />
      <% end %>

      <!-- Performance info (dev mode only) -->
      <%= if Application.get_env(:eventasaurus, :env) == :dev do %>
        <div class="text-xs text-gray-500 dark:text-gray-400 mt-2">
          Performance: Showing <%= length(@photos) %> of <%= @total_photos %> photos
          <%= if @error_count > 0 do %>
            | <%= @error_count %> errors
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp photo_thumbnail(assigns) do
    ~H"""
    <div
      class={[
        "relative group overflow-hidden rounded-lg bg-gray-200 dark:bg-gray-700 cursor-pointer",
        "hover:scale-105 transition-transform duration-200",
        @class
      ]}
      phx-click="show_photo"
      phx-value-index={@index}
      phx-target={@myself}
      role="button"
      tabindex="0"
      aria-label={"View photo #{@index + 1} in full size"}
      onkeydown="if(event.key === 'Enter' || event.key === ' ') this.click()"
    >
      <!-- Progressive enhancement: show thumbnail first, then full image -->
      <%= if @photo.thumbnail_url do %>
        <img
          src={@photo.thumbnail_url}
          alt={"Photo #{@index + 1}"}
          class="w-full h-full object-cover absolute inset-0"
          loading="lazy"
          role="img"
        />
      <% end %>

      <img
        id={"photo-#{@index}"}
        src={@photo.url}
        alt={"Photo #{@index + 1}"}
        class={[
          "w-full h-full object-cover transition-opacity duration-300",
          if(@photo.thumbnail_url, do: "opacity-0 hover:opacity-100", else: "")
        ]}
        loading="lazy"
        role="img"
        phx-hook="LazyImage"
        data-src={@photo.url}
        onload="this.style.opacity='1'"
        onerror="this.style.display='none'; this.parentElement.classList.add('bg-gray-300', 'dark:bg-gray-600')"
      />

      <!-- Hover overlay -->
      <div class="absolute inset-0 bg-black/20 opacity-0 group-hover:opacity-100 transition-opacity duration-200 flex items-center justify-center" aria-hidden="true">
        <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7"/>
        </svg>
      </div>

      <!-- Error state -->
      <div class="absolute inset-0 hidden bg-gray-100 dark:bg-gray-700 items-center justify-center photo-error-state">
        <svg class="w-8 h-8 text-gray-400 dark:text-gray-500" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd"/>
        </svg>
      </div>
    </div>
    """
  end

  defp pagination_controls(assigns) do
    ~H"""
    <div class="flex items-center justify-between pt-4 border-t border-gray-200 dark:border-gray-700">
      <div class="flex items-center gap-2">
        <button
          type="button"
          phx-click="prev_page"
          phx-target={@myself}
          disabled={@current_page <= 1 or @loading_state == :loading}
          class={[
            "px-3 py-2 text-sm font-medium rounded-md transition-colors",
            "disabled:opacity-50 disabled:cursor-not-allowed",
            if(@current_page <= 1 or @loading_state == :loading,
              do: "bg-gray-100 dark:bg-gray-700 text-gray-400 dark:text-gray-500",
              else: "bg-gray-200 dark:bg-gray-600 text-gray-700 dark:text-gray-200 hover:bg-gray-300 dark:hover:bg-gray-500"
            )
          ]}
          aria-label="Go to previous page"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
          </svg>
        </button>

        <span class="text-sm text-gray-600 dark:text-gray-400" aria-live="polite">
          Page <%= @current_page %> of <%= @max_pages %>
        </span>

        <button
          type="button"
          phx-click="next_page"
          phx-target={@myself}
          disabled={@current_page >= @max_pages or @loading_state == :loading}
          class={[
            "px-3 py-2 text-sm font-medium rounded-md transition-colors",
            "disabled:opacity-50 disabled:cursor-not-allowed",
            if(@current_page >= @max_pages or @loading_state == :loading,
              do: "bg-gray-100 dark:bg-gray-700 text-gray-400 dark:text-gray-500",
              else: "bg-gray-200 dark:bg-gray-600 text-gray-700 dark:text-gray-200 hover:bg-gray-300 dark:hover:bg-gray-500"
            )
          ]}
          aria-label="Go to next page"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
          </svg>
        </button>
      </div>

      <div class="text-sm text-gray-500 dark:text-gray-400">
        Showing <%= (@current_page - 1) * @photos_per_page + 1 %>-<%= min(@current_page * @photos_per_page, @total_photos) %> of <%= @total_photos %>
      </div>
    </div>
    """
  end

  defp photo_viewer_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby="photo-viewer-title"
      phx-click="close_photo"
      phx-target={@myself}
      phx-window-keydown="handle_keydown"
      phx-key="Escape"
    >
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-black/80 transition-opacity" aria-hidden="true"></div>

      <!-- Modal content -->
      <div class="relative min-h-screen flex items-center justify-center p-4">
        <div
          class="relative max-w-6xl w-full"
          phx-click="stop_propagation"
          phx-target={@myself}
        >
          <!-- Photo -->
          <div class="relative">
            <img
              src={@photo.url}
              alt={"Photo #{@selected_index + 1}"}
              class="w-full h-auto max-h-[80vh] object-contain rounded-lg shadow-2xl"
              role="img"
            />

            <!-- Close button -->
            <button
              type="button"
              phx-click="close_photo"
              phx-target={@myself}
              class="absolute top-4 right-4 p-2 bg-black/50 text-white rounded-full hover:bg-black/70 transition-colors"
              aria-label="Close photo viewer"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>

            <!-- Navigation arrows -->
            <%= if @selected_index > 0 do %>
              <button
                type="button"
                phx-click="prev_photo"
                phx-target={@myself}
                class="absolute left-4 top-1/2 transform -translate-y-1/2 p-3 bg-black/50 text-white rounded-full hover:bg-black/70 transition-colors"
                aria-label="Previous photo"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
                </svg>
              </button>
            <% end %>

            <%= if @selected_index < length(@photos) - 1 do %>
              <button
                type="button"
                phx-click="next_photo"
                phx-target={@myself}
                class="absolute right-4 top-1/2 transform -translate-y-1/2 p-3 bg-black/50 text-white rounded-full hover:bg-black/70 transition-colors"
                aria-label="Next photo"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
                </svg>
              </button>
            <% end %>
          </div>

          <!-- Photo info -->
          <div class="mt-4 text-center text-white">
            <h2 id="photo-viewer-title" class="text-lg font-medium">
              Photo <%= @selected_index + 1 %> of <%= length(@photos) %>
            </h2>
            <%= if @photo.width and @photo.height do %>
              <p class="text-sm text-gray-300 mt-1">
                <%= @photo.width %> × <%= @photo.height %> pixels
              </p>
            <% end %>
            <%= if @photo[:provider] do %>
              <p class="text-xs text-gray-400 mt-2">
                Source: <%= String.capitalize(@photo.provider) %>
              </p>
            <% end %>
            <%= if @photo[:attribution] do %>
              <p class="text-xs text-gray-300 mt-1">
                <%= if safe_external_url(@photo[:attribution_url]) do %>
                  <a
                    href={safe_external_url(@photo[:attribution_url])}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline hover:text-white transition-colors"
                  >
                    <%= @photo.attribution %>
                  </a>
                <% else %>
                  <%= @photo.attribution %>
                <% end %>
              </p>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("show_photo", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    photos = socket.assigns.visible_photos

    case Enum.at(photos, index) do
      nil ->
        {:noreply, socket}

      photo ->
        {:noreply,
         socket
         |> assign(:selected_photo, photo)
         |> assign(:selected_index, index)}
    end
  end

  @impl true
  def handle_event("close_photo", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_photo, nil)
     |> assign(:selected_index, nil)}
  end

  @impl true
  def handle_event("prev_photo", _params, socket) do
    current_index = socket.assigns.selected_index
    photos = socket.assigns.visible_photos

    new_index = max(0, current_index - 1)
    new_photo = Enum.at(photos, new_index)

    {:noreply,
     socket
     |> assign(:selected_photo, new_photo)
     |> assign(:selected_index, new_index)}
  end

  @impl true
  def handle_event("next_photo", _params, socket) do
    current_index = socket.assigns.selected_index
    photos = socket.assigns.visible_photos

    new_index = min(length(photos) - 1, current_index + 1)
    new_photo = Enum.at(photos, new_index)

    {:noreply,
     socket
     |> assign(:selected_photo, new_photo)
     |> assign(:selected_index, new_index)}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    current_page = socket.assigns.current_page

    if current_page > 1 do
      new_page = current_page - 1
      {:noreply, load_page(socket, new_page)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    current_page = socket.assigns.current_page
    max_pages = socket.assigns.max_pages

    if current_page < max_pages do
      new_page = current_page + 1
      {:noreply, load_page(socket, new_page)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("handle_keydown", %{"key" => "Escape"}, socket) do
    {:noreply,
     socket
     |> assign(:selected_photo, nil)
     |> assign(:selected_index, nil)}
  end

  def handle_event("handle_keydown", %{"key" => "ArrowLeft"}, socket) do
    if socket.assigns.selected_photo do
      handle_event("prev_photo", %{}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("handle_keydown", %{"key" => "ArrowRight"}, socket) do
    if socket.assigns.selected_photo do
      handle_event("next_photo", %{}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("handle_keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # This prevents click events from bubbling up to close the modal
    {:noreply, socket}
  end

  # Private functions

  defp safe_external_url(nil), do: nil

  defp safe_external_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> url
      _ -> nil
    end
  end

  defp assign_computed_data(socket) do
    # Photo source: cached_images table (R2 storage)
    # Falls back to rich_data for legacy compatibility
    venue = Map.get(socket.assigns, :venue)
    rich_data = socket.assigns.rich_data

    all_photos =
      cond do
        # Primary: Get photos from cached_images table
        venue && is_map(venue) && Map.has_key?(venue, :id) ->
          get_cached_images_for_venue(venue.id)

        # Legacy fallback: rich_data.images format
        is_map(rich_data) && Map.has_key?(rich_data, :images) && is_list(rich_data.images) ->
          normalize_photos(rich_data.images)

        is_map(rich_data) && Map.has_key?(rich_data, "images") && is_list(rich_data["images"]) ->
          normalize_photos(rich_data["images"])

        # Standardized format from rich_data
        is_map(rich_data) ->
          case get_in(rich_data, [:sections, :photos, :photos]) do
            photos when is_list(photos) -> normalize_standardized_photos(photos)
            _ -> nil
          end || []

        true ->
          []
      end

    # Limit total photos for performance
    total_photos = min(length(all_photos), @max_photos_displayed)
    limited_photos = Enum.take(all_photos, total_photos)

    # Calculate pagination
    current_page = socket.assigns.current_page
    max_pages = max(1, ceil(total_photos / @photos_per_page))

    # Get photos for current page
    start_index = (current_page - 1) * @photos_per_page

    visible_photos =
      limited_photos
      |> Enum.drop(start_index)
      |> Enum.take(@photos_per_page)

    socket
    |> assign(:all_photos, limited_photos)
    |> assign(:visible_photos, visible_photos)
    |> assign(:total_photos, total_photos)
    |> assign(:max_pages, max_pages)
    |> assign(:photos_per_page, @photos_per_page)
    |> assign(:has_photos, total_photos > 0)
    |> assign(:selected_photo, nil)
    |> assign(:selected_index, nil)
  end

  defp load_page(socket, page) do
    all_photos = socket.assigns.all_photos
    _total_photos = socket.assigns.total_photos

    # Calculate photos for the new page
    start_index = (page - 1) * @photos_per_page

    visible_photos =
      all_photos
      |> Enum.drop(start_index)
      |> Enum.take(@photos_per_page)

    socket
    |> assign(:current_page, page)
    |> assign(:visible_photos, visible_photos)
    |> assign(:loading_state, :idle)
  end

  defp normalize_standardized_photos(photos) when is_list(photos) do
    photos
    |> Enum.filter(&is_valid_standardized_photo?/1)
    |> Enum.map(&normalize_standardized_photo/1)
  end

  defp normalize_standardized_photos(_), do: []

  defp normalize_photos(images) when is_list(images) do
    images
    |> Enum.filter(&is_valid_photo?/1)
    |> Enum.map(&normalize_photo/1)
  end

  defp normalize_photos(_), do: []

  defp is_valid_standardized_photo?(photo) when is_map(photo) do
    Map.has_key?(photo, :url) or Map.has_key?(photo, "url")
  end

  defp is_valid_standardized_photo?(_), do: false

  defp is_valid_photo?(image) when is_map(image) do
    Map.has_key?(image, "url") and is_binary(image["url"])
  end

  defp is_valid_photo?(_), do: false

  defp normalize_standardized_photo(photo) when is_map(photo) do
    %{
      url: Map.get(photo, :url) || Map.get(photo, "url"),
      alt: Map.get(photo, :alt) || Map.get(photo, "alt") || "Photo",
      thumbnail_url: Map.get(photo, :thumbnail_url) || Map.get(photo, "thumbnail_url"),
      width: Map.get(photo, :width) || Map.get(photo, "width"),
      height: Map.get(photo, :height) || Map.get(photo, "height")
    }
  end

  defp normalize_photo(image) when is_map(image) do
    %{
      url: Map.get(image, "url"),
      alt: "Photo",
      thumbnail_url: Map.get(image, "thumbnail_url"),
      width: Map.get(image, "width"),
      height: Map.get(image, "height")
    }
  end

  # Get cached images from the cached_images table for a venue
  defp get_cached_images_for_venue(venue_id) when is_integer(venue_id) do
    ImageCacheService.get_entity_images("venue", venue_id)
    |> Enum.map(&normalize_cached_image/1)
  end

  defp get_cached_images_for_venue(_), do: []

  # Convert CachedImage struct to the format expected by the component
  defp normalize_cached_image(%CachedImage{} = cached_image) do
    %{
      url: CachedImage.effective_url(cached_image),
      alt: "Photo",
      thumbnail_url: nil,
      width: nil,
      height: nil,
      provider: cached_image.original_source,
      attribution: get_attribution(cached_image),
      attribution_url: nil,
      position: cached_image.position
    }
  end

  # Extract attribution from metadata if available
  defp get_attribution(%CachedImage{metadata: metadata}) when is_map(metadata) do
    metadata["attribution"] || metadata[:attribution]
  end

  defp get_attribution(_), do: nil
end
