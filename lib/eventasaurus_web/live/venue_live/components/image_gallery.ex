defmodule EventasaurusWeb.VenueLive.Components.ImageGallery do
  @moduledoc """
  Image gallery component for venue pages.

  Displays 1-5+ images with responsive layouts:
  - 1 image: Full width (h-96)
  - 2 images: Split 50/50 (both h-96)
  - 3 images: Large left (50%, h-96) + 2 stacked right (50%, each h-48)
  - 4 images: Large left (50%, h-96) + 3 grid right
  - 5+ images: Large left (50%, h-96) + 4 grid right (2x2, each h-48)

  Based on trivia_advisor image gallery pattern.
  """
  use Phoenix.Component

  attr :venue, :map, required: true, doc: "Venue with venue_images JSONB field"

  def image_gallery(assigns) do
    assigns = assign(assigns, :images, get_images(assigns.venue))

    ~H"""
    <%= if has_images?(@images) do %>
      <div class="venue-image-gallery">
        <%= case image_layout(length(@images)) do %>
          <% :single -> %>
            <%= render_single_image(assigns) %>
          <% :double -> %>
            <%= render_double_images(assigns) %>
          <% :triple -> %>
            <%= render_triple_images(assigns) %>
          <% :quad -> %>
            <%= render_quad_images(assigns) %>
          <% :gallery -> %>
            <%= render_gallery_images(assigns) %>
        <% end %>
      </div>
    <% else %>
      <div class="text-center py-8 text-gray-500">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
          />
        </svg>
        <p class="mt-2">No images available</p>
      </div>
    <% end %>
    """
  end

  # Layout: Single image - Full width
  defp render_single_image(assigns) do
    ~H"""
    <div class="relative w-full h-96 rounded-lg overflow-hidden">
      <img
        src={get_image_url(Enum.at(@images, 0))}
        alt={"#{@venue.name} - Photo"}
        class="w-full h-full object-cover"
        loading="lazy"
      />
    </div>
    """
  end

  # Layout: Two images - 50/50 split
  defp render_double_images(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-2">
      <%= for {image, index} <- Enum.with_index(@images, 1) do %>
        <div class="relative h-96 rounded-lg overflow-hidden">
          <img
            src={get_image_url(image)}
            alt={"#{@venue.name} - Photo #{index}"}
            class="w-full h-full object-cover"
            loading="lazy"
          />
        </div>
      <% end %>
    </div>
    """
  end

  # Layout: Three images - Large left + 2 stacked right
  defp render_triple_images(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-2">
      <!-- Large image on left -->
      <div class="relative h-96 rounded-lg overflow-hidden">
        <img
          src={get_image_url(Enum.at(@images, 0))}
          alt={"#{@venue.name} - Photo 1"}
          class="w-full h-full object-cover"
          loading="lazy"
        />
      </div>
      <!-- Two stacked images on right -->
      <div class="grid grid-rows-2 gap-2">
        <%= for {image, index} <- Enum.slice(@images, 1..2) |> Enum.with_index(2) do %>
          <div class="relative h-48 rounded-lg overflow-hidden">
            <img
              src={get_image_url(image)}
              alt={"#{@venue.name} - Photo #{index}"}
              class="w-full h-full object-cover"
              loading="lazy"
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Layout: Four images - Large left + 3 grid right
  defp render_quad_images(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-2">
      <!-- Large image on left -->
      <div class="relative h-96 rounded-lg overflow-hidden">
        <img
          src={get_image_url(Enum.at(@images, 0))}
          alt={"#{@venue.name} - Photo 1"}
          class="w-full h-full object-cover"
          loading="lazy"
        />
      </div>
      <!-- 3 images on right: 1 full width + 2 in grid -->
      <div class="grid grid-rows-2 gap-2">
        <!-- Top right: single image -->
        <div class="relative h-48 rounded-lg overflow-hidden">
          <img
            src={get_image_url(Enum.at(@images, 1))}
            alt={"#{@venue.name} - Photo 2"}
            class="w-full h-full object-cover"
            loading="lazy"
          />
        </div>
        <!-- Bottom right: 2 images side by side -->
        <div class="grid grid-cols-2 gap-2">
          <%= for {image, index} <- Enum.slice(@images, 2..3) |> Enum.with_index(3) do %>
            <div class="relative rounded-lg overflow-hidden">
              <img
                src={get_image_url(image)}
                alt={"#{@venue.name} - Photo #{index}"}
                class="w-full h-full object-cover"
                loading="lazy"
              />
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Layout: 5+ images - Large left + 4 grid right (2x2)
  defp render_gallery_images(assigns) do
    assigns = assign(assigns, :remaining_count, length(assigns.images) - 5)

    ~H"""
    <div class="grid grid-cols-2 gap-2">
      <!-- Large image on left -->
      <div class="relative h-96 rounded-lg overflow-hidden">
        <img
          src={get_image_url(Enum.at(@images, 0))}
          alt={"#{@venue.name} - Photo 1"}
          class="w-full h-full object-cover"
          loading="lazy"
        />
      </div>
      <!-- 4 images on right in 2x2 grid -->
      <div class="grid grid-cols-2 grid-rows-2 gap-2">
        <%= for {image, index} <- Enum.slice(@images, 1..4) |> Enum.with_index(2) do %>
          <div class="relative h-48 rounded-lg overflow-hidden">
            <img
              src={get_image_url(image)}
              alt={"#{@venue.name} - Photo #{index}"}
              class="w-full h-full object-cover"
              loading="lazy"
            />
            <!-- Show "+N more" overlay on last image if there are more than 5 -->
            <%= if index == 5 && @remaining_count > 0 do %>
              <div class="absolute inset-0 bg-black bg-opacity-60 flex items-center justify-center">
                <span class="text-white text-2xl font-semibold">+<%= @remaining_count %> more</span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp has_images?(images), do: is_list(images) and length(images) > 0

  defp get_images(%{venue_images: images}) when is_list(images) and images != [] do
    images
  end

  defp get_images(venue) do
    # Enable via config: config :eventasaurus, :enable_dev_imagekit_fetch, true
    dev_fetch? =
      Application.get_env(:eventasaurus, :enable_dev_imagekit_fetch, false) and
        Code.ensure_loaded?(Eventasaurus.ImageKit.Fetcher)

    if dev_fetch? do
      case Eventasaurus.ImageKit.Fetcher.list_venue_images(venue.slug) do
        {:ok, images} -> images
        _ -> []
      end
    else
      []
    end
  end

  defp get_image_url(%{"url" => url}) when is_binary(url), do: url
  defp get_image_url(_), do: "/images/venue-placeholder.png"

  defp image_layout(1), do: :single
  defp image_layout(2), do: :double
  defp image_layout(3), do: :triple
  defp image_layout(4), do: :quad
  defp image_layout(n) when n >= 5, do: :gallery
  defp image_layout(_), do: :single
end
