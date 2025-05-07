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

// Time Options Hook - Handles the time dropdown and combining date/time values
Hooks.TimeOptionsHook = {
  mounted() {
    console.log("TimeOptionsHook mounted");
    
    // Get references to all related fields
    this.startTimeSelect = document.getElementById("event_start_time");
    this.endTimeSelect = document.getElementById("event_ends_time");
    this.startDateInput = document.getElementById("event_start_date");
    this.endDateInput = document.getElementById("event_ends_date");
    this.startAtHidden = document.getElementById("event_start_at");
    this.endsAtHidden = document.getElementById("event_ends_at");
    
    // Set current time as default (rounded to nearest 30 min)
    this.setDefaultTime();
    
    // Add event listeners for form submission
    const form = this.el.closest("form");
    if (form) {
      form.addEventListener("submit", this.handleSubmit.bind(this));
    }
    
    // Add event listeners for date/time changes
    if (this.startDateInput) {
      this.startDateInput.addEventListener("change", (e) => {
        // When start date changes, update end date to match
        if (this.endDateInput) {
          this.endDateInput.value = e.target.value;
        }
        this.updateCombinedDateTime();
      });
    }
    
    if (this.startTimeSelect) {
      this.startTimeSelect.addEventListener("change", (e) => {
        // When start time changes, update end time to be 1 hour later
        if (this.endTimeSelect) {
          const selectedTime = e.target.value;
          if (selectedTime) {
            const [hours, minutes] = selectedTime.split(':').map(Number);
            // Add 1 hour
            const endHours = (hours + 1) % 24;
            const endTimeValue = `${endHours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}`;
            this.endTimeSelect.value = endTimeValue;
          }
        }
        this.updateCombinedDateTime();
      });
    }
    
    if (this.endDateInput) {
      this.endDateInput.addEventListener("change", this.updateCombinedDateTime.bind(this));
    }
    
    if (this.endTimeSelect) {
      this.endTimeSelect.addEventListener("change", this.updateCombinedDateTime.bind(this));
    }
    
    // Set initial values if editing an existing event
    this.initializeFromExistingValues();
  },
  
  setDefaultTime() {
    if (!this.startTimeSelect) return;
    
    // Get current time
    const now = new Date();
    
    // Round to nearest 30 minutes
    const minutes = now.getMinutes();
    const roundedMinutes = minutes < 30 ? 30 : 0;
    const hours = minutes < 30 ? now.getHours() : (now.getHours() + 1) % 24;
    
    // Format the time value (HH:MM)
    const timeValue = `${hours.toString().padStart(2, '0')}:${roundedMinutes.toString().padStart(2, '0')}`;
    
    // Set the selected time
    this.startTimeSelect.value = timeValue;
    
    // Default end time to 1 hour after start time
    if (this.endTimeSelect) {
      const endHours = (hours + 1) % 24;
      const endTimeValue = `${endHours.toString().padStart(2, '0')}:${roundedMinutes.toString().padStart(2, '0')}`;
      this.endTimeSelect.value = endTimeValue;
    }
    
    // Set end date to same as start date initially
    if (this.startDateInput && this.startDateInput.value && this.endDateInput) {
      this.endDateInput.value = this.startDateInput.value;
    }
    
    // Update combined datetime fields
    this.updateCombinedDateTime();
  },
  
  handleSubmit(event) {
    // Combine date and time fields
    this.updateCombinedDateTime();
  },
  
  updateCombinedDateTime() {
    // Combine start date and time
    if (this.startDateInput && this.startDateInput.value && 
        this.startTimeSelect && this.startTimeSelect.value && 
        this.startAtHidden) {
      const startDate = this.startDateInput.value;
      const startTime = this.startTimeSelect.value;
      const startDateTime = `${startDate}T${startTime}`;
      this.startAtHidden.value = startDateTime;
    }
    
    // Combine end date and time
    if (this.endDateInput && this.endDateInput.value && 
        this.endTimeSelect && this.endTimeSelect.value && 
        this.endsAtHidden) {
      const endDate = this.endDateInput.value;
      const endTime = this.endTimeSelect.value;
      const endDateTime = `${endDate}T${endTime}`;
      this.endsAtHidden.value = endDateTime;
    }
  },
  
  initializeFromExistingValues() {
    // Check if we're editing an existing event
    const initialStartAt = document.querySelector('input[name="event[start_at]"][value]');
    const initialEndsAt = document.querySelector('input[name="event[ends_at]"][value]');
    
    if (initialStartAt && initialStartAt.value) {
      // Parse the datetime and populate date and time fields
      const startDateTime = new Date(initialStartAt.value);
      if (!isNaN(startDateTime.getTime()) && this.startDateInput && this.startTimeSelect) {
        // Format date as YYYY-MM-DD
        const startDate = startDateTime.toISOString().split('T')[0];
        this.startDateInput.value = startDate;
        
        // Format time as HH:MM
        const hours = startDateTime.getHours().toString().padStart(2, '0');
        const minutes = startDateTime.getMinutes().toString().padStart(2, '0');
        this.startTimeSelect.value = `${hours}:${minutes}`;
      }
    }
    
    if (initialEndsAt && initialEndsAt.value) {
      // Parse the datetime and populate date and time fields
      const endsDateTime = new Date(initialEndsAt.value);
      if (!isNaN(endsDateTime.getTime()) && this.endDateInput && this.endTimeSelect) {
        // Format date as YYYY-MM-DD
        const endDate = endsDateTime.toISOString().split('T')[0];
        this.endDateInput.value = endDate;
        
        // Format time as HH:MM
        const hours = endsDateTime.getHours().toString().padStart(2, '0');
        const minutes = endsDateTime.getMinutes().toString().padStart(2, '0');
        this.endTimeSelect.value = `${hours}:${minutes}`;
      }
    } else if (this.startDateInput && this.startDateInput.value && this.endDateInput) {
      // If no end date/time, set end date to match start date
      this.endDateInput.value = this.startDateInput.value;
      
      // And set end time to an hour after start time if possible
      if (this.startTimeSelect && this.startTimeSelect.value && this.endTimeSelect) {
        const [hours, minutes] = this.startTimeSelect.value.split(':').map(Number);
        const endHours = (hours + 1) % 24;
        const endTimeValue = `${endHours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}`;
        this.endTimeSelect.value = endTimeValue;
      }
    }
    
    // Update the combined fields
    this.updateCombinedDateTime();
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
      setTimeout(() => this.initClassicAutocomplete(), 100); // Use classic API only for now
    } else {
      console.log("Google Maps not yet loaded, will initialize when ready");
      // Add a global callback for when Google Maps loads
      window.initGooglePlaces = () => {
        if (this.mounted) {
          setTimeout(() => this.initClassicAutocomplete(), 100);
        }
      };
    }
  },
  
  destroyed() {
    // Mark as unmounted to prevent async operations after component is gone
    this.mounted = false;
    console.log("GooglePlacesAutocomplete hook destroyed");
  },
  
  // Legacy approach using classic Autocomplete - but it works reliably
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
        
        console.group("Place selection process");
        const place = autocomplete.getPlace();
        console.log("Place selected:", place);
        
        if (!place.geometry) {
          console.error("No place geometry received");
          console.groupEnd();
          return;
        }
        
        // Get place details
        const venueName = place.name || '';
        const venueAddress = place.formatted_address || '';
        let city = '', state = '', country = '';
        
        // Get address components
        if (place.address_components) {
          console.log("Processing address components:", place.address_components);
          for (const component of place.address_components) {
            if (component.types.includes('locality')) {
              city = component.long_name;
              console.log(`Found city: ${city}`);
            } else if (component.types.includes('administrative_area_level_1')) {
              state = component.long_name;
              console.log(`Found state: ${state}`);
            } else if (component.types.includes('country')) {
              country = component.long_name;
              console.log(`Found country: ${country}`);
            }
          }
        }
        
        // Get coordinates
        let lat = null, lng = null;
        if (place.geometry && place.geometry.location) {
          lat = place.geometry.location.lat();
          lng = place.geometry.location.lng();
          console.log(`Coordinates: ${lat}, ${lng}`);
        }
        
        // Map field IDs to expected form data keys
        const fieldMappings = {
          'venue_name': venueName,
          'venue_address': venueAddress,
          'venue_city': city,
          'venue_state': state,
          'venue_country': country,
          'venue_latitude': lat,
          'venue_longitude': lng
        };
        
        // Direct DOM updates for each field
        console.log("Updating DOM fields...");
        Object.entries(fieldMappings).forEach(([key, value]) => {
          if (value !== null && value !== undefined) {
            this.directUpdateField(key, value);
          }
        });
        
        // Prepare data for LiveView
        const venueData = {
          name: venueName,
          address: venueAddress,
          city: city,
          state: state,
          country: country,
          latitude: lat,
          longitude: lng
        };
        
        // Send to LiveView
        console.log("Pushing venue data to LiveView:", venueData);
        this.pushEvent('venue_selected', venueData);
        
        // Log all form fields for debugging
        this.logFormFieldValues();
        console.groupEnd();
      });
      
      console.log("Classic Autocomplete initialized");
    } catch (error) {
      console.error("Error in Autocomplete initialization:", error);
    }
  },
  
  // Direct DOM update to ensure form fields are updated
  directUpdateField(id, value) {
    if (!this.mounted) return;
    
    console.group(`Updating field ${id}`);
    
    // Look for the element using direct ID
    let field = document.getElementById(id);
    console.log(`Field by ID ${id}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    
    // If not found, try with venue_ instead of venue-
    if (!field) {
      const altId = id.replace('venue-', 'venue_');
      field = document.getElementById(altId);
      console.log(`Field by ID ${altId}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    }
    
    // If still not found, try the event[] prefixed version (for Phoenix forms)
    if (!field) {
      const selector = `[name="event[${id.replace('venue-', 'venue_')}]"]`;
      field = document.querySelector(selector);
      console.log(`Field by selector ${selector}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    }
    
    if (field) {
      // Set the value directly
      const oldValue = field.value;
      field.value = value || '';
      
      // Log the update
      console.log(`Updated value: "${oldValue}" -> "${value}"`);
      
      // Trigger input and change events to ensure form controllers detect the change
      field.dispatchEvent(new Event('input', {bubbles: true}));
      field.dispatchEvent(new Event('change', {bubbles: true}));
      console.log("Events dispatched: input, change");
    } else {
      console.error(`Field ${id} not found in DOM`);
    }
    
    console.groupEnd();
  },
  
  // Debug helper to log all form field values
  logFormFieldValues() {
    console.group("Current form field values:");
    
    // Check all possible field name combinations
    const fieldKeys = [
      'venue_name', 'venue_address', 'venue_city', 'venue_state', 
      'venue_country', 'venue_latitude', 'venue_longitude'
    ];
    
    fieldKeys.forEach(key => {
      // Check direct field ID
      let val = null;
      let foundElement = null;
      
      // Try by ID first
      const directEl = document.getElementById(key);
      if (directEl) {
        foundElement = directEl;
        val = directEl.value;
      } 
      
      // Try with dashes instead of underscores
      if (!foundElement) {
        const dashKey = key.replace('_', '-');
        const dashEl = document.getElementById(dashKey);
        if (dashEl) {
          foundElement = dashEl;
          val = dashEl.value;
        }
      }
      
      // Try the event[] prefixed version
      if (!foundElement) {
        const selector = `[name="event[${key}]"]`;
        const formEl = document.querySelector(selector);
        if (formEl) {
          foundElement = formEl;
          val = formEl.value;
        }
      }
      
      console.log(`${key}: ${val !== null ? val : 'FIELD NOT FOUND'} ${foundElement ? '(✓)' : '(✗)'}`);
    });
    
    console.groupEnd();
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