/**
 * MapboxVenuesMap Hook
 *
 * Renders an interactive Mapbox GL JS map showing multiple venue markers with clustering.
 * Features:
 * - Marker clustering for performance
 * - Popups with venue details
 * - Responsive design
 * - Dark mode support
 */

const MapboxVenuesMap = {
  mounted() {
    this.initMap();
  },

  initMap() {
    // Wait for Mapbox GL to be loaded
    if (!window.mapboxgl) {
      console.warn("Mapbox GL JS not loaded, retrying...");
      setTimeout(() => this.initMap(), 100);
      return;
    }

    // Check for access token
    if (!window.MAPBOX_ACCESS_TOKEN) {
      console.error("Mapbox access token not configured");
      this.showError("Map configuration error");
      return;
    }

    try {
      const venuesData = JSON.parse(this.el.dataset.venues);
      const centerData = JSON.parse(this.el.dataset.center);

      // Set access token
      mapboxgl.accessToken = window.MAPBOX_ACCESS_TOKEN;

      // Initialize map
      this.map = new mapboxgl.Map({
        container: this.el,
        style: 'mapbox://styles/mapbox/streets-v12',
        center: [centerData.lng, centerData.lat],
        zoom: 12
      });

      // Add navigation controls
      this.map.addControl(new mapboxgl.NavigationControl());

      // Add fullscreen control
      this.map.addControl(new mapboxgl.FullscreenControl());

      // Wait for map to load before adding markers
      this.map.on('load', () => {
        this.addVenueMarkers(venuesData);

        // Fit bounds to show all markers
        if (venuesData.length > 0) {
          const bounds = new mapboxgl.LngLatBounds();
          venuesData.forEach(venue => {
            bounds.extend([venue.longitude, venue.latitude]);
          });
          this.map.fitBounds(bounds, {
            padding: 50,
            maxZoom: venuesData.length === 1 ? 14 : 15
          });
        }
      });

    } catch (error) {
      console.error("Error initializing Mapbox venues map:", error);
      this.showError("Failed to load map");
    }
  },

  addVenueMarkers(venues) {
    // If we have many venues, use clustering
    if (venues.length > 10) {
      this.addClusteredMarkers(venues);
    } else {
      this.addSimpleMarkers(venues);
    }
  },

  addSimpleMarkers(venues) {
    // Create simple markers without clustering
    this.markers = venues.map(venue => {
      // Create marker
      const marker = new mapboxgl.Marker()
        .setLngLat([venue.longitude, venue.latitude])
        .setPopup(new mapboxgl.Popup({ offset: 25 })
          .setHTML(this.createPopupContent(venue)))
        .addTo(this.map);

      return marker;
    });
  },

  addClusteredMarkers(venues) {
    // Create GeoJSON data for clustering
    const geojsonData = {
      type: 'FeatureCollection',
      features: venues.map(venue => ({
        type: 'Feature',
        properties: venue,
        geometry: {
          type: 'Point',
          coordinates: [venue.longitude, venue.latitude]
        }
      }))
    };

    // Add source
    this.map.addSource('venues', {
      type: 'geojson',
      data: geojsonData,
      cluster: true,
      clusterMaxZoom: 14,
      clusterRadius: 50
    });

    // Add cluster circles layer
    this.map.addLayer({
      id: 'clusters',
      type: 'circle',
      source: 'venues',
      filter: ['has', 'point_count'],
      paint: {
        'circle-color': [
          'step',
          ['get', 'point_count'],
          '#2563eb',  // blue-600
          10,
          '#1d4ed8', // blue-700
          30,
          '#1e40af'  // blue-800
        ],
        'circle-radius': [
          'step',
          ['get', 'point_count'],
          20,
          10,
          30,
          30,
          40
        ]
      }
    });

    // Add cluster count labels
    this.map.addLayer({
      id: 'cluster-count',
      type: 'symbol',
      source: 'venues',
      filter: ['has', 'point_count'],
      layout: {
        'text-field': '{point_count_abbreviated}',
        'text-font': ['DIN Offc Pro Medium', 'Arial Unicode MS Bold'],
        'text-size': 12
      },
      paint: {
        'text-color': '#ffffff'
      }
    });

    // Add unclustered point layer
    this.map.addLayer({
      id: 'unclustered-point',
      type: 'circle',
      source: 'venues',
      filter: ['!', ['has', 'point_count']],
      paint: {
        'circle-color': '#2563eb',
        'circle-radius': 8,
        'circle-stroke-width': 2,
        'circle-stroke-color': '#fff'
      }
    });

    // Click handler for clusters - zoom in
    this.map.on('click', 'clusters', (e) => {
      const features = this.map.queryRenderedFeatures(e.point, {
        layers: ['clusters']
      });
      const clusterId = features[0].properties.cluster_id;
      this.map.getSource('venues').getClusterExpansionZoom(
        clusterId,
        (err, zoom) => {
          if (err) return;

          this.map.easeTo({
            center: features[0].geometry.coordinates,
            zoom: zoom
          });
        }
      );
    });

    // Click handler for unclustered points - show popup
    this.map.on('click', 'unclustered-point', (e) => {
      const coordinates = e.features[0].geometry.coordinates.slice();
      const venue = e.features[0].properties;

      // Ensure popup appears over the point
      while (Math.abs(e.lngLat.lng - coordinates[0]) > 180) {
        coordinates[0] += e.lngLat.lng > coordinates[0] ? 360 : -360;
      }

      new mapboxgl.Popup()
        .setLngLat(coordinates)
        .setHTML(this.createPopupContent(venue))
        .addTo(this.map);
    });

    // Change cursor on hover
    this.map.on('mouseenter', 'clusters', () => {
      this.map.getCanvas().style.cursor = 'pointer';
    });
    this.map.on('mouseleave', 'clusters', () => {
      this.map.getCanvas().style.cursor = '';
    });
    this.map.on('mouseenter', 'unclustered-point', () => {
      this.map.getCanvas().style.cursor = 'pointer';
    });
    this.map.on('mouseleave', 'unclustered-point', () => {
      this.map.getCanvas().style.cursor = '';
    });
  },

  createPopupContent(venue) {
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

  showError(message) {
    this.el.innerHTML = `
      <div class="flex items-center justify-center h-full bg-red-50">
        <div class="text-center">
          <svg class="w-8 h-8 text-red-600 mx-auto mb-2" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
          </svg>
          <p class="text-red-600">${message}</p>
        </div>
      </div>
    `;
  },

  destroyed() {
    // Clean up
    if (this.markers) {
      this.markers.forEach(marker => marker.remove());
    }
    if (this.map) {
      this.map.remove();
    }
  }
};

export default MapboxVenuesMap;
