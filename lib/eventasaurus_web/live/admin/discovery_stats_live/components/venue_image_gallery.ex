defmodule EventasaurusWeb.Admin.DiscoveryStatsLive.Components.VenueImageGallery do
  @moduledoc """
  LiveView component for displaying venue images with enrichment history.
  Shows image previews, provider attribution, quality scores, and enrichment timeline.
  """
  use Phoenix.Component

  attr :venue, :map, required: true, doc: "Venue with preloaded images and metadata"
  attr :show_history, :boolean, default: false, doc: "Whether to show enrichment history"

  def venue_image_gallery(assigns) do
    ~H"""
    <div class="venue-image-gallery">
      <%= if has_images?(@venue) do %>
        <!-- Image Grid -->
        <div class="mb-4">
          <div class="flex items-center justify-between mb-3">
            <h4 class="text-sm font-semibold text-gray-900">
              📸 Images (<%= image_count(@venue) %>)
            </h4>
            <%= if @venue.image_enrichment_metadata do %>
              <span class="text-xs text-gray-500">
                Last enriched: <%= format_last_enriched(@venue) %>
              </span>
            <% end %>
          </div>

          <!-- Image Thumbnails -->
          <div class="grid grid-cols-4 gap-2">
            <%= for {image, index} <- Enum.with_index(get_images(@venue), 1) do %>
              <div class="relative group">
                <img
                  src={get_image_url(image)}
                  alt={"#{@venue.name} - Image #{index}"}
                  class="w-full h-24 object-cover rounded-lg border border-gray-200 hover:border-blue-500 transition-colors"
                  loading="lazy"
                  onerror="this.onerror=null; this.src='/images/venue-placeholder.png'; this.classList.add('opacity-50');"
                />

                <!-- Provider Badge -->
                <div class="absolute top-1 right-1 bg-white/90 backdrop-blur-sm px-2 py-0.5 rounded text-xs font-medium shadow-sm">
                  <%= provider_icon(image["provider"]) %> <%= format_provider_name(image["provider"]) %>
                </div>

                <!-- Quality Score Badge -->
                <%= if image["quality_score"] do %>
                  <div class="absolute bottom-1 left-1 bg-white/90 backdrop-blur-sm px-2 py-0.5 rounded text-xs font-medium shadow-sm">
                    ⭐ <%= Float.round(image["quality_score"], 2) %>
                  </div>
                <% end %>

                <!-- Hover Overlay with Details -->
                <div class="absolute inset-0 bg-black/70 opacity-0 group-hover:opacity-100 transition-opacity rounded-lg flex items-center justify-center">
                  <div class="text-white text-center text-xs p-2">
                    <%= if image["width"] && image["height"] do %>
                      <p class="font-semibold"><%= image["width"] %>×<%= image["height"] %></p>
                    <% end %>
                    <%= if image["fetched_at"] do %>
                      <p class="mt-1 opacity-75">
                        <%= format_date(image["fetched_at"]) %>
                      </p>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Provider Attribution Summary -->
        <div class="flex items-center gap-3 text-xs text-gray-600 mb-3">
          <span class="font-medium">Sources:</span>
          <%= for provider <- get_unique_providers(@venue) do %>
            <span class="inline-flex items-center gap-1 px-2 py-1 bg-gray-100 rounded-full">
              <%= provider_icon(provider) %>
              <%= format_provider_name(provider) %>
            </span>
          <% end %>
        </div>

        <!-- Enrichment History Timeline (if requested) -->
        <%= if @show_history && has_enrichment_history?(@venue) do %>
          <div class="mt-4 pt-4 border-t border-gray-200">
            <h5 class="text-sm font-semibold text-gray-900 mb-3">📊 Enrichment History</h5>
            <div class="space-y-2">
              <%= for entry <- get_enrichment_history(@venue) do %>
                <div class="flex items-start gap-3 text-xs">
                  <div class="flex-shrink-0 w-24 text-gray-500">
                    <%= format_history_date(entry["enriched_at"]) %>
                  </div>
                  <div class="flex-1">
                    <div class="flex items-center gap-2 mb-1">
                      <span class="font-medium text-gray-900">
                        +<%= entry["images_added"] || 0 %> images
                      </span>
                      <%= if entry["providers"] do %>
                        <span class="text-gray-600">
                          from <%= Enum.join(entry["providers"], ", ") %>
                        </span>
                      <% end %>
                    </div>
                    <%= if entry["cost_usd"] do %>
                      <div class="text-gray-500">
                        Cost: $<%= Float.round(entry["cost_usd"], 4) %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      <% else %>
        <!-- No Images State -->
        <div class="text-center py-4 text-gray-500 text-sm">
          <span class="text-2xl">📷</span>
          <p class="mt-2">No images available</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp has_images?(venue) do
    venue.venue_images && is_list(venue.venue_images) && length(venue.venue_images) > 0
  end

  defp get_images(venue) do
    venue.venue_images || []
  end

  defp image_count(venue) do
    venue.venue_images |> Kernel.||([]) |> length()
  end

  defp get_image_url(image) do
    # Use ImageKit URL directly (uploaded during enrichment)
    image["url"]
  end

  defp format_last_enriched(venue) do
    case venue.image_enrichment_metadata do
      %{"last_enriched_at" => timestamp} when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %Y")
          _ -> "Unknown"
        end

      _ ->
        "Unknown"
    end
  end

  defp get_unique_providers(venue) do
    venue.venue_images
    |> Kernel.||([])
    |> Enum.map(fn img -> img["provider"] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp provider_icon("google_places"), do: "🗺️"
  defp provider_icon("foursquare"), do: "📍"
  defp provider_icon("yelp"), do: "⭐"
  defp provider_icon("tripadvisor"), do: "🦉"
  defp provider_icon(_), do: "📸"

  defp format_provider_name("google_places"), do: "Google Places"
  defp format_provider_name("foursquare"), do: "Foursquare"
  defp format_provider_name("yelp"), do: "Yelp"
  defp format_provider_name("tripadvisor"), do: "TripAdvisor"
  defp format_provider_name("here"), do: "HERE Maps"
  defp format_provider_name(nil), do: "Unknown"

  defp format_provider_name(provider) when is_binary(provider) do
    provider
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_provider_name(_), do: "Unknown"

  defp format_date(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %Y")
      _ -> "Unknown"
    end
  end

  defp format_date(_), do: "Unknown"

  defp format_history_date(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d")
      _ -> "Unknown"
    end
  end

  defp format_history_date(_), do: "Unknown"

  defp has_enrichment_history?(venue) do
    case venue.image_enrichment_metadata do
      %{"enrichment_history" => history} when is_list(history) and length(history) > 0 ->
        true

      _ ->
        false
    end
  end

  defp get_enrichment_history(venue) do
    case venue.image_enrichment_metadata do
      %{"enrichment_history" => history} when is_list(history) ->
        history

      _ ->
        []
    end
  end
end
