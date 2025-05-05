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

// Google Places Autocomplete Hook
Hooks.GooglePlacesAutocomplete = {
  mounted() {
    console.log("GooglePlacesAutocomplete hook mounted");
    this.inputEl = this.el;
    this.mounted = true;
    
    // Check if Google Maps API is loaded and ready
    if (window.google && google.maps && google.maps.places) {
      console.log("Google Maps already loaded, initializing now");
      setTimeout(() => this.initPlacesWidget(), 100); // Slight delay to ensure DOM is ready
    } else {
      console.log("Google Maps not yet loaded, will initialize when ready");
      // Add a global callback for when Google Maps loads
      window.initGooglePlaces = () => {
        if (this.mounted) {
          setTimeout(() => this.initPlacesWidget(), 100);
        }
      };
    }
  },
  
  destroyed() {
    // Mark as unmounted to prevent async operations after component is gone
    this.mounted = false;
    console.log("GooglePlacesAutocomplete hook destroyed");
  },
  
  initPlacesWidget() {
    if (!this.mounted) return;
    
    try {
      console.log("Initializing Google Places widget");
      
      // Use feature detection to determine which API to use
      if (window.google && google.maps && google.maps.places && google.maps.places.PlaceAutocompleteElement) {
        console.log("Using modern PlaceAutocompleteElement API");
        this.initModernPlacesWidget();
      } else {
        console.log("Falling back to classic Autocomplete API");
        this.initClassicAutocomplete();
      }
    } catch (error) {
      console.error("Error initializing Google Places widget:", error);
    }
  },
  
  // Modern approach using PlaceAutocompleteElement
  initModernPlacesWidget() {
    if (!this.mounted) return;
    
    try {
      // Create a container for the new element
      const container = document.createElement('div');
      container.className = 'place-autocomplete-container';
      container.style.width = '100%';
      
      // Insert the new container before our original input
      this.inputEl.parentNode.insertBefore(container, this.inputEl);
      
      // Hide the original input
      this.inputEl.style.display = 'none';
      
      // Create the widget without any options first (minimal configuration)
      const placesWidget = new google.maps.places.PlaceAutocompleteElement();
      
      // Set only the types option separately if needed
      placesWidget.types = ['establishment', 'geocode'];
      
      // Add the widget to our container
      container.appendChild(placesWidget);
      
      // Style the newly created input with a delay to make sure it's in the DOM
      setTimeout(() => {
        if (!this.mounted) return;
        
        try {
          const newInput = container.querySelector('input');
          if (newInput) {
            newInput.className = this.inputEl.className;
            newInput.placeholder = "Search for a venue or address...";
            
            newInput.style.width = '100%';
            newInput.style.padding = '0.5rem 0.75rem';
            newInput.style.borderRadius = '0.375rem';
            newInput.style.borderWidth = '1px';
            newInput.style.lineHeight = '1.25rem';
          }
          
          const widgetContainer = container.querySelector('.gmp-place-autocomplete');
          if (widgetContainer) {
            widgetContainer.style.width = '100%';
          }
        } catch (e) {
          console.error("Error styling place autocomplete:", e);
        }
      }, 200);
      
      // Add event listener for place selection
      placesWidget.addEventListener('gmp-placeselect', (event) => {
        if (!this.mounted) return;
        
        const place = event.detail?.place;
        console.log("Place selected using PlaceAutocompleteElement:", place);
        
        if (!place) {
          console.error("No place data received");
          return;
        }
        
        this.handleSelectedPlace(place);
      });
      
      console.log("PlaceAutocompleteElement initialized");
    } catch (error) {
      console.error("Error in PlaceAutocompleteElement initialization:", error);
      // Fallback to classic if modern fails
      this.initClassicAutocomplete();
    }
  },
  
  // Handle a selected place (from either API)
  handleSelectedPlace(place) {
    if (!this.mounted) return;
    
    // Extract basic place information
    const venueName = place.displayName?.text || place.name || '';
    const venueAddress = place.formattedAddress || '';
    
    // Prepare data object
    let venueData = {
      name: venueName,
      address: venueAddress
    };
    
    // Get coordinates if available
    if (place.location) {
      venueData.latitude = place.location.lat;
      venueData.longitude = place.location.lng;
      
      // Update hidden fields
      this.updateField('venue-lat', place.location.lat);
      this.updateField('venue-address', venueAddress);
      this.updateField('venue-name', venueName);
    }
    
    // Send the data to the LiveView
    console.log("Pushing venue data to LiveView:", venueData);
    this.pushEvent('venue_selected', venueData);
  },
  
  // Legacy approach using classic Autocomplete
  initClassicAutocomplete() {
    if (!this.mounted) return;
    
    try {
      console.log("Initializing classic Autocomplete API");
      
      // Create the autocomplete object
      const options = {
        types: ['establishment', 'geocode']
      };
      
      const autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
      
      // When a place is selected
      autocomplete.addListener('place_changed', () => {
        if (!this.mounted) return;
        
        const place = autocomplete.getPlace();
        console.log("Place selected using classic Autocomplete:", place);
        
        if (!place.geometry) {
          console.error("No place geometry received");
          return;
        }
        
        // Process the place data
        this.processClassicAutocompletePlace(place);
      });
      
      console.log("Classic Autocomplete initialized");
    } catch (error) {
      console.error("Error in classic Autocomplete initialization:", error);
    }
  },
  
  // Process place from classic Autocomplete
  processClassicAutocompletePlace(place) {
    if (!this.mounted) return;
    
    // Extract place details
    const venueName = place.name || '';
    const venueAddress = place.formatted_address || '';
    let city = '', state = '', country = '';
    
    // Get address components
    if (place.address_components) {
      city = this.getAddressComponent(place, 'locality');
      state = this.getAddressComponent(place, 'administrative_area_level_1');
      country = this.getAddressComponent(place, 'country');
      
      this.updateField('venue-city', city);
      this.updateField('venue-state', state);
      this.updateField('venue-country', country);
    }
    
    // Update form fields
    this.updateField('venue-name', venueName);
    this.updateField('venue-address', venueAddress);
    
    // Get coordinates
    if (place.geometry && place.geometry.location) {
      const lat = place.geometry.location.lat();
      const lng = place.geometry.location.lng();
      
      this.updateField('venue-lat', lat);
      this.updateField('venue-lng', lng);
    }
    
    // Notify LiveView
    this.pushEvent('venue_selected', {
      name: venueName,
      address: venueAddress,
      city: city,
      state: state,
      country: country,
      latitude: place.geometry?.location.lat(),
      longitude: place.geometry?.location.lng()
    });
  },
  
  // Helper to update form fields
  updateField(id, value) {
    if (!this.mounted) return;
    
    const field = document.getElementById(id);
    if (field) {
      field.value = value || '';
      
      // Trigger change events
      field.dispatchEvent(new Event('input', {bubbles: true}));
      field.dispatchEvent(new Event('change', {bubbles: true}));
      
      console.log(`Updated ${id}: ${value}`);
    } else {
      console.error(`Field ${id} not found`);
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