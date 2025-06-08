// Import dependencies
import "phoenix_html";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import topbar from "../vendor/topbar";
import { createClient } from '@supabase/supabase-js';

// Define LiveView hooks here
import SupabaseImageUpload from "./supabase_upload";
import AuthSyncHook from "./hooks/auth_sync_hook";
let Hooks = {};

// Base64 utilities for encoding state parameters
const Base64 = {
  encode: (str) => btoa(unescape(encodeURIComponent(str))),
  decode: (str) => decodeURIComponent(escape(atob(str)))
};

// Supabase Auth OAuth Hook for social authentication
Hooks.SocialAuth = {
  mounted() {
    // Get Supabase configuration from body data attributes
    const supabaseUrl = document.body.dataset.supabaseUrl;
    const supabaseApiKey = document.body.dataset.supabaseApiKey;
    
    if (!supabaseUrl || !supabaseApiKey) {
      console.error('Supabase configuration not found');
      return;
    }

    // Initialize Supabase client
    this.supabase = createClient(supabaseUrl, supabaseApiKey);
    
    // Handle OAuth provider buttons
    this.el.addEventListener('click', async (e) => {
      const button = e.target.closest('[data-provider]');
      if (!button) return;
      
      e.preventDefault();
      
      const provider = button.dataset.provider;
      const redirectTo = button.dataset.redirectTo || '/dashboard';
      const isLoading = button.classList.contains('loading');
      
      if (isLoading) return; // Prevent double-clicks
      
      // Set loading state with visual feedback
      this.setLoadingState(button, true);
      
      try {
        await this.signInWithProvider(provider, redirectTo);
        
        // Show success state briefly before the OAuth redirect happens
        this.setSuccessState(button, true);
        
      } catch (error) {
        console.error(`${provider} auth error:`, error);
        this.setLoadingState(button, false);
        
        // Send error to backend for flash storage and display
        this.sendErrorToBackend(provider, error.message || 'Authentication failed', this.categorizeError(error));
        
        // Show immediate toast feedback
        this.showError(`Failed to connect with ${provider}. Please try again.`);
      }
    });
    
    // Set up error dismissal event listeners
    this.setupErrorHandlers();
  },

  async signInWithProvider(provider, redirectTo = '/dashboard') {
    // Determine if we're on a registration page
    const isRegistration = window.location.pathname.includes('/register') || 
                          window.location.pathname.includes('/signup');
    
    // Create state parameter with provider and context info
    const state = {
      provider: provider,
      context: isRegistration ? 'registration' : 'login',
      timestamp: Date.now()
    };
    
    const encodedState = Base64.encode(JSON.stringify(state));
    
    const { data, error } = await this.supabase.auth.signInWithOAuth({
      provider: provider,
      options: {
        redirectTo: `${window.location.origin}/auth/callback?redirect_to=${encodeURIComponent(redirectTo)}`,
        queryParams: {
          state: encodedState
        }
      }
    });
    
    if (error) {
      throw error;
    }
    
    // The redirect will happen automatically via Supabase
    // No further action needed here - the OAuth provider will redirect
    // back to our callback URL with the authorization code
  },
  
  setLoadingState(button, isLoading) {
    const loadingText = button.querySelector('.loading-text');
    const loadingSpinner = button.querySelector('.loading-spinner');
    
    if (isLoading) {
      button.disabled = true;
      button.classList.add('loading');
      button.classList.remove('success');
      if (loadingSpinner) loadingSpinner.classList.remove('hidden');
      if (loadingText) loadingText.textContent = 'Connecting...';
    } else {
      button.disabled = false;
      button.classList.remove('loading');
      if (loadingSpinner) loadingSpinner.classList.add('hidden');
      if (loadingText) {
        const provider = button.dataset.provider;
        loadingText.textContent = `Continue with ${provider.charAt(0).toUpperCase() + provider.slice(1)}`;
      }
    }
  },

  setSuccessState(button, isSuccess) {
    const loadingText = button.querySelector('.loading-text');
    const loadingSpinner = button.querySelector('.loading-spinner');
    
    if (isSuccess) {
      button.classList.remove('loading');
      button.classList.add('success');
      if (loadingSpinner) loadingSpinner.classList.add('hidden');
      if (loadingText) loadingText.textContent = 'Redirecting...';
    } else {
      button.classList.remove('success');
    }
  },
  
  categorizeError(error) {
    const message = error.message || error.toString();
    
    if (message.includes('popup_closed') || message.includes('closed')) {
      return 'popup_closed';
    } else if (message.includes('network') || message.includes('timeout')) {
      return 'network_error';
    } else if (message.includes('access_denied') || message.includes('user_denied')) {
      return 'access_denied';
    } else if (message.includes('invalid_request') || message.includes('invalid_grant')) {
      return 'invalid_request';
    } else if (message.includes('server_error') || message.includes('temporarily_unavailable')) {
      return 'server_error';
    } else {
      return 'unknown_error';
    }
  },
  
  // Send error data to backend
  async sendErrorToBackend(provider, reason, errorType) {
    try {
      const csrfToken = this.el.dataset.csrfToken || document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
      
      const response = await fetch('/auth/error', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({
          provider: provider,
          reason: reason,
          error_type: errorType
        })
      });

      if (!response.ok) {
        console.warn('Failed to send error to backend:', response.status);
      }
    } catch (error) {
      console.warn('Error sending auth error to backend:', error);
    }
  },

  // Set up error handling event listeners
  setupErrorHandlers() {
    // Handle error dismissal buttons
    this.el.addEventListener('click', (e) => {
      if (e.target.closest('[phx-click="dismiss_auth_error"]')) {
        e.preventDefault();
        const errorElement = e.target.closest('.social-auth-error, .social-auth-error-compact');
        if (errorElement) {
          this.dismissError(errorElement);
        }
      }
    });
    
    // Handle retry buttons
    this.el.addEventListener('click', (e) => {
      const retryButton = e.target.closest('[phx-click^="retry_"]');
      if (retryButton) {
        e.preventDefault();
        const provider = retryButton.getAttribute('phx-click').replace('retry_', '').replace('_auth', '');
        this.retryAuth(provider);
      }
    });
  },

  // Dismiss error with animation
  dismissError(errorElement) {
    errorElement.classList.add('dismissing');
    setTimeout(() => {
      if (errorElement.parentNode) {
        errorElement.parentNode.removeChild(errorElement);
      }
    }, 300);
  },

  // Retry authentication for a specific provider
  async retryAuth(provider) {
    const button = this.el.querySelector(`[data-provider="${provider}"]`);
    if (button) {
      // Clear any existing errors first
      const errorElements = this.el.querySelectorAll('.social-auth-error, .social-auth-error-compact');
      errorElements.forEach(el => this.dismissError(el));
      
      // Trigger the auth flow again
      button.click();
    }
  },

  // Handle retry events from LiveView
  handleEvent(event, callback) {
    if (event === 'retry_social_auth') {
      callback(() => {
        // Find the last clicked button and retry
        const buttons = this.el.querySelectorAll('[data-provider]');
        const lastButton = Array.from(buttons).find(btn => btn.classList.contains('loading'));
        if (lastButton) {
          lastButton.click();
        }
      });
    }
  },

  showError(message) {
    // Create a simple toast notification that matches the app's flash style
    const toast = document.createElement('div');
    toast.className = 'fixed top-20 right-4 max-w-sm w-full bg-white border border-red-200 rounded-xl shadow-lg p-4 z-50 transition-all duration-300';
    toast.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <span class="text-red-500 text-lg">⚠️</span>
        </div>
        <div class="ml-3 flex-1">
          <p class="text-sm text-red-800 font-medium">${message}</p>
        </div>
        <button class="ml-4 text-red-500 hover:text-red-700" onclick="this.parentElement.parentElement.remove()">
          <span class="sr-only">Close</span>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
          </svg>
        </button>
      </div>
    `;
    
    document.body.appendChild(toast);
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (toast.parentNode) {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(100%)';
        setTimeout(() => {
          if (toast.parentNode) {
            toast.parentNode.removeChild(toast);
          }
        }, 300);
      }
    }, 5000);
  }
};

// Global OAuth functions for use outside of LiveView contexts
window.EventasaurusAuth = {
  async signInWithFacebook() {
    const supabaseUrl = document.body.dataset.supabaseUrl;
    const supabaseApiKey = document.body.dataset.supabaseApiKey;
    
    if (!supabaseUrl || !supabaseApiKey) {
      throw new Error('Supabase configuration not found');
    }

    const supabase = createClient(supabaseUrl, supabaseApiKey);
    
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: 'facebook',
      options: {
        redirectTo: `${window.location.origin}/auth/callback`
      }
    });
    
    if (error) throw error;
    return data;
  },

  async signInWithTwitter() {
    const supabaseUrl = document.body.dataset.supabaseUrl;
    const supabaseApiKey = document.body.dataset.supabaseApiKey;
    
    if (!supabaseUrl || !supabaseApiKey) {
      throw new Error('Supabase configuration not found');
    }

    const supabase = createClient(supabaseUrl, supabaseApiKey);
    
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: 'twitter',
      options: {
        redirectTo: `${window.location.origin}/auth/callback`
      }
    });
    
    if (error) throw error;
    return data;
  },

  async signInWithProvider(provider) {
    const supabaseUrl = document.body.dataset.supabaseUrl;
    const supabaseApiKey = document.body.dataset.supabaseApiKey;
    
    if (!supabaseUrl || !supabaseApiKey) {
      throw new Error('Supabase configuration not found');
    }

    const supabase = createClient(supabaseUrl, supabaseApiKey);
    
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: provider,
      options: {
        redirectTo: `${window.location.origin}/auth/callback`
      }
    });
    
    if (error) throw error;
    return data;
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

// DateTimeSync Hook - Keeps end date/time in sync with start date/time
Hooks.DateTimeSync = {
  mounted() {
    const startDate = this.el.querySelector('[data-role="start-date"]');
    const startTime = this.el.querySelector('[data-role="start-time"]');
    const endDate = this.el.querySelector('[data-role="end-date"]');
    const endTime = this.el.querySelector('[data-role="end-time"]');

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

// Supabase image upload hook for file input
Hooks.SupabaseImageUpload = SupabaseImageUpload;

// Cross-tab authentication synchronization hook
Hooks.AuthSyncHook = AuthSyncHook;

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