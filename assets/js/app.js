// Import dependencies
import "phoenix_html";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import topbar from "../vendor/topbar";
import { TicketQR } from "./ticket_qr";

// Supabase client setup for identity management
let supabaseClient = null;

// Clipboard functionality
window.addEventListener("phx:copy_to_clipboard", (e) => {
  const text = e.detail.text;
  if (navigator.clipboard && window.isSecureContext) {
    // Use the modern clipboard API
    navigator.clipboard.writeText(text).then(() => {
      console.log("Text copied to clipboard:", text);
    }).catch(err => {
      console.error("Failed to copy text:", err);
      fallbackCopyTextToClipboard(text);
    });
  } else {
    // Fallback for older browsers
    fallbackCopyTextToClipboard(text);
  }
});

function fallbackCopyTextToClipboard(text) {
  const textArea = document.createElement("textarea");
  textArea.value = text;
  textArea.style.top = "0";
  textArea.style.left = "0";
  textArea.style.position = "fixed";
  document.body.appendChild(textArea);
  textArea.focus();
  textArea.select();
  try {
    const successful = document.execCommand('copy');
    if (successful) {
      console.log("Text copied to clipboard (fallback):", text);
    } else {
      console.error("Failed to copy text (fallback)");
    }
  } catch (err) {
    console.error("Fallback copy failed:", err);
  }
  document.body.removeChild(textArea);
}

// PostHog Analytics Manager with performance optimizations
class PostHogManager {
  constructor() {
    this.posthog = null;
    this.isLoaded = false;
    this.isLoading = false;
    this.eventQueue = [];
    this.loadAttempts = 0;
    this.maxLoadAttempts = 3;
    this.retryDelay = 2000;
    this.privacyConsent = this.getPrivacyConsent();
    this.isOnline = navigator.onLine;
    
    // Listen for online/offline events
    window.addEventListener('online', () => {
      this.isOnline = true;
      this.processQueue();
    });
    
    window.addEventListener('offline', () => {
      this.isOnline = false;
    });
    
    // Privacy event listener
    window.addEventListener('posthog:privacy-consent', (e) => {
      this.updatePrivacyConsent(e.detail.consent);
    });
  }
  
