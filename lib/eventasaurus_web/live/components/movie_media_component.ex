defmodule EventasaurusWeb.Live.Components.MovieMediaComponent do
  @moduledoc """
  Media section component for movie/TV show display.

  Displays images, videos, and other media content with
  interactive galleries and video previews.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:images, fn -> [] end)
     |> assign_new(:videos, fn -> [] end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-lg p-6">
      <div class="space-y-6">
        <!-- Videos Section -->
        <%= if @display_videos && length(@display_videos) > 0 do %>
          <div>
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Videos</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for video <- @display_videos do %>
                <.video_card video={video} />
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Images Section -->
        <%= if @display_images && length(@display_images) > 0 do %>
          <div>
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Images</h2>

            <!-- Image type tabs -->
            <div class="flex space-x-1 mb-4">
              <button
                phx-click="set_image_type"
                phx-value-type="all"
                phx-target={@myself}
                class={["px-3 py-2 text-sm font-medium rounded-md",
                  @current_image_type == "all" && "bg-indigo-100 text-indigo-700" || "text-gray-500 hover:text-gray-700"]}
              >
                All (<%= length(@display_images) %>)
              </button>

              <%= if @backdrop_images && length(@backdrop_images) > 0 do %>
                <button
                  phx-click="set_image_type"
                  phx-value-type="backdrops"
                  phx-target={@myself}
                  class={["px-3 py-2 text-sm font-medium rounded-md",
                    @current_image_type == "backdrops" && "bg-indigo-100 text-indigo-700" || "text-gray-500 hover:text-gray-700"]}
                >
                  Backdrops (<%= length(@backdrop_images) %>)
                </button>
              <% end %>

              <%= if @poster_images && length(@poster_images) > 0 do %>
                <button
                  phx-click="set_image_type"
                  phx-value-type="posters"
                  phx-target={@myself}
                  class={["px-3 py-2 text-sm font-medium rounded-md",
                    @current_image_type == "posters" && "bg-indigo-100 text-indigo-700" || "text-gray-500 hover:text-gray-700"]}
                >
                  Posters (<%= length(@poster_images) %>)
                </button>
              <% end %>
            </div>

            <!-- Images grid -->
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
              <%= for {image, index} <- Enum.with_index(@filtered_images) do %>
                <.image_card
                  image={image}
                  index={index}
                  type={@current_image_type}
                  myself={@myself}
                />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("set_image_type", %{"type" => type}, socket) do
    filtered_images = get_filtered_images(socket.assigns, type)

    {:noreply,
     socket
     |> assign(:current_image_type, type)
     |> assign(:filtered_images, filtered_images)}
  end

  @impl true
  def handle_event("open_image_modal", %{"index" => index}, socket) do
    # This would typically open a modal or lightbox
    # For now, we'll just track the selected image
    case Integer.parse(index) do
      {idx, _} -> {:noreply, assign(socket, :selected_image_index, idx)}
      :error -> {:noreply, socket}
    end
  end

  # Private function components

  defp video_card(assigns) do
    ~H"""
    <div class="relative group">
      <div class="relative aspect-video bg-gray-900 rounded-lg overflow-hidden">
        <%= if @video["key"] && get_video_thumbnail(@video) do %>
          <img
            src={get_video_thumbnail(@video)}
            alt={@video["name"]}
            class="w-full h-full object-cover"
            loading="lazy"
          />

          <!-- Play button overlay -->
          <div class="absolute inset-0 flex items-center justify-center bg-black/30 group-hover:bg-black/40 transition-colors">
            <button
              onclick={"window.open('#{get_video_url(@video)}', '_blank')"}
              class="w-16 h-16 bg-white/90 hover:bg-white rounded-full flex items-center justify-center transition-colors"
            >
              <.icon name="hero-play" class="w-8 h-8 text-gray-900 ml-1" />
            </button>
          </div>
        <% else %>
          <div class="w-full h-full flex items-center justify-center">
            <.icon name="hero-film" class="w-12 h-12 text-gray-500" />
          </div>
        <% end %>
      </div>

      <div class="mt-2">
        <h3 class="text-sm font-medium text-gray-900 line-clamp-2">
          <%= @video["name"] %>
        </h3>
        <p class="text-xs text-gray-500 capitalize">
          <%= @video["type"] %>
        </p>
      </div>
    </div>
    """
  end

  defp image_card(assigns) do
    ~H"""
    <div class="relative group cursor-pointer">
      <div class="relative aspect-[3/4] bg-gray-200 rounded-lg overflow-hidden">
        <img
          src={get_image_url(@image, @type)}
          alt="Movie image"
          class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
          loading="lazy"
          phx-click="open_image_modal"
          phx-value-index={@index}
          phx-target={@myself}
        />

        <!-- Hover overlay -->
        <div class="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors" />
      </div>
    </div>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    images = socket.assigns.images || []
    videos = socket.assigns.videos || []

    backdrop_images = get_images_by_type(images, "backdrops")
    poster_images = get_images_by_type(images, "posters")

    socket
    |> assign(:display_images, images)
    # Limit videos
    |> assign(:display_videos, Enum.take(videos, 6))
    |> assign(:backdrop_images, backdrop_images)
    |> assign(:poster_images, poster_images)
    |> assign(:current_image_type, "all")
    |> assign(:filtered_images, images)
    |> assign(:selected_image_index, nil)
  end

  defp get_images_by_type(images, type) when is_list(images) do
    case type do
      "backdrops" ->
        Enum.filter(images, fn img ->
          img["aspect_ratio"] && img["aspect_ratio"] > 1.5
        end)

      "posters" ->
        Enum.filter(images, fn img ->
          img["aspect_ratio"] && img["aspect_ratio"] < 1.5
        end)

      _ ->
        images
    end
  end

  defp get_images_by_type(_, _), do: []

  defp get_filtered_images(assigns, type) do
    case type do
      "backdrops" -> assigns.backdrop_images
      "posters" -> assigns.poster_images
      _ -> assigns.display_images
    end
  end

  defp get_video_thumbnail(video) do
    site = video["site"]
    key = video["key"]

    case {site, key} do
      {"YouTube", key} when is_binary(key) ->
        "https://img.youtube.com/vi/#{key}/maxresdefault.jpg"

      _ ->
        nil
    end
  end

  defp get_video_url(video) do
    site = video["site"]
    key = video["key"]

    case {site, key} do
      {"YouTube", key} when is_binary(key) ->
        "https://www.youtube.com/watch?v=#{key}"

      {"Vimeo", key} when is_binary(key) ->
        "https://vimeo.com/#{key}"

      _ ->
        "#"
    end
  end

  defp get_image_url(image, type) do
    path = image["file_path"]

    case type do
      "backdrops" ->
        RichDataDisplayComponent.tmdb_image_url(path, "w500")

      "posters" ->
        RichDataDisplayComponent.tmdb_image_url(path, "w342")

      _ ->
        # Auto-detect based on aspect ratio
        aspect_ratio = image["aspect_ratio"] || 1.0
        size = if aspect_ratio > 1.5, do: "w500", else: "w342"
        RichDataDisplayComponent.tmdb_image_url(path, size)
    end
  end
end
