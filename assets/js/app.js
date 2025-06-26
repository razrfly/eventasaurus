// Import dependencies
import "phoenix_html";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import topbar from "../vendor/topbar";

// Define LiveView hooks here
import SupabaseImageUpload from "./supabase_upload";
let Hooks = {};

// SupabaseAuthHandler hook to handle auth tokens from URL fragments
Hooks.SupabaseAuthHandler = {
  mounted() {
    this.handleAuthTokens();
  },

  handleAuthTokens() {
    // Check for auth tokens in URL fragment (Supabase sends tokens this way)
    const hash = window.location.hash;
    if (hash && hash.includes('access_token')) {
      // Parse the URL fragment
      const params = new URLSearchParams(hash.substring(1));
      const accessToken = params.get('access_token');
      const refreshToken = params.get('refresh_token');
      const tokenType = params.get('type');
      const error = params.get('error');
      const errorDescription = params.get('error_description');

      if (error) {
        // Handle auth errors
        console.error('Auth error:', error, errorDescription);
        window.location.href = `/auth/callback?error=${encodeURIComponent(error)}&error_description=${encodeURIComponent(errorDescription || '')}`;
      } else if (accessToken) {
        // Build callback URL with tokens
        let callbackUrl = '/auth/callback?access_token=' + encodeURIComponent(accessToken);
        
        if (refreshToken) {
          callbackUrl += '&refresh_token=' + encodeURIComponent(refreshToken);
        }
        
        if (tokenType) {
          callbackUrl += '&type=' + encodeURIComponent(tokenType);
        }

        // Clear the fragment from URL and redirect to callback
        if (history.replaceState) {
          const url = window.location.href.split('#')[0];
          history.replaceState(null, '', url);
        }
        
        // Redirect to auth callback to process tokens
        window.location.href = callbackUrl;
      }
    }
  }
};

// SetupPathSelector hook to sync radio button states
Hooks.SetupPathSelector = {
  mounted() {
    this.syncRadioButtons();
  },

  updated() {
    this.syncRadioButtons();
  },

  syncRadioButtons() {
    const selectedPath = this.el.dataset.selectedPath;
    const radioButtons = this.el.querySelectorAll('input[type="radio"][name="setup_path"]');
    
    radioButtons.forEach(radio => {
      radio.checked = radio.value === selectedPath;
    });
  }
};

// ImagePicker hook for pushing image_selected event
Hooks.ImagePicker = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const imageData = this.el.dataset.image;
      if (imageData) {
        let data;
        try {
          data = JSON.parse(imageData);
        } catch (err) {
          data = imageData;
        }
        this.pushEvent("image_selected", data);
      }
    });
  }
};

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

// Timezone Detection Hook to detect the user's timezone
Hooks.TimezoneDetectionHook = {
  mounted() {
    if (process.env.NODE_ENV !== 'production') console.log("TimezoneDetectionHook mounted on element:", this.el.id);
    
    // Get the user's timezone using Intl.DateTimeFormat
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (process.env.NODE_ENV !== 'production') console.log("Detected user timezone:", timezone);
    
    // Send the timezone to the server
    if (timezone) {
      this.pushEvent("set_timezone", { timezone });
    }
  }
};