  async init() {
    if (this.isLoaded || this.isLoading || !this.privacyConsent) {
      console.log('PostHog init skipped:', {
        isLoaded: this.isLoaded,
        isLoading: this.isLoading,
        privacyConsent: this.privacyConsent
      });
      return;
    }
    
    this.isLoading = true;
    
    try {
      // Get PostHog config from window variables set by the server
      const posthogApiKey = window.POSTHOG_API_KEY;
      const posthogHost = window.POSTHOG_HOST || 'https://eu.i.posthog.com';
      
      console.log('PostHog initialization attempt:', {
        apiKeyPresent: !!posthogApiKey,
        apiKeyLength: posthogApiKey ? posthogApiKey.length : 0,
        host: posthogHost,
        privacyConsent: this.privacyConsent,
        userAgent: navigator.userAgent,
        isOnline: this.isOnline,
        protocol: window.location.protocol,
        domain: window.location.hostname
      });
      
      if (!posthogApiKey) {
        console.warn('PostHog API key not found - analytics will be disabled');
        this.isLoading = false;
        return;
      }
      
      if (!this.privacyConsent.analytics) {
        console.log('PostHog disabled by privacy consent - analytics opt-out');
        this.isLoading = false;
        return;
      }
      
      console.log('Attempting to load PostHog module...');
      
      // Dynamic import to prevent blocking page render
      const { default: posthog } = await import('posthog-js');
      
      console.log('PostHog module loaded, initializing with config...');
      
      // Initialize with privacy-focused settings
      posthog.init(posthogApiKey, {
        api_host: posthogHost,
        
        // Privacy settings
        disable_session_recording: !this.privacyConsent.analytics,
        disable_cookie: !this.privacyConsent.cookies,
        respect_dnt: true,
        opt_out_capturing_by_default: !this.privacyConsent.analytics,
        
        // Performance settings
        capture_pageview: this.privacyConsent.analytics,
        capture_pageleave: this.privacyConsent.analytics,
        loaded: (posthogInstance) => {
          this.onPostHogLoaded(posthogInstance);
        },
        
        // Error handling
        on_request_error: (error) => {
          console.warn('PostHog request failed:', error);
        },
        
        // Batch settings for performance
        batch_requests: true,
        batch_size: 10,
        batch_flush_interval_ms: 5000,
        
        // Cross-domain settings
        cross_subdomain_cookie: false,
        secure_cookie: window.location.protocol === 'https:',
        
        // Advanced privacy
        mask_all_element_attributes: !this.privacyConsent.analytics,
        mask_all_text: !this.privacyConsent.analytics
      });
      
      this.posthog = posthog;
      this.isLoaded = true;
      this.isLoading = false;
      this.loadAttempts = 0;
      
      console.log('PostHog loaded successfully with privacy settings:', this.privacyConsent);
      
      // Process any queued events
      this.processQueue();
      
    } catch (error) {
      console.error('Failed to load PostHog:', {
        error: error.message,
        stack: error.stack,
        name: error.name,
        loadAttempts: this.loadAttempts,
        isOnline: this.isOnline,
        userAgent: navigator.userAgent
      });
      this.isLoading = false;
      this.loadAttempts++;
      
      // Retry loading with exponential backoff
      if (this.loadAttempts < this.maxLoadAttempts) {
        const delay = this.retryDelay * Math.pow(2, this.loadAttempts - 1);
        console.log(`Retrying PostHog load in ${delay}ms (attempt ${this.loadAttempts}/${this.maxLoadAttempts})`);
        setTimeout(() => this.init(), delay);
      } else {
        console.warn('PostHog failed to load after multiple attempts - analytics disabled');
        this.processQueue(); // Process queue to clear it
      }
    }
  }
  
  onPostHogLoaded(posthogInstance) {
    console.log('PostHog initialized successfully');
    
    // Identify user if authenticated and consent given
    if (this.privacyConsent.analytics && window.currentUser && window.currentUser.id) {
      const identifyProps = {
        user_type: 'authenticated',
        privacy_consent: this.privacyConsent
      };
      
      // Only include hashed email if marketing consent is given and email exists
      if (this.privacyConsent.marketing && window.currentUser.email) {
        this.hashEmail(window.currentUser.email)
          .then(hashedEmail => {
            posthogInstance.identify(window.currentUser.id, {
              ...identifyProps,
              email_hash: hashedEmail
            });
            console.log('PostHog user identified with hashed email:', window.currentUser.id);
          })
          .catch(error => {
            console.warn('Failed to hash email for PostHog:', error);
            // Fall back to identifying without email hash
            posthogInstance.identify(window.currentUser.id, identifyProps);
            console.log('PostHog user identified (fallback, no email hash):', window.currentUser.id);
          });
      } else {
        posthogInstance.identify(window.currentUser.id, identifyProps);
        console.log('PostHog user identified (no email):', window.currentUser.id);
      }
    } else if (this.privacyConsent.analytics) {
      // Set properties for anonymous users
      posthogInstance.register({
        user_type: 'anonymous',
        privacy_consent: this.privacyConsent
      });
      console.log('PostHog tracking anonymous user');
    }
  }
  
  capture(event, properties = {}) {
    // Add privacy and performance checks
    if (!this.privacyConsent.analytics) {
      console.log('PostHog event blocked by privacy settings:', event);
      return;
    }
    
    const eventData = {
      event,
      properties: {
        ...properties,
        timestamp: Date.now(),
        user_agent: navigator.userAgent,
        is_online: this.isOnline,
        privacy_consent: this.privacyConsent
      }
    };
    
    if (this.isLoaded && this.posthog && this.isOnline) {
      try {
        this.posthog.capture(event, eventData.properties);
        console.log('PostHog event captured:', event, eventData.properties);
      } catch (error) {
        console.warn('Failed to capture PostHog event:', error);
        this.queueEvent(eventData);
      }
    } else {
      // Queue for later if PostHog not loaded or offline
      this.queueEvent(eventData);
    }
  }
  
