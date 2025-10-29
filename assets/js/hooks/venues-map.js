/**
 * VenuesMap Hook
 *
 * Renders an interactive Google Map showing multiple venue markers with clustering.
 * Features:
 * - Marker clustering for performance
 * - Info windows with venue details
 * - Responsive design
 * - Dark mode support
 */

const VenuesMap = {
  mounted() {
    this.initMap();
  },

  initMap() {
    // Wait for Google Maps to be loaded
    if (!window.google || !window.google.maps) {
      console.warn("Google Maps not loaded, retrying...");
      setTimeout(() => this.initMap(), 100);
      return;
    }

    try {
      const venuesData = JSON.parse(this.el.dataset.venues);
      const centerData = JSON.parse(this.el.dataset.center);

      // Initialize map
      this.map = new google.maps.Map(this.el, {
        center: centerData,
        zoom: 12,
        mapTypeControl: true,
        streetViewControl: true,
        fullscreenControl: true,
        zoomControl: true,
        styles: this.getMapStyles()
      });

      // Create markers
      this.markers = venuesData.map(venue => {
        const marker = new google.maps.Marker({
          position: { lat: venue.latitude, lng: venue.longitude },
          map: this.map,
          title: venue.name,
          optimized: true
        });

        // Create info window
        const infoWindow = new google.maps.InfoWindow({
          content: this.createInfoWindowContent(venue)
        });

        // Add click listener
        marker.addListener('click', () => {
          // Close all other info windows
          if (this.currentInfoWindow) {
            this.currentInfoWindow.close();
          }
          infoWindow.open(this.map, marker);
          this.currentInfoWindow = infoWindow;
        });

        return marker;
      });

      // Add marker clustering if we have many markers
      if (venuesData.length > 10 && window.markerClusterer) {
        this.markerClusterer = new markerClusterer.MarkerClusterer({
          map: this.map,
          markers: this.markers,
          algorithm: new markerClusterer.SuperClusterAlgorithm({ radius: 100 })
        });
      }

      // Fit bounds to show all markers
      if (venuesData.length > 0) {
        const bounds = new google.maps.LatLngBounds();
        venuesData.forEach(venue => {
          bounds.extend({ lat: venue.latitude, lng: venue.longitude });
        });
        this.map.fitBounds(bounds);

        // Don't zoom in too much if only one marker
        if (venuesData.length === 1) {
          this.map.setZoom(14);
        }
      }

    } catch (error) {
      console.error("Error initializing venues map:", error);
      this.showError();
    }
  },

  createInfoWindowContent(venue) {
    const eventsText = venue.events_count > 0
      ? `<span class="text-blue-600 text-sm">${venue.events_count} ${venue.events_count === 1 ? 'event' : 'events'}</span>`
      : '<span class="text-gray-500 text-sm">No upcoming events</span>';

    return `
      <div class="p-2 max-w-xs">
        <h3 class="font-semibold text-gray-900 mb-1">${venue.name}</h3>
        ${venue.address ? `<p class="text-sm text-gray-600 mb-2">${venue.address}</p>` : ''}
        <div class="mb-2">${eventsText}</div>
        <a
          href="${venue.url}"
          class="inline-block px-3 py-1 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 transition-colors"
          data-phx-link="redirect"
          data-phx-link-state="push"
        >
          View Details
        </a>
      </div>
    `;
  },

  getMapStyles() {
    // Return custom map styles based on theme
    // For now, return default styles
    // TODO: Add dark mode detection and appropriate styles
    return [];
  },

  showError() {
    this.el.innerHTML = `
      <div class="flex items-center justify-center h-full bg-red-50">
        <div class="text-center">
          <svg class="w-8 h-8 text-red-600 mx-auto mb-2" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
          </svg>
          <p class="text-red-600">Failed to load map</p>
        </div>
      </div>
    `;
  },

  destroyed() {
    // Clean up
    if (this.markers) {
      this.markers.forEach(marker => marker.setMap(null));
    }
    if (this.markerClusterer) {
      this.markerClusterer.clearMarkers();
    }
    if (this.currentInfoWindow) {
      this.currentInfoWindow.close();
    }
  }
};

export default VenuesMap;
