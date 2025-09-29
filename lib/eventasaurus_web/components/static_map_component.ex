defmodule EventasaurusWeb.StaticMapComponent do
  @moduledoc """
  A reusable component for displaying static Mapbox maps for event venues.

  Supports:
  - Multiple themes with different map styles
  - Responsive sizing for mobile and desktop
  - Accessibility features
  - Error handling and graceful fallbacks
  - Loading states

  ## Security Notes

  This component uses Mapbox Static API tokens in client-side URLs, which is the standard
  approach for static maps. To secure your Mapbox usage:

  1. Use a PUBLIC token (not secret) with minimal required scopes
  2. Enable URL restrictions on your Mapbox token for your domain
  3. Rotate tokens periodically if abuse is detected
  4. Consider rate limiting at the application level

  For more security guidance, see: https://docs.mapbox.com/help/troubleshooting/how-to-use-mapbox-securely/
  """

  use EventasaurusWeb, :live_component

  @doc """
  Renders a static map component for the given venue.

  ## Props

  * `:venue` - The venue struct containing location data
  * `:theme` - The current theme (:minimal, :cosmic, :velocity, etc.)
  * `:size` - Size preset (:small, :medium, :large) - optional, defaults to :medium
  * `:class` - Additional CSS classes - optional

  ## Examples

      <.live_component
        module={EventasaurusWeb.StaticMapComponent}
        id="venue-map"
        venue={@venue}
        theme={@theme}
        size={:medium}
      />
  """
  def render(assigns) do
    # Don't render if venue is nil or doesn't have location data
    if should_render_map?(assigns.venue) do
      ~H"""
      <div class={map_container_classes(@size)} id={"map-container-#{@id}"}>
        <%= if has_coordinates?(@venue) do %>
          <img
            src={mapbox_static_url(@venue, @theme, @size)}
            alt={map_alt_text(@venue)}
            class="w-full h-full object-cover rounded-xl border border-gray-200 shadow-sm"
            loading="lazy"
            onerror={"this.style.display='none'; document.getElementById('map-fallback-#{@id}').style.display='block'"}
          />
          <!-- Error fallback (hidden by default) -->
          <div
            id={"map-fallback-#{@id}"}
            class="hidden w-full h-full bg-gray-100 rounded-xl border border-gray-200 flex items-center justify-center text-gray-500 text-sm"
          >
            <div class="text-center">
              <svg class="w-8 h-8 mx-auto mb-2" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"></path>
              </svg>
              <p>Map unavailable</p>
            </div>
          </div>
        <% else %>
          <!-- Address-only fallback -->
          <div class="w-full h-full bg-gray-100 rounded-xl border border-gray-200 flex items-center justify-center text-gray-500 text-sm">
            <div class="text-center">
              <svg class="w-8 h-8 mx-auto mb-2" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"></path>
              </svg>
              <p>Map unavailable</p>
            </div>
          </div>
        <% end %>
      </div>
      """
    else
      ~H""
    end
  end

  # Private functions

  defp should_render_map?(nil), do: false
  defp should_render_map?(%{venue_type: "online"}), do: false
  defp should_render_map?(%{venue_type: "tbd"}), do: false

  defp should_render_map?(venue) do
    # Require either coordinates or address
    has_coordinates?(venue) || has_address?(venue)
  end

  defp has_coordinates?(%{latitude: lat, longitude: lon}) when is_number(lat) and is_number(lon),
    do: true

  defp has_coordinates?(_), do: false

  defp has_address?(%{address: address}) when is_binary(address) and address != "", do: true
  defp has_address?(_), do: false

  defp format_address(venue) do
    parts =
      [
        venue.address,
        EventasaurusApp.Venues.Venue.city_name(venue),
        EventasaurusApp.Venues.Venue.country_name(venue)
      ]
      |> Enum.filter(fn part -> is_binary(part) and String.trim(part) != "" end)
      |> Enum.join(", ")

    parts
  end

  defp map_container_classes(size) do
    base_classes = ["relative overflow-hidden"]

    size_classes =
      case size do
        # ~200px
        :small -> ["h-48"]
        # ~320px
        :large -> ["h-80"]
        # ~256px (medium default)
        _ -> ["h-64"]
      end

    base_classes ++ size_classes
  end

  defp map_alt_text(venue) do
    if venue.address do
      "Map showing the location of #{venue.name} at #{format_address(venue)}"
    else
      "Map showing the location of #{venue.name}"
    end
  end

  defp mapbox_static_url(venue, theme, size) do
    # Get Mapbox access token from application config
    mapbox_config = Application.get_env(:eventasaurus, :mapbox)
    access_token = if mapbox_config, do: mapbox_config[:access_token], else: nil

    # Fallback to environment variable if not in config (for development)
    access_token = access_token || System.get_env("MAPBOX_ACCESS_TOKEN")

    if access_token && access_token != "" do
      # Determine coordinates
      {lat, lon} = get_coordinates(venue)

      # Get theme-specific style
      style_id = get_mapbox_style_id(theme)

      # Get size dimensions
      {width, height} = get_map_dimensions(size)

      # Build Mapbox Static API URL
      base_url = "https://api.mapbox.com/styles/v1/#{style_id}/static"
      marker = "pin-s+#{get_marker_color(theme)}(#{lon},#{lat})"
      # zoom level 15
      coords = "#{lon},#{lat},15"
      dimensions = "#{width}x#{height}"

      "#{base_url}/#{marker}/#{coords}/#{dimensions}?access_token=#{access_token}"
    else
      ""
    end
  end

  defp get_coordinates(%{latitude: lat, longitude: lon}) when is_number(lat) and is_number(lon) do
    {lat, lon}
  end

  defp get_coordinates(_venue) do
    # If no coordinates, we would need to geocode the address
    # This should not be reached due to should_render_map? check
    raise "Attempted to get coordinates for venue without valid location data"
  end

  defp get_mapbox_style_id(theme) do
    # Map event themes to appropriate Mapbox built-in styles
    case theme do
      # Clean custom style for minimal theme
      :minimal -> "holden/cm7pc60fv00zf01s2846m99jm"
      # Dark style perfect for cosmic theme
      :cosmic -> "mapbox/dark-v11"
      # Clean streets for velocity theme
      :velocity -> "mapbox/streets-v12"
      # Outdoors style for retro theme
      :retro -> "mapbox/outdoors-v12"
      # Satellite streets for celebration
      :celebration -> "mapbox/satellite-streets-v12"
      # Natural features for nature theme
      :nature -> "mapbox/outdoors-v12"
      # Configurable custom style as default
      :professional -> get_default_style_id()
      # Default to configurable professional style
      _ -> get_default_style_id()
    end
  end

  defp get_default_style_id do
    # Allow configurable default style via environment variable
    System.get_env("MAPBOX_DEFAULT_STYLE_ID") || "mapbox/streets-v12"
  end

  defp get_marker_color(theme) do
    # Theme-specific marker colors (3-character hex codes for Mapbox)
    case theme do
      # Purple
      :cosmic -> "7c3aed"
      # Red  
      :velocity -> "ef4444"
      # Amber
      :retro -> "f59e0b"
      # Pink
      :celebration -> "ec4899"
      # Emerald
      :nature -> "10b981"
      # Blue
      :professional -> "3b82f6"
      # Gray (minimal default)
      _ -> "6b7280"
    end
  end

  defp get_map_dimensions(size) do
    # Return {width, height} for different sizes
    # Using 2x for retina displays
    case size do
      # 300x200 display size
      :small -> {600, 400}
      # 600x300 display size  
      :large -> {1200, 600}
      # 500x250 display size (medium)
      _ -> {1000, 500}
    end
  end

  # Default assigns
  def mount(socket) do
    {:ok, assign(socket, size: :medium, class: "")}
  end

  def update(assigns, socket) do
    # Set defaults for optional assigns
    size = assigns[:size] || :medium
    class = assigns[:class] || ""

    socket =
      socket
      |> assign(assigns)
      |> assign(size: size, class: class)

    {:ok, socket}
  end
end