  queueEvent(eventData) {
    // Limit queue size to prevent memory issues
    if (this.eventQueue.length >= 100) {
      this.eventQueue.shift(); // Remove oldest event
    }
    
    this.eventQueue.push(eventData);
    console.log(`Event queued (${this.eventQueue.length} total):`, eventData.event);
  }
  
  processQueue() {
    if (!this.isLoaded || !this.posthog || !this.isOnline || !this.privacyConsent.analytics) {
      return;
    }
    
    console.log(`Processing ${this.eventQueue.length} queued events`);
    
    const eventsToProcess = [...this.eventQueue];
    this.eventQueue = [];
    
    eventsToProcess.forEach(eventData => {
      try {
        this.posthog.capture(eventData.event, eventData.properties);
      } catch (error) {
        console.warn('Failed to process queued event:', error);
        // Re-queue if it fails
        this.queueEvent(eventData);
      }
    });
  }
  
  getPrivacyConsent() {
    try {
      const stored = localStorage.getItem('posthog_privacy_consent');
      if (stored) {
        return JSON.parse(stored);
      }
    } catch (error) {
      console.warn('Failed to read privacy consent from localStorage:', error);
    }
    
    // Default privacy settings (conservative)
    return {
      analytics: false,
      cookies: false,
      marketing: false, // For hashed email and marketing communications
      essential: true // Always allow essential functionality
    };
  }
  
  updatePrivacyConsent(consent) {
    this.privacyConsent = { ...this.privacyConsent, ...consent };
    
    try {
      localStorage.setItem('posthog_privacy_consent', JSON.stringify(this.privacyConsent));
    } catch (error) {
      console.warn('Failed to save privacy consent to localStorage:', error);
    }
    
    console.log('Privacy consent updated:', this.privacyConsent);
    
    // Reinitialize PostHog if consent changed
    if (consent.analytics && !this.isLoaded) {
      this.init();
    } else if (!consent.analytics && this.isLoaded) {
      this.disable();
    }
  }
  
  disable() {
    if (this.posthog) {
      try {
        this.posthog.opt_out_capturing();
        console.log('PostHog tracking disabled');
      } catch (error) {
        console.warn('Failed to disable PostHog:', error);
      }
    }
  }
  
  // Helper to hash email for GDPR compliance
  async hashEmail(email) {
    // Check if email is valid
    if (!email || typeof email !== 'string') {
      throw new Error('Invalid email provided for hashing');
    }
    
    // Check if crypto.subtle is available (requires HTTPS or localhost)
    if (typeof crypto?.subtle !== 'object') {
      console.warn('Web Crypto API not available—cannot hash email securely.');
      throw new Error('crypto.subtle is not supported in this environment');
    }
    
    try {
      const data = new TextEncoder().encode(email);
      const digest = await crypto.subtle.digest('SHA-256', data);
      return Array.from(new Uint8Array(digest))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
    } catch (error) {
      console.error('Failed to hash email:', error);
      throw new Error(`Email hashing failed: ${error.message}`);
    }
  }

  // GDPR compliance helper
    showPrivacyBanner() {
    if (this.privacyConsent.analytics === undefined) {
      // Dispatch event to show privacy banner UI
      window.dispatchEvent(new CustomEvent('posthog:show-privacy-banner'));
      
      // Show the privacy banner element if it exists
      const banner = document.getElementById('privacy-banner');
      if (banner) {
        banner.style.display = 'block';
        // Animate in
        setTimeout(() => {
          banner.style.transform = 'translateY(0)';
        }, 100);
      }
    }
  }
}

// Initialize PostHog manager
const posthogManager = new PostHogManager();

// Legacy compatibility function
function initPostHogClient() {
  return posthogManager.init();
}

