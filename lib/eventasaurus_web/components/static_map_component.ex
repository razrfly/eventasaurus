defmodule EventasaurusWeb.StaticMapComponent do
  @moduledoc """
  A reusable component for displaying static Mapbox maps for event venues.
  
  Supports:
  - Multiple themes with different map styles
  - Responsive sizing for mobile and desktop
  - Accessibility features
  - Error handling and graceful fallbacks
  - Loading states
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
      <div class={["bg-white border border-gray-200 rounded-xl p-4 sm:p-6 mb-8 shadow-sm", @class]}>
        <h2 class="text-xl font-semibold mb-4 text-gray-900">Location</h2>
        
        <!-- Address fallback (always visible) -->
        <div class="mb-4">
          <p class="text-gray-700 font-medium"><%= @venue.name %></p>
          <%= if @venue.address do %>
            <p class="text-gray-600"><%= format_address(@venue) %></p>
          <% end %>
        </div>
        
        <!-- Map image -->
        <div class={map_container_classes(@size)} id={"map-container-#{@id}"}>
          <img
            src={mapbox_static_url(@venue, @theme, @size)}
            alt={map_alt_text(@venue)}
            class="w-full h-full object-cover rounded-lg"
            loading="lazy"
            onerror={"this.style.display='none'; document.getElementById('map-fallback-#{@id}').style.display='block'"}
          />
          
          <!-- Error fallback (hidden by default) -->
          <div 
            id={"map-fallback-#{@id}"} 
            class="hidden w-full h-full bg-gray-100 rounded-lg flex items-center justify-center text-gray-500 text-sm"
          >
            <div class="text-center">
              <svg class="w-8 h-8 mx-auto mb-2" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"></path>
              </svg>
              <p>Map unavailable</p>
            </div>
          </div>
        </div>
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
  
  defp has_coordinates?(%{latitude: lat, longitude: lon}) when is_float(lat) and is_float(lon), do: true
  defp has_coordinates?(_), do: false
  
  defp has_address?(%{address: address}) when is_binary(address) and address != "", do: true
  defp has_address?(_), do: false
  
  defp format_address(venue) do
    parts = [
      venue.address,
      venue.city,
      venue.state,
      venue.country
    ]
    |> Enum.filter(fn part -> is_binary(part) and String.trim(part) != "" end)
    |> Enum.join(", ")
    
    parts
  end
  
  defp map_container_classes(size) do
    base_classes = ["relative overflow-hidden"]
    
    size_classes = case size do
      :small -> ["h-48"]      # ~200px
      :large -> ["h-80"]      # ~320px
      _ -> ["h-64"]           # ~256px (medium default)
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
      coords = "#{lon},#{lat},15"  # zoom level 15
      dimensions = "#{width}x#{height}"
      
      "#{base_url}/#{marker}/#{coords}/#{dimensions}?access_token=#{access_token}"
    else
      ""
    end
  end
  
  defp get_coordinates(%{latitude: lat, longitude: lon}) when is_float(lat) and is_float(lon) do
    {lat, lon}
  end
  
  defp get_coordinates(_venue) do
    # If no coordinates, we would need to geocode the address
    # For now, return a default (this should be handled by should_render_map?)
    {0.0, 0.0}
  end
  
  defp get_mapbox_style_id(theme) do
    # Use your custom Mapbox style for all themes for now
    # Later we can create different custom styles for different themes
    "holden/cm7pbsjwv004401sc5z5ldatr"
  end
  
  defp get_marker_color(theme) do
    # Theme-specific marker colors (3-character hex codes for Mapbox)
    case theme do
      :cosmic -> "7c3aed"      # Purple
      :velocity -> "ef4444"    # Red  
      :retro -> "f59e0b"       # Amber
      :celebration -> "ec4899" # Pink
      :nature -> "10b981"      # Emerald
      :professional -> "3b82f6" # Blue
      _ -> "6b7280"           # Gray (minimal default)
    end
  end
  
  defp get_map_dimensions(size) do
    # Return {width, height} for different sizes
    # Using 2x for retina displays
    case size do
      :small -> {600, 400}   # 300x200 display size
      :large -> {1200, 600}  # 600x300 display size  
      _ -> {1000, 500}       # 500x250 display size (medium)
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