// Pricing Validator Hook - Real-time validation for flexible pricing
Hooks.PricingValidator = {
  mounted() {
    this.validatePricing = this.validatePricing.bind(this);
    
    // Add event listeners for input changes
    this.el.addEventListener('input', this.validatePricing);
    this.el.addEventListener('blur', this.validatePricing);
    
    // Initial validation
    setTimeout(this.validatePricing, 100);
  },

  destroyed() {
    this.el.removeEventListener('input', this.validatePricing);
    this.el.removeEventListener('blur', this.validatePricing);
  },

  validatePricing() {
    const form = this.el.closest('form');
    if (!form) return;

    // Get all pricing inputs
    const basePriceInput = form.querySelector('#base-price-input');
    const minimumPriceInput = form.querySelector('#minimum-price-input');
    const suggestedPriceInput = form.querySelector('#suggested-price-input');

    // Get error elements
    const basePriceError = form.querySelector('#base-price-error');
    const minimumPriceError = form.querySelector('#minimum-price-error');
    const suggestedPriceError = form.querySelector('#suggested-price-error');

    if (!basePriceInput || !basePriceError) return;

    // Parse values
    const basePrice = parseFloat(basePriceInput.value) || 0;
    const minimumPrice = minimumPriceInput ? (parseFloat(minimumPriceInput.value) || 0) : 0;
    const suggestedPrice = suggestedPriceInput ? parseFloat(suggestedPriceInput.value) : null;

    // Clear all errors first
    this.clearError(basePriceError);
    if (minimumPriceError) this.clearError(minimumPriceError);
    if (suggestedPriceError) this.clearError(suggestedPriceError);

    // Only validate if flexible pricing fields are visible
    if (!minimumPriceInput || !suggestedPriceInput) return;

    // Validation logic
    let hasErrors = false;

    // Base price validation
    if (basePrice <= 0) {
      this.showError(basePriceError, 'Base price must be greater than 0');
      hasErrors = true;
    }

    // Minimum price validation
    if (minimumPrice < 0) {
      this.showError(minimumPriceError, 'Minimum price cannot be negative');
      hasErrors = true;
    } else if (minimumPrice > basePrice) {
      this.showError(minimumPriceError, 'Minimum price cannot exceed base price');
      hasErrors = true;
    }

    // Suggested price validation
    if (suggestedPrice !== null && !isNaN(suggestedPrice)) {
      if (suggestedPrice < minimumPrice) {
        this.showError(suggestedPriceError, 'Suggested price cannot be lower than minimum price');
        hasErrors = true;
      } else if (suggestedPrice > basePrice) {
        this.showError(suggestedPriceError, 'Suggested price cannot exceed base price');
        hasErrors = true;
      }
    }

    // Update input styling
    this.updateInputStyling(basePriceInput, !hasErrors);
    if (minimumPriceInput) this.updateInputStyling(minimumPriceInput, !hasErrors);
    if (suggestedPriceInput) this.updateInputStyling(suggestedPriceInput, !hasErrors);
  },

  showError(errorElement, message) {
    errorElement.textContent = message;
    errorElement.classList.remove('hidden');
  },

  clearError(errorElement) {
    errorElement.textContent = '';
    errorElement.classList.add('hidden');
  },

  updateInputStyling(input, isValid) {
    if (isValid) {
      input.classList.remove('border-red-500', 'focus:ring-red-500');
      input.classList.add('border-gray-300', 'focus:ring-blue-500');
    } else {
      input.classList.remove('border-gray-300', 'focus:ring-blue-500');
      input.classList.add('border-red-500', 'focus:ring-red-500');
    }
  }
};

// DateTimeSync Hook - Keeps end date/time in sync with start date/time
Hooks.DateTimeSync = {
  mounted() {
    const startDate = this.el.querySelector('[data-role="start-date"]');
    const startTime = this.el.querySelector('[data-role="start-time"]');
    const endDate = this.el.querySelector('[data-role="end-date"]');
    const endTime = this.el.querySelector('[data-role="end-time"]');

    // Check for polling deadline fields
    const pollingDate = this.el.querySelector('[data-role="polling-deadline-date"]');
    const pollingTime = this.el.querySelector('[data-role="polling-deadline-time"]');
    const pollingHidden = this.el.querySelector('[data-role="polling-deadline"]');

    // Handle polling deadline combination
    if (pollingDate && pollingTime && pollingHidden) {
      const combinePollingDateTime = () => {
        if (pollingDate.value && pollingTime.value) {
          // Combine date and time into ISO string
          const dateTimeString = `${pollingDate.value}T${pollingTime.value}:00`;
          pollingHidden.value = dateTimeString;
        } else {
          // Clear the hidden input if either date or time is empty
          pollingHidden.value = '';
        }
        pollingHidden.dispatchEvent(new Event('change', { bubbles: true }));
      };

      // Set initial value
      combinePollingDateTime();

      // Listen for both input and change events
      const eventTypes = ['change', 'input'];
      eventTypes.forEach(eventType => {
        pollingDate.addEventListener(eventType, combinePollingDateTime);
        pollingTime.addEventListener(eventType, combinePollingDateTime);
      });

      // Store cleanup function for later removal
      this.pollingCleanup = () => {
        eventTypes.forEach(eventType => {
          pollingDate.removeEventListener(eventType, combinePollingDateTime);
          pollingTime.removeEventListener(eventType, combinePollingDateTime);
        });
      };
    }

    // Original start/end date logic
    if (!startDate || !startTime || !endDate || !endTime) return;

    // Helper: round up to next 30-min interval
    function getNextHalfHour(now) {
      let mins = now.getMinutes();
      let rounded = mins < 30 ? 30 : 0;
      let hour = now.getHours() + (mins >= 30 ? 1 : 0);
      return { hour: hour % 24, minute: rounded };
    }

    function setInitialTimes() {
      const now = new Date();
      const { hour, minute } = getNextHalfHour(now);

      // Format to HH:MM
      const pad = n => n.toString().padStart(2, '0');
      const startTimeVal = `${pad(hour)}:${pad(minute)}`;
      startTime.value = startTimeVal;

      // Set start date to today if empty
      if (!startDate.value) {
        startDate.value = now.toISOString().slice(0, 10);
      }

      // Set end date to match start date
      endDate.value = startDate.value;

      // Set end time to +1 hour
      let endHour = (hour + 1) % 24;
      endTime.value = `${pad(endHour)}:${pad(minute)}`;
    }

    // Sync end date/time when start changes
    function syncEndFields() {
      // Copy start date to end date
      endDate.value = startDate.value;
      endDate.dispatchEvent(new Event('change', { bubbles: true }));

      // Parse start time
      const [sHour, sMinute] = startTime.value.split(':').map(Number);
      let endHour = (sHour + 1) % 24;
      endTime.value = `${endHour.toString().padStart(2, '0')}:${sMinute.toString().padStart(2, '0')}`;
    }

    // On mount, set initial times if start time is empty
    if (!startTime.value) setInitialTimes();

    startDate.addEventListener('change', syncEndFields);
    startTime.addEventListener('change', syncEndFields);
  },

  destroyed() {
    // Clean up polling deadline event listeners
    if (this.pollingCleanup) {
      this.pollingCleanup();
    }
  }
};