// Initialize Supabase client if needed
function initSupabaseClient() {
  if (!supabaseClient && typeof window !== 'undefined') {
    try {
      // Get Supabase config from meta tags or data attributes
      let supabaseUrl = document.querySelector('meta[name="supabase-url"]')?.content;
      let supabaseAnonKey = document.querySelector('meta[name="supabase-anon-key"]')?.content;
      
      // Fallback to body data attributes if meta tags not found
      if (!supabaseUrl || !supabaseAnonKey) {
        const body = document.body;
        supabaseUrl = body.dataset.supabaseUrl;
        supabaseAnonKey = body.dataset.supabaseApiKey;
      }
      
      console.log('Supabase config found:', { 
        hasUrl: !!supabaseUrl, 
        hasKey: !!supabaseAnonKey,
        hasSupabaseGlobal: !!window.supabase 
      });
      
      if (supabaseUrl && supabaseAnonKey && window.supabase) {
        supabaseClient = window.supabase.createClient(supabaseUrl, supabaseAnonKey);
        console.log('Supabase client initialized successfully');
      } else {
        console.error('Missing Supabase configuration or library:', {
          supabaseUrl: !!supabaseUrl,
          supabaseAnonKey: !!supabaseAnonKey,
          supabaseLibrary: !!window.supabase
        });
      }
    } catch (error) {
      console.error('Error initializing Supabase client:', error);
    }
  }
  return supabaseClient;
}

// Define LiveView hooks here
import SupabaseImageUpload from "./supabase_upload";
let Hooks = {};

// TicketQR hook for generating QR codes on tickets
Hooks.TicketQR = TicketQR;

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

