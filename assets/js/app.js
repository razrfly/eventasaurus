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
    
    // Check if all required elements are found
    if (!this.startTimeSelect || !this.endTimeSelect || !this.startDateInput || 
        !this.endDateInput || !this.startAtHidden || !this.endsAtHidden) {
      console.error("TimeOptionsHook: Not all required elements found", {
        startTime: !!this.startTimeSelect,
        endTime: !!this.endTimeSelect,
        startDate: !!this.startDateInput,
        endDate: !!this.endDateInput,
        startAt: !!this.startAtHidden,
        endsAt: !!this.endsAtHidden
      });
      return; // Don't proceed if elements are missing
    }

    // Set default times if not already set
    this.setDefaultTime();
    
    // Add event listeners for changes to automatically update related fields
    this.addEventListeners();
    
    // Perform initial combination of date and time values
    this.combineDateTime();
  },

  setDefaultTime() {
    // Only set defaults if the fields don't already have values
    if (!this.startTimeSelect.value) {
      const now = new Date();
      
      // Round to nearest 30 minutes
      const minutes = now.getMinutes();
      const roundedMinutes = minutes < 30 ? 30 : 0;
      const hoursAdjustment = minutes < 30 ? 0 : 1;
      
      now.setMinutes(roundedMinutes);
      if (hoursAdjustment === 1) {
        now.setHours(now.getHours() + hoursAdjustment);
      }
      
      // Format the time for the select field (24-hour format)
      const formattedStartTime = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
      
      // Set start time
      this.setTimeValue(this.startTimeSelect, formattedStartTime);
      
      // Calculate end time (1 hour later)
      const endTime = new Date(now);
      endTime.setHours(endTime.getHours() + 1);
      const formattedEndTime = `${String(endTime.getHours()).padStart(2, '0')}:${String(endTime.getMinutes()).padStart(2, '0')}`;
      
      // Set end time
      this.setTimeValue(this.endTimeSelect, formattedEndTime);
    }
  },
  
  setTimeValue(selectElement, timeValue) {
    if (!selectElement) return;
    
    // Find the option with this value
    let found = false;
    for (let i = 0; i < selectElement.options.length; i++) {
      if (selectElement.options[i].value === timeValue) {
        selectElement.selectedIndex = i;
        found = true;
        break;
      }
    }
    
    // If exact match not found, find the closest time
    if (!found && selectElement.options.length > 0) {
      let closestIndex = 1; // Skip the empty option
      let closestDiff = Infinity;
      
      const targetMinutes = this.timeToMinutes(timeValue);
      
      for (let i = 1; i < selectElement.options.length; i++) {
        const optionMinutes = this.timeToMinutes(selectElement.options[i].value);
        const diff = Math.abs(optionMinutes - targetMinutes);
        
        if (diff < closestDiff) {
          closestDiff = diff;
          closestIndex = i;
        }
      }
      
      selectElement.selectedIndex = closestIndex;
    }
    
    // Dispatch change event to notify other listeners
    selectElement.dispatchEvent(new Event('change', { bubbles: true }));
  },
  
  timeToMinutes(timeString) {
    if (!timeString) return 0;
    
    try {
      const [hours, minutes] = timeString.split(':').map(Number);
      return hours * 60 + minutes;
    } catch (err) {
      console.error("Error converting time to minutes:", err);
      return 0;
    }
  },
  
  addEventListeners() {
    // For start date, listen to both input and change events
    const syncStartToEndDate = () => {
      if (this.startDateInput && this.endDateInput) {
        this.endDateInput.value = this.startDateInput.value;
        
        // Manually trigger change event on end date
        this.endDateInput.dispatchEvent(new Event('change', { bubbles: true }));
        this.combineDateTime();
      }
    };
    
    this.startDateInput.addEventListener('change', syncStartToEndDate);
    this.startDateInput.addEventListener('input', syncStartToEndDate);
    
    // When start time changes, update end time to be 1 hour later
    this.startTimeSelect.addEventListener('change', () => {
      if (this.startTimeSelect.value && this.endTimeSelect) {
        const startMinutes = this.timeToMinutes(this.startTimeSelect.value);
        const endMinutes = startMinutes + 60; // Add 1 hour in minutes
        
        const hours = Math.floor(endMinutes / 60) % 24;
        const minutes = endMinutes % 60;
        
        const formattedEndTime = `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
        this.setTimeValue(this.endTimeSelect, formattedEndTime);
      }
      this.combineDateTime();
    });
    
    // Update hidden fields when any date/time field changes
    this.endDateInput.addEventListener('change', () => this.combineDateTime());
    this.endTimeSelect.addEventListener('change', () => this.combineDateTime());
  },
  
  combineDateTime() {
    // Combine start date and time
    if (this.startDateInput && this.startDateInput.value && 
        this.startTimeSelect && this.startTimeSelect.value &&
        this.startAtHidden) {
      this.startAtHidden.value = `${this.startDateInput.value}T${this.startTimeSelect.value}:00`;
    }
    
    // Combine end date and time
    if (this.endDateInput && this.endDateInput.value && 
        this.endTimeSelect && this.endTimeSelect.value &&
        this.endsAtHidden) {
      this.endsAtHidden.value = `${this.endDateInput.value}T${this.endTimeSelect.value}:00`;
    }
    
    console.log('DateTime values combined:', {
      start_at: this.startAtHidden?.value || 'not set',
      ends_at: this.endsAtHidden?.value || 'not set'
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

// New Event Form Hook to handle form submission
Hooks.EventFormHook = {
  mounted() {
    console.log("EventFormHook mounted");
    
    this.el.addEventListener("submit", this.handleSubmit.bind(this));
  },
  
  handleSubmit(event) {
    console.log("Form is being submitted - combining date/time fields");
    
    // Get references to date and time inputs
    const startDateInput = document.getElementById("event_start_date");
    const startTimeInput = document.getElementById("event_start_time");
    const endDateInput = document.getElementById("event_ends_date");
    const endTimeInput = document.getElementById("event_ends_time");
    
    // Get references to hidden datetime fields
    const startAtHidden = document.getElementById("event_start_at");
    const endsAtHidden = document.getElementById("event_ends_at");
    
    // Combine start date and time
    if (startDateInput && startDateInput.value && 
        startTimeInput && startTimeInput.value && 
        startAtHidden) {
      startAtHidden.value = `${startDateInput.value}T${startTimeInput.value}:00`;
      console.log(`Combined start datetime: ${startAtHidden.value}`);
    } else {
      console.error("Missing required start date/time fields:", {
        startDate: startDateInput?.value,
        startTime: startTimeInput?.value
      });
    }
    
    // Combine end date and time
    if (endDateInput && endDateInput.value && 
        endTimeInput && endTimeInput.value && 
        endsAtHidden) {
      endsAtHidden.value = `${endDateInput.value}T${endTimeInput.value}:00`;
      console.log(`Combined end datetime: ${endsAtHidden.value}`);
    } else {
      console.error("Missing required end date/time fields:", {
        endDate: endDateInput?.value,
        endTime: endTimeInput?.value
      });
    }
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