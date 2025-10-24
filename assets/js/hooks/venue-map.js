/**
 * VenueMap Hook
 *
 * Initializes and manages Leaflet map for venue location display.
 *
 * Features:
 * - Interactive map with OpenStreetMap tiles
 * - Marker with venue name popup
 * - Centered on venue coordinates
 * - Street-level zoom (15)
 */

import L from "leaflet";

// Import Leaflet CSS - required for proper map display
import "leaflet/dist/leaflet.css";

// Fix Leaflet's default icon paths (required when using webpack/esbuild)
import icon from "leaflet/dist/images/marker-icon.png";
import iconShadow from "leaflet/dist/images/marker-shadow.png";
import iconRetina from "leaflet/dist/images/marker-icon-2x.png";

let DefaultIcon = L.icon({
  iconUrl: icon,
  iconRetinaUrl: iconRetina,
  shadowUrl: iconShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41]
});

L.Marker.prototype.options.icon = DefaultIcon;

export const VenueMap = {
  mounted() {
    const latitude = parseFloat(this.el.dataset.latitude);
    const longitude = parseFloat(this.el.dataset.longitude);
    const venueName = this.el.dataset.venueName;

    // Validate coordinates
    if (isNaN(latitude) || isNaN(longitude)) {
      console.error("Invalid coordinates for venue map");
      return;
    }

    // Initialize map
    this.map = L.map(this.el, {
      center: [latitude, longitude],
      zoom: 15,
      scrollWheelZoom: false, // Prevent accidental zooming while scrolling page
    });

    // Add OpenStreetMap tile layer
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(this.map);

    // Add marker with popup
    const marker = L.marker([latitude, longitude]).addTo(this.map);

    if (venueName) {
      marker.bindPopup(`<strong>${venueName}</strong>`).openPopup();
    }

    // Allow zoom on click
    this.map.on("click", () => {
      this.map.scrollWheelZoom.enable();
    });

    // Disable zoom when mouse leaves map
    this.map.on("mouseout", () => {
      this.map.scrollWheelZoom.disable();
    });
  },

  destroyed() {
    // Clean up map instance when component is destroyed
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  },
};

export default VenueMap;