// ThresholdForm Hook - Handles threshold type radio button toggling and revenue conversion
Hooks.ThresholdForm = {
  mounted() {
    // Get form elements
    this.form = this.el.querySelector('form');
    this.thresholdTypeInputs = this.el.querySelectorAll('input[name="event[threshold_type]"]');
    this.attendeeThreshold = this.el.querySelector('#attendee-threshold');
    this.revenueThreshold = this.el.querySelector('#revenue-threshold');
    this.revenueInput = document.getElementById('threshold_revenue_dollars');
    this.hiddenRevenueInput = document.getElementById('threshold_revenue_cents');

    // Initial setup
    this.updateVisibility();
    this.setupRevenueConversion();

    // Add event listeners
    this.thresholdTypeInputs.forEach(radio => {
      radio.addEventListener('change', () => this.updateVisibility());
    });
  },

  updateVisibility() {
    const selectedType = this.el.querySelector('input[name="event[threshold_type]"]:checked')?.value || 'attendee_count';
    
    // Show/hide fields based on threshold type
    switch (selectedType) {
      case 'attendee_count':
        this.attendeeThreshold?.classList.remove('hidden');
        this.revenueThreshold?.classList.add('hidden');
        break;
      case 'revenue':
        this.attendeeThreshold?.classList.add('hidden');
        this.revenueThreshold?.classList.remove('hidden');
        break;
      case 'both':
        this.attendeeThreshold?.classList.remove('hidden');
        this.revenueThreshold?.classList.remove('hidden');
        break;
    }
  },

  setupRevenueConversion() {
    if (!this.revenueInput || !this.hiddenRevenueInput) return;

    // Convert dollars to cents on input
    this.revenueInput.addEventListener('input', (e) => {
      const value = e.target.value.trim();
      if (value === '') {
        // Set empty string for empty input
        this.hiddenRevenueInput.value = '';
      } else {
        const dollars = parseFloat(value) || 0;
        const cents = Math.round(dollars * 100);
        this.hiddenRevenueInput.value = cents;
      }
      
      // Trigger change event for LiveView
      this.hiddenRevenueInput.dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Initial conversion if there's already a value
    if (this.revenueInput.value) {
      const value = this.revenueInput.value.trim();
      if (value !== '') {
        const dollars = parseFloat(value) || 0;
        const cents = Math.round(dollars * 100);
        this.hiddenRevenueInput.value = cents;
      }
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

// Google Places Autocomplete Hook - Consolidated with recent locations filtering
Hooks.VenueSearchWithFiltering = {
  mounted() {
    if (process.env.NODE_ENV !== 'production') console.log("VenueSearchWithFiltering hook mounted on element:", this.el.id);
    this.inputEl = this.el;
    this.mounted = true;
    this.debounceTimeout = null;
    
    // Initialize Google Places as enabled by default for better UX
    this.googlePlacesEnabled = true;
    this.autocomplete = null;
    this.lastPlaceSelected = '';
    
    // Initialize Google Places immediately
    this.initGooglePlaces();
    
    // Listen for enable_google_places event from LiveView (for manual re-enabling)
    this.handleEvent("enable_google_places", () => {
      if (process.env.NODE_ENV !== 'production') console.log("Re-enabling Google Places from LiveView event");
      this.enableGooglePlaces();
    });
    
    // Add input listener for filtering recent locations
    this.inputEl.addEventListener('input', (e) => {
      const query = e.target.value.trim();
      
      // Debounce the filtering to avoid too many LiveView calls
      if (this.debounceTimeout) {
        clearTimeout(this.debounceTimeout);
      }
      
      this.debounceTimeout = setTimeout(() => {
        if (this.mounted) {
          // Only filter recent locations if user is not using Google Places
          if (!this.googlePlacesEnabled || query.length < 2) {
            this.pushEvent('filter_recent_locations', { query: query });
          }
        }
      }, 150); // 150ms debounce
    });
    
    // Add focus event listener to show recent locations when appropriate
    this.handleFocus = () => {
      // Only show recent locations if Google Places is disabled or input is empty
      if (!this.googlePlacesEnabled || this.inputEl.value.trim().length === 0) {
        this.pushEvent('show_recent_locations', {});
      }
    };
    this.inputEl.addEventListener('focus', this.handleFocus);
    
    // Hide recent locations when clicking outside
    this.documentClickHandler = (e) => {
      // Validate that e.target is a DOM element
      if (e.target && typeof e.target.contains === 'function' && typeof e.target.closest === 'function') {
        if (!this.inputEl.contains(e.target) && !e.target.closest('.recent-locations-dropdown')) {
          this.pushEvent('hide_recent_locations', {});
        }
      }
    };
    document.addEventListener('click', this.documentClickHandler);
  },
  
  destroyed() {
    this.mounted = false;
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout);
    }
    
    // Remove event listeners to prevent memory leaks
    if (this.inputEl && this.handleFocus) {
      this.inputEl.removeEventListener('focus', this.handleFocus);
      this.handleFocus = null;
    }
    
    if (this.documentClickHandler) {
      document.removeEventListener('click', this.documentClickHandler);
      this.documentClickHandler = null;
    }
    
    // Remove this hook from the waiting list if it exists
    if (window.venueSearchHooks && Array.isArray(window.venueSearchHooks)) {
      const index = window.venueSearchHooks.indexOf(this);
      if (index > -1) {
        window.venueSearchHooks.splice(index, 1);
      }
    }
    
    if (process.env.NODE_ENV !== 'production') console.log("VenueSearchWithFiltering hook destroyed");
  },
  
  initGooglePlaces() {
    if (!this.mounted) return;
    
    // Check if Google Maps API is loaded and ready
    if (window.google && google.maps && google.maps.places) {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps already loaded, initializing autocomplete");
      setTimeout(() => this.initClassicAutocomplete(), 100);
    } else {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps not yet loaded, will initialize when ready");
      // Add this hook to the list of hooks waiting for Google Maps to load
      if (!window.venueSearchHooks) {
        window.venueSearchHooks = [];
      }
      
      // Ensure this hook isn't already in the list to prevent duplicates
      if (!window.venueSearchHooks.includes(this)) {
        window.venueSearchHooks.push(this);
      }
      
      // Set up the global callback for when Google Maps loads (only once)
      if (!window.initGooglePlaces) {
        window.initGooglePlaces = () => {
          if (window.venueSearchHooks && Array.isArray(window.venueSearchHooks)) {
            window.venueSearchHooks.forEach(hook => {
              if (hook.mounted) {
                try {
                  setTimeout(() => hook.initClassicAutocomplete(), 100);
                } catch (error) {
                  if (process.env.NODE_ENV !== 'production') console.error("Error initializing autocomplete for hook:", error);
                }
              }
            });
            // Clear the list after initialization
            window.venueSearchHooks = [];
          }
        };
      }
    }
  },
  
  // Google Places Autocomplete initialization
  initClassicAutocomplete() {
    if (!this.mounted) return;
    
    try {
      if (process.env.NODE_ENV !== 'production') console.log("Initializing Google Places Autocomplete");
      
      // Prevent creating multiple instances
      if (this.autocomplete) {
        if (process.env.NODE_ENV !== 'production') console.log("Autocomplete already initialized");
        return;
      }
      
      // Create the autocomplete object with suggestions enabled by default
      const options = {
        types: ['establishment', 'geocode']
      };
      
      this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
      this.googlePlacesEnabled = true;
      
      // When a place is selected from Google Places
      this.autocomplete.addListener('place_changed', () => {
        if (!this.mounted) return;
        
        if (process.env.NODE_ENV !== 'production') console.group("Google Places selection process");
        const place = this.autocomplete.getPlace();
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
        
        // Track this selection to differentiate from manual typing
        this.lastPlaceSelected = venueAddress || venueName;
        
        // Get address components
        if (place.address_components) {
          if (process.env.NODE_ENV !== 'production') console.log("Processing address components:", place.address_components);
          for (const component of place.address_components) {
            if (component.types.includes('locality')) {
              city = component.long_name;
            } else if (component.types.includes('administrative_area_level_1')) {
              state = component.long_name;
            } else if (component.types.includes('country')) {
              country = component.long_name;
            }
          }
        }
        
        // Get coordinates
        let lat = null, lng = null;
        if (place.geometry && place.geometry.location) {
          lat = place.geometry.location.lat();
          lng = place.geometry.location.lng();
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
        
        // Hide recent locations after selection
        this.pushEvent('hide_recent_locations', {});
        
        if (process.env.NODE_ENV !== 'production') console.groupEnd();
      });
      
      if (process.env.NODE_ENV !== 'production') console.log("Google Places Autocomplete initialized");
    } catch (error) {
      if (process.env.NODE_ENV !== 'production') console.error("Error in Google Places Autocomplete initialization:", error);
    }
  },
  
  // Methods to control Google Places suggestions
  enableGooglePlaces() {
    if (this.autocomplete) {
      this.googlePlacesEnabled = true;
      // Re-enable the autocomplete with proper types
      this.autocomplete.setOptions({
        types: ['establishment', 'geocode']
      });
      
      // Hide recent locations when Google Places is enabled
      this.pushEvent('hide_recent_locations', {});
      
      // Focus the input and trigger search if there's content
      this.inputEl.focus();
      if (this.inputEl.value.trim()) {
        // Trigger autocomplete to show suggestions for current text using proper DOM events
        this.inputEl.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
        this.inputEl.dispatchEvent(new Event('focus', { bubbles: true }));
      }
    }
  },
  
  disableGooglePlaces() {
    if (this.autocomplete) {
      this.googlePlacesEnabled = false;
      
      // Disable the autocomplete by unbinding it
      if (this.autocomplete.unbindAll) {
        this.autocomplete.unbindAll();
      } else {
        // Fallback: set restrictive bounds to effectively disable
        this.autocomplete.setOptions({
          types: [],
          bounds: new google.maps.LatLngBounds(
            new google.maps.LatLng(0, 0),
            new google.maps.LatLng(0, 0)
          ),
          strictBounds: true
        });
      }
      
      // Force hide any visible suggestions dropdown
      const pacContainers = document.querySelectorAll('.pac-container');
      pacContainers.forEach(container => {
        container.style.display = 'none';
      });
      
      if (process.env.NODE_ENV !== 'production') console.log("Google Places disabled and suggestions hidden");
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
    
    // Set the field value if found
    if (field) {
      field.value = value;
      field.dispatchEvent(new Event('input', { bubbles: true }));
      field.dispatchEvent(new Event('change', { bubbles: true }));
      if (process.env.NODE_ENV !== 'production') console.log(`Set field ${id} to:`, value);
    } else {
      if (process.env.NODE_ENV !== 'production') console.warn(`Could not find field for ${id}`);
    }
    
    if (process.env.NODE_ENV !== 'production') console.groupEnd();
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

// Stripe Payment Elements Hook
Hooks.StripePaymentElements = {
  mounted() {
    console.log("Stripe Payment Elements hook mounted");
    
    // Get client secret from the page URL params
    const urlParams = new URLSearchParams(window.location.search);
    const clientSecret = urlParams.get('client_secret');
    
    if (!clientSecret || clientSecret.length < 10) {
      console.error("No valid client_secret found in URL");
      this.pushEvent("payment_failed", {error: {message: "Missing or invalid payment session"}});
      return;
    }
    
    if (!window.Stripe) {
      console.error("Stripe.js not loaded");
      return;
    }
    
    // Initialize Stripe with publishable key
    if (!window.stripePublishableKey) {
      console.error("Stripe publishable key not found");
      return;
    }
    
    const stripe = Stripe(window.stripePublishableKey);
    
    const elements = stripe.elements({
      clientSecret: clientSecret,
      appearance: {
        theme: 'stripe',
        variables: {
          colorPrimary: '#2563eb',
          colorBackground: '#ffffff',
          colorText: '#111827',
          colorDanger: '#dc2626',
          fontFamily: 'system-ui, sans-serif',
          spacingUnit: '6px',
          borderRadius: '8px'
        }
      }
    });
    
    // Create and mount the Payment Element
    const paymentElement = elements.create('payment');
    paymentElement.mount('#stripe-payment-element');
    
    // Handle form submission
    const submitButton = document.getElementById('stripe-submit-button');
    if (submitButton) {
      submitButton.addEventListener('click', async (e) => {
        e.preventDefault();
        
        if (submitButton.disabled) return;
        
        // Disable submit button
        submitButton.disabled = true;
        
        try {
          const {error, paymentIntent} = await stripe.confirmPayment({
            elements,
            confirmParams: {
              return_url: window.location.href
            },
            redirect: 'if_required'
          });
          
          if (error) {
            console.error("Payment failed:", error);
            this.pushEvent("payment_failed", {error: error});
            submitButton.disabled = false;
          } else if (paymentIntent && paymentIntent.status === 'succeeded') {
            console.log("Payment succeeded:", paymentIntent);
            this.pushEvent("payment_succeeded", {payment_intent_id: paymentIntent.id});
          }
        } catch (err) {
          console.error("Payment error:", err);
          submitButton.disabled = false;
        }
      });
    }
    
    // Store references for cleanup
    this.stripe = stripe;
    this.elements = elements;
    this.paymentElement = paymentElement;
  },
  
  destroyed() {
    console.log("Stripe Payment Elements hook destroyed");
    if (this.paymentElement) {
      this.paymentElement.unmount();
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

// PostHog event tracking listener with enhanced error handling
window.addEventListener("phx:track_event", (e) => {
  if (e.detail) {
    const { event, properties } = e.detail;
    
    // Use the PostHogManager for better error handling and queueing
    posthogManager.capture(event, properties);
  }
});

// Expose PostHog manager for debugging and external use
window.posthogManager = posthogManager;

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
  
  // Initialize PostHog analytics with privacy checks
  posthogManager.showPrivacyBanner();
  posthogManager.init();
  
  // Initialize Supabase client
  initSupabaseClient();
});