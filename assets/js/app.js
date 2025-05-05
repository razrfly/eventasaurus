// Import dependencies
import "phoenix_html";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import topbar from "../vendor/topbar";

// Define LiveView hooks here
let Hooks = {};

// Input Sync Hook to ensure hidden fields stay in sync with LiveView state
Hooks.InputSync = {
  mounted() {
    // This ensures the hidden input values are updated when the form is submitted
    this.handleEvent("sync_inputs", ({ values }) => {
      if (values && values[this.el.id]) {
        this.el.value = values[this.el.id];
      }
    });
  }
};

// Google Places Autocomplete Hook - DIRECT BASIC IMPLEMENTATION
Hooks.GooglePlacesAutocomplete = {
  mounted() {
    console.log("GooglePlacesAutocomplete hook mounted");
    const input = this.el;
    
    // Check if Google Maps is available
    if (typeof google === 'undefined' || !google.maps || !google.maps.places) {
      console.log("Google Maps not yet loaded, will initialize when ready");
      
      // Add a global callback for when Google Maps loads
      window.initGooglePlaces = () => {
        this.initAutocomplete(input);
      };
      
      return;
    }
    
    // If Google Maps is already loaded, initialize autocomplete
    this.initAutocomplete(input);
  },
  
  initAutocomplete(input) {
    try {
      console.log("Initializing Google Places Autocomplete");
      
      // Create the autocomplete object
      const autocomplete = new google.maps.places.Autocomplete(input);
      
      // Add a listener for when a place is selected
      autocomplete.addListener('place_changed', () => {
        const place = autocomplete.getPlace();
        
        if (!place.geometry) {
          console.error("No place geometry");
          return;
        }
        
        console.log("Place selected:", place);
        
        // Update form fields
        document.getElementById('venue-name').value = place.name || '';
        document.getElementById('venue-address').value = place.formatted_address || '';
        
        // Update lat/lng
        if (place.geometry.location) {
          document.getElementById('venue-lat').value = place.geometry.location.lat();
          document.getElementById('venue-lng').value = place.geometry.location.lng();
        }
        
        // Get address components
        if (place.address_components) {
          const city = this.getAddressComponent(place, 'locality');
          const state = this.getAddressComponent(place, 'administrative_area_level_1');
          const country = this.getAddressComponent(place, 'country');
          
          document.getElementById('venue-city').value = city;
          document.getElementById('venue-state').value = state;
          document.getElementById('venue-country').value = country;
        }
        
        // Dispatch change events for LiveView
        const dispatchEvent = (id) => {
          const el = document.getElementById(id);
          if (el) {
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
          }
        };
        
        // Dispatch events for all fields
        ['venue-name', 'venue-address', 'venue-city', 'venue-state', 
         'venue-country', 'venue-lat', 'venue-lng'].forEach(dispatchEvent);
        
        // Notify LiveView about the selection
        this.pushEvent('venue_selected', {
          name: place.name || '',
          address: place.formatted_address || '',
          city: this.getAddressComponent(place, 'locality'),
          state: this.getAddressComponent(place, 'administrative_area_level_1'),
          country: this.getAddressComponent(place, 'country'),
          latitude: place.geometry.location.lat(),
          longitude: place.geometry.location.lng()
        });
      });
      
      console.log("Google Places Autocomplete initialized successfully");
    } catch (error) {
      console.error("Error initializing Google Places Autocomplete:", error);
    }
  },
  
  // Helper to extract address components
  getAddressComponent(place, type) {
    const component = place.address_components.find(comp => comp.types.includes(type));
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