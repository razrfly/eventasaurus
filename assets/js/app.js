// Import dependencies
import "phoenix_html";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import topbar from "../vendor/topbar";

// Define LiveView hooks here
let Hooks = {};

// Google Places Autocomplete Hook
Hooks.GooglePlacesAutocomplete = {
  mounted() {
    console.log("GooglePlacesAutocomplete hook mounted");
    this.inputEl = this.el;
    
    // Initialize immediately if API is already loaded
    if (window.google && window.google.maps && window.google.maps.places) {
      console.log("Google Maps API already available");
      this.initAutocomplete();
      return;
    }
    
    // Wait for API to load
    this.attempts = 0;
    this.maxAttempts = 40; // 20 seconds
    this.checkInterval = 500; // ms
    
    this.waitForAPI();
  },
  
  destroyed() {
    if (this.checkTimer) {
      clearInterval(this.checkTimer);
    }
  },
  
  waitForAPI() {
    this.checkTimer = setInterval(() => {
      this.attempts++;
      // Check if Google Maps API is loaded
      if (window.google && window.google.maps && window.google.maps.places) {
        console.log(`Google Maps API loaded after ${this.attempts} attempts`);
        clearInterval(this.checkTimer);
        this.initAutocomplete();
        return;
      }
      
      // Log attempt progress
      if (this.attempts % 5 === 0) {
        console.log(`Waiting for Google Maps API... (${this.attempts}/${this.maxAttempts})`);
      }
      
      // Give up after max attempts
      if (this.attempts >= this.maxAttempts) {
        console.error("Google Maps API failed to load after multiple attempts");
        clearInterval(this.checkTimer);
      }
    }, this.checkInterval);
  },
  
  initAutocomplete() {
    try {
      // Create autocomplete instance
      const autocomplete = new google.maps.places.Autocomplete(this.inputEl, {
        types: ['establishment', 'geocode'],
        fields: ['name', 'formatted_address', 'address_components', 'geometry', 'place_id']
      });
      
      // Handle place selection
      autocomplete.addListener('place_changed', () => {
        const place = autocomplete.getPlace();
        
        if (!place.geometry) {
          console.log("Place selected without geometry data");
          return;
        }
        
        console.log("Place selected:", place.name);
        
        // Update hidden fields
        this.updateHiddenField('venue-name', place.name || '');
        this.updateHiddenField('venue-address', place.formatted_address || '');
        
        // Process address components
        if (place.address_components && place.address_components.length > 0) {
          this.updateHiddenField('venue-city', this.getAddressComponent(place, 'locality'));
          this.updateHiddenField('venue-state', this.getAddressComponent(place, 'administrative_area_level_1'));
          this.updateHiddenField('venue-country', this.getAddressComponent(place, 'country'));
        }
        
        // Process coordinates
        if (place.geometry && place.geometry.location) {
          this.updateHiddenField('venue-lat', place.geometry.location.lat());
          this.updateHiddenField('venue-lng', place.geometry.location.lng());
        }
        
        // Send data to LiveView
        this.pushEvent('place_selected', {
          details: {
            name: place.name,
            formatted_address: place.formatted_address,
            address_components: place.address_components,
            geometry: {
              location: {
                lat: place.geometry.location.lat(),
                lng: place.geometry.location.lng()
              }
            }
          }
        });
      });
      
      console.log("Google Places Autocomplete initialized successfully");
    } catch (error) {
      console.error("Failed to initialize Places Autocomplete:", error);
    }
  },
  
  // Helper to update hidden form fields
  updateHiddenField(id, value) {
    const field = document.getElementById(id);
    if (field) {
      field.value = value;
    }
  },
  
  // Helper to extract address components
  getAddressComponent(place, type) {
    const component = place.address_components.find(c => c.types.includes(type));
    return component ? component.long_name : '';
  }
};

// Set up LiveView
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
});

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"});
window.addEventListener("phx:page-loading-start", info => topbar.show());
window.addEventListener("phx:page-loading-stop", info => topbar.hide());

// Connect if there are any LiveViews on the page
liveSocket.connect();

// Expose liveSocket on window for web console debug logs and latency simulation
window.liveSocket = liveSocket;

// Handle Supabase Auth Callback (from email confirmation links)
document.addEventListener("DOMContentLoaded", function() {
  // Check if we have an access token in the URL hash
  if (window.location.hash && window.location.hash.includes("access_token")) {
    // Parse hash params
    const hashParams = window.location.hash.substring(1).split("&").reduce((acc, pair) => {
      const [key, value] = pair.split("=");
      acc[key] = decodeURIComponent(value);
      return acc;
    }, {});

    // Check for required tokens
    if (hashParams.access_token && hashParams.refresh_token) {
      // Create a form to post the tokens
      const form = document.createElement("form");
      form.method = "POST";
      form.action = "/auth/callback";
      form.style.display = "none";

      // Add CSRF token
      const csrfInput = document.createElement("input");
      csrfInput.type = "hidden";
      csrfInput.name = "_csrf_token";
      csrfInput.value = csrfToken;
      form.appendChild(csrfInput);

      // Add the tokens
      const accessTokenInput = document.createElement("input");
      accessTokenInput.type = "hidden";
      accessTokenInput.name = "access_token";
      accessTokenInput.value = hashParams.access_token;
      form.appendChild(accessTokenInput);

      const refreshTokenInput = document.createElement("input");
      refreshTokenInput.type = "hidden";
      refreshTokenInput.name = "refresh_token";
      refreshTokenInput.value = hashParams.refresh_token;
      form.appendChild(refreshTokenInput);

      // Add callback type
      const typeInput = document.createElement("input");
      typeInput.type = "hidden";
      typeInput.name = "type";
      typeInput.value = hashParams.type || "unknown";
      form.appendChild(typeInput);

      // Submit form to handle tokens server-side
      document.body.appendChild(form);
      form.submit();

      // Remove hash from URL (to prevent tokens from staying in browser history)
      window.history.replaceState(null, null, window.location.pathname);
    }
  }
}); 