// TimeSync Hook - For date polling mode where we only sync time fields
Hooks.TimeSync = {
  mounted() {
    const startTime = document.querySelector('[data-role="start-time"]');
    const endTime = document.querySelector('[data-role="end-time"]');

    if (!startTime || !endTime) return;

    // Helper: round up to next 30-min interval
    function getNextHalfHour(now) {
      let mins = now.getMinutes();
      let rounded = mins < 30 ? 30 : 0;
      let hour = now.getHours() + (mins >= 30 ? 1 : 0);
      return { hour: hour % 24, minute: rounded };
    }

    function setInitialTimes() {
      const now = new Date();
      const { hour, minute } = getNextHalfHour(now);

      // Format to HH:MM
      const pad = n => n.toString().padStart(2, '0');
      const startTimeVal = `${pad(hour)}:${pad(minute)}`;
      startTime.value = startTimeVal;

      // Set end time to +1 hour
      let endHour = (hour + 1) % 24;
      endTime.value = `${pad(endHour)}:${pad(minute)}`;
      
      // Trigger events to ensure LiveView updates
      startTime.dispatchEvent(new Event('input', { bubbles: true }));
      startTime.dispatchEvent(new Event('change', { bubbles: true }));
      endTime.dispatchEvent(new Event('input', { bubbles: true }));
      endTime.dispatchEvent(new Event('change', { bubbles: true }));
    }

    // Sync end time when start time changes
    function syncEndTime() {
      if (!startTime.value) return;
      
      // Parse start time
      const [sHour, sMinute] = startTime.value.split(':').map(Number);
      let endHour = (sHour + 1) % 24;
      endTime.value = `${endHour.toString().padStart(2, '0')}:${sMinute.toString().padStart(2, '0')}`;
      
      // Trigger events to ensure LiveView updates
      endTime.dispatchEvent(new Event('input', { bubbles: true }));
      endTime.dispatchEvent(new Event('change', { bubbles: true }));
    }

    // Initialize times if start time is empty
    if (!startTime.value) setInitialTimes();

    startTime.addEventListener('change', syncEndTime);
    startTime.addEventListener('input', syncEndTime);
  }
};

// Google Places Autocomplete Hook
Hooks.GooglePlacesAutocomplete = {
  mounted() {
    if (process.env.NODE_ENV !== 'production') console.log("GooglePlacesAutocomplete hook mounted on element:", this.el.id);
    this.inputEl = this.el;
    this.mounted = true;
    
    // Check if Google Maps API is loaded and ready
    if (window.google && google.maps && google.maps.places) {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps already loaded, initializing now");
      setTimeout(() => this.initClassicAutocomplete(), 100); // Use classic API only for now
    } else {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps not yet loaded, will initialize when ready");
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
    if (process.env.NODE_ENV !== 'production') console.log("GooglePlacesAutocomplete hook destroyed");
  },
  
  // Legacy approach using classic Autocomplete - but it works reliably
  initClassicAutocomplete() {
    if (!this.mounted) return;
    
    try {
      if (process.env.NODE_ENV !== 'production') console.log("Initializing classic Autocomplete API");
      
      // Create the autocomplete object
      const options = {
        types: ['establishment', 'geocode']
      };
      
      const autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
      
      // When a place is selected
      autocomplete.addListener('place_changed', () => {
        if (!this.mounted) return;
        
        if (process.env.NODE_ENV !== 'production') console.group("Place selection process");
        const place = autocomplete.getPlace();
        if (process.env.NODE_ENV !== 'production') console.log("Place selected:", place);
        
        if (!place.geometry) {
          if (process.env.NODE_ENV !== 'production') console.error("No place geometry received");
          if (process.env.NODE_ENV !== 'production') console.groupEnd();
          return;
        }
        
        // Get place details
        const venueName = place.name || '';
        const venueAddress = place.formatted_address || '';
        let city = '', state = '', country = '';
        
        // Get address components
        if (place.address_components) {
          if (process.env.NODE_ENV !== 'production') console.log("Processing address components:", place.address_components);
          for (const component of place.address_components) {
            if (component.types.includes('locality')) {
              city = component.long_name;
              if (process.env.NODE_ENV !== 'production') console.log(`Found city: ${city}`);
            } else if (component.types.includes('administrative_area_level_1')) {
              state = component.long_name;
              if (process.env.NODE_ENV !== 'production') console.log(`Found state: ${state}`);
            } else if (component.types.includes('country')) {
              country = component.long_name;
              if (process.env.NODE_ENV !== 'production') console.log(`Found country: ${country}`);
            }
          }
        }
        
        // Get coordinates
        let lat = null, lng = null;
        if (place.geometry && place.geometry.location) {
          lat = place.geometry.location.lat();
          lng = place.geometry.location.lng();
          if (process.env.NODE_ENV !== 'production') console.log(`Coordinates: ${lat}, ${lng}`);
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
        if (process.env.NODE_ENV !== 'production') console.log("Updating DOM fields...");
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
        if (process.env.NODE_ENV !== 'production') console.log("Pushing venue data to LiveView:", venueData);
        this.pushEvent('venue_selected', venueData);
        
        // Log all form fields for debugging
        this.logFormFieldValues();
        if (process.env.NODE_ENV !== 'production') console.groupEnd();
      });
      
      if (process.env.NODE_ENV !== 'production') console.log("Classic Autocomplete initialized");
    } catch (error) {
      if (process.env.NODE_ENV !== 'production') console.error("Error in Autocomplete initialization:", error);
    }
  },
  
  // Direct DOM update to ensure form fields are updated
  directUpdateField(id, value) {
    if (!this.mounted) return;
    
    if (process.env.NODE_ENV !== 'production') console.group(`Updating field ${id}`);
    
    // Determine form type by examining the input element's ID
    const formType = this.inputEl.id.includes("new") ? "new" : "edit";
    if (process.env.NODE_ENV !== 'production') console.log(`Form context detected: ${formType}`);
    
    // Look for the element using direct ID with suffix
    let field = document.getElementById(`${id}-${formType}`);
    if (process.env.NODE_ENV !== 'production') console.log(`Field by ID ${id}-${formType}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    
    // If not found, try without suffix
    if (!field) {
      field = document.getElementById(id);
      if (process.env.NODE_ENV !== 'production') console.log(`Field by ID ${id}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    }
    
    // If not found, try with venue_ instead of venue-
    if (!field) {
      const altId = id.replace('venue-', 'venue_');
      field = document.getElementById(altId);
      if (process.env.NODE_ENV !== 'production') console.log(`Field by ID ${altId}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    }
    
    // If still not found, try with venue_ instead of venue- and the suffix
    if (!field) {
      const altId = id.replace('venue-', 'venue_');
      field = document.getElementById(`${altId}-${formType}`);
      if (process.env.NODE_ENV !== 'production') console.log(`Field by ID ${altId}-${formType}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    }
    
    // If still not found, try the event[] prefixed version (for Phoenix forms)
    if (!field) {
      const selector = `[name="event[${id.replace('venue-', 'venue_')}]"]`;
      field = document.querySelector(selector);
      if (process.env.NODE_ENV !== 'production') console.log(`Field by selector ${selector}: ${field ? 'FOUND' : 'NOT FOUND'}`);
    }
    
    if (field) {
      // Set the value directly
      const oldValue = field.value;
      field.value = value || '';
      
      // Log the update
      if (process.env.NODE_ENV !== 'production') console.log(`Updated value: "${oldValue}" -> "${value}"`);
      
      // Trigger input and change events to ensure form controllers detect the change
      field.dispatchEvent(new Event('input', {bubbles: true}));
      field.dispatchEvent(new Event('change', {bubbles: true}));
      if (process.env.NODE_ENV !== 'production') console.log("Events dispatched: input, change");
    } else {
      if (process.env.NODE_ENV !== 'production') console.error(`Field ${id} not found in DOM`);
    }
    
    if (process.env.NODE_ENV !== 'production') console.groupEnd();
  },
  
  // Debug helper to log all form field values
  logFormFieldValues() {
    if (process.env.NODE_ENV !== 'production') console.group("Current form field values:");
    
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
    });
    if (process.env.NODE_ENV !== 'production') console.groupEnd();
  },
  
  // Combine end date and time
  combineEndDateTime(endDateInput, endTimeInput, endsAtHidden) {
    if (endDateInput && endDateInput.value && 
        endTimeInput && endTimeInput.value && 
        endsAtHidden) {
      endsAtHidden.value = `${endDateInput.value}T${endTimeInput.value}:00`;
      if (process.env.NODE_ENV !== 'production') console.log(`Combined end datetime: ${endsAtHidden.value}`);
    } else {
      if (process.env.NODE_ENV !== 'production') console.error("Missing required end date/time fields:", {
        endDate: endDateInput?.value,
      });
    }
  }
};

// Calendar Form Sync Hook - Updates hidden form field when calendar dates change
Hooks.CalendarFormSync = {
  mounted() {
    if (process.env.NODE_ENV !== 'production') console.log("CalendarFormSync hook mounted");
    
    // Listen for calendar date changes from the LiveComponent
    this.handleEvent("calendar_dates_changed", ({ dates, component_id }) => {
      if (process.env.NODE_ENV !== 'production') console.log("Calendar dates changed:", dates);
      
      // Find the hidden input field for selected poll dates
      const hiddenInput = document.querySelector('[name="event[selected_poll_dates]"]');
      if (hiddenInput) {
        hiddenInput.value = dates.join(',');
        if (process.env.NODE_ENV !== 'production') console.log("Updated hidden field with:", hiddenInput.value);
        
        // Dispatch change event to trigger any form validation
        hiddenInput.dispatchEvent(new Event('change', { bubbles: true }));
      } else {
        if (process.env.NODE_ENV !== 'production') console.warn("Could not find hidden input for selected_poll_dates");
      }
      
      // Also update any date validation display
      this.updateDateValidation(dates);
    });
  },
  
  updateDateValidation(dates) {
    const errorContainer = document.getElementById('date-selection-error');
    if (errorContainer) {
      if (dates.length === 0) {
        errorContainer.textContent = 'Please select at least one date for the poll';
        errorContainer.className = 'text-red-600 text-sm mt-1';
      } else {
        errorContainer.textContent = '';
        errorContainer.className = 'hidden';
      }
    }
  }
};

// Calendar Keyboard Navigation Hook - Handles keyboard navigation within calendar
Hooks.CalendarKeyboardNav = {
  mounted() {
    if (process.env.NODE_ENV !== 'production') console.log("CalendarKeyboardNav hook mounted");
    
    // Handle keyboard navigation events
    this.el.addEventListener('keydown', (e) => {
      const currentButton = e.target;
      
      // Only handle navigation for calendar day buttons
      if (!currentButton.hasAttribute('phx-value-date')) return;
      
      const currentDate = currentButton.getAttribute('phx-value-date');
      
      // Handle arrow keys and space/enter
      if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Enter', ' '].includes(e.key)) {
        e.preventDefault();
        
        // Send navigation event to LiveComponent
        this.pushEvent("key_navigation", {
          key: e.key === ' ' ? 'Space' : e.key,
          date: currentDate
        });
      }
    });
    
    // Handle focus events from server
    this.handleEvent("focus_date", ({ date }) => {
      const button = this.el.querySelector(`[phx-value-date="${date}"]`);
      if (button && !button.disabled) {
        button.focus();
      }
    });
  }
};

// Supabase image upload hook for file input
Hooks.SupabaseImageUpload = SupabaseImageUpload;

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