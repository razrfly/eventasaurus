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
      
      // Only log initialization attempt if API key is present
      if (posthogApiKey) {
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
      }
      
      if (!posthogApiKey) {
        // Silently disable analytics when no API key is present
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

// LazyImage Hook for performance optimization of image loading
Hooks.LazyImage = {
  mounted() {
    this.observer = null;
    this.setupLazyLoading();
  },

  setupLazyLoading() {
    // Intersection Observer for lazy loading
    if ('IntersectionObserver' in window) {
      this.observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            this.loadImage(entry.target);
            this.observer.unobserve(entry.target);
          }
        });
      }, {
        rootMargin: '50px 0px', // Start loading 50px before entering viewport
        threshold: 0.1
      });

      this.observer.observe(this.el);
    } else {
      // Fallback for browsers without IntersectionObserver
      this.loadImage(this.el);
    }

    // Error handling
    this.el.addEventListener('error', () => {
      this.handleImageError();
    });

    // Success handling
    this.el.addEventListener('load', () => {
      this.handleImageLoad();
    });
  },

  loadImage(img) {
    const src = img.dataset.src;
    if (src && !img.src) {
      img.src = src;
      img.classList.add('loading');
    }
  },

  handleImageLoad() {
    this.el.classList.remove('loading');
    this.el.classList.add('loaded');
    
    // Remove loading placeholder if present
    const placeholder = document.getElementById('hero-loading-placeholder');
    if (placeholder) {
      placeholder.style.opacity = '0';
      setTimeout(() => placeholder.remove(), 300);
    }
  },

  handleImageError() {
    this.el.classList.remove('loading');
    this.el.classList.add('error');
    
    // Hide broken image
    this.el.style.display = 'none';
    
    // Add fallback background if parent has specific class
    const parent = this.el.parentElement;
    if (parent && parent.classList.contains('bg-gray-900')) {
      parent.classList.add('bg-gray-800');
    }
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
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
          
          // Also initialize PlacesSuggestionSearch hooks
          if (window.placeSuggestionHooks && Array.isArray(window.placeSuggestionHooks)) {
            window.placeSuggestionHooks.forEach(hook => {
              if (hook.mounted) {
                try {
                  setTimeout(() => hook.initPlacesAutocomplete(), 100);
                } catch (error) {
                  if (process.env.NODE_ENV !== 'production') console.error("Error initializing places autocomplete for hook:", error);
                }
              }
            });
            // Clear the list after initialization
            window.placeSuggestionHooks = [];
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

// TaxationTypeValidator hook for enhanced taxation type selection validation
Hooks.TaxationTypeValidator = {
  mounted() {
    this.setupValidation();
  },

  updated() {
    this.setupValidation();
  },

  setupValidation() {
    const radioButtons = this.el.querySelectorAll('input[type="radio"][name*="taxation_type"]');
    const helpTooltip = this.el.querySelector('[data-role="help-tooltip"]');
    const errorContainer = this.el.querySelector('[data-role="error-container"]');
    
    if (radioButtons.length === 0) return;

    // Add immediate feedback on radio button change
    radioButtons.forEach(radio => {
      radio.addEventListener('change', () => {
        this.validateSelection();
        this.showSelectionFeedback(radio.value);
      });

      // Add keyboard support for tooltip
      radio.addEventListener('keydown', (e) => {
        if (e.key === 'F1' || (e.ctrlKey && e.key === 'h')) {
          e.preventDefault();
          this.toggleTooltip();
        }
      });
    });

    // Validate on form submission attempt
    const form = this.el.closest('form');
    if (form) {
      form.addEventListener('submit', (e) => {
        if (!this.validateSelection()) {
          e.preventDefault();
          this.showValidationError('Please select a taxation classification for your event');
          return false;
        }
      });
    }

    // Initial validation
    this.validateSelection();
  },

  validateSelection() {
    const radioButtons = this.el.querySelectorAll('input[type="radio"][name*="taxation_type"]');
    const selectedRadio = Array.from(radioButtons).find(radio => radio.checked);
    const isValid = !!selectedRadio;

    // Update visual validation state
    this.updateValidationState(isValid);

    return isValid;
  },

  updateValidationState(isValid) {
    const fieldset = this.el.querySelector('fieldset');
    const errorContainer = this.el.querySelector('[data-role="error-container"]');

    if (fieldset) {
      if (isValid) {
        fieldset.classList.remove('border-red-500', 'bg-red-50');
        fieldset.classList.add('border-green-500', 'bg-green-50');
      } else {
        fieldset.classList.remove('border-green-500', 'bg-green-50');
        fieldset.classList.add('border-red-500', 'bg-red-50');
      }
    }

    if (errorContainer && !isValid) {
      this.showValidationError('This field is required');
    }
  },

  showSelectionFeedback(selectedValue) {
    // Clear any previous validation errors
    this.clearValidationError();

    // Show selection confirmation
    const confirmationContainer = this.el.querySelector('[data-role="confirmation-container"]');
    if (confirmationContainer) {
      const message = selectedValue === 'ticketed_event' 
        ? 'Selected: Ticketed Event - Standard event with paid tickets'
        : 'Selected: Contribution Collection - Donation-based event';
      
      confirmationContainer.innerHTML = `
        <div class="flex items-center gap-2 text-green-700 bg-green-50 p-2 rounded-md">
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"></path>
          </svg>
          <span class="text-sm font-medium">${message}</span>
        </div>
      `;
    }
  },

  showValidationError(message) {
    const errorContainer = this.el.querySelector('[data-role="error-container"]');
    if (errorContainer) {
      errorContainer.innerHTML = `
        <div class="flex items-center gap-2 text-red-700 bg-red-50 p-2 rounded-md" role="alert" aria-live="polite">
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
          </svg>
          <span class="text-sm font-medium">${message}</span>
        </div>
      `;
    }
  },

  clearValidationError() {
    const errorContainer = this.el.querySelector('[data-role="error-container"]');
    if (errorContainer) {
      errorContainer.innerHTML = '';
    }
  },

  toggleTooltip() {
    const helpTooltip = this.el.querySelector('[data-role="help-tooltip"]');
    if (helpTooltip) {
      const isVisible = !helpTooltip.classList.contains('hidden');
      if (isVisible) {
        helpTooltip.classList.add('hidden');
      } else {
        helpTooltip.classList.remove('hidden');
      }
    }
  }
};

// Poll Option Drag and Drop Hook
Hooks.PollOptionDragDrop = {
  mounted() {
    this.initialize();
  },

  updated() {
    // Re-initialize after LiveView updates the DOM
    this.initialize();
  },

  destroyed() {
    this.cleanupEventListeners();
  },

  initialize() {
    // Clean up any existing state first
    this.cleanupEventListeners();
    
    // Reset state
    this.originalOrder = null;
    this.draggedElement = null;
    this.touchStartY = 0;
    this.touchStartX = 0;
    this.touchElement = null;
    this.isDragging = false;
    this.hasMoved = false;
    this.touchTimeout = null;
    this.touchMoveThrottle = null;
    this.mobileDragIndicator = null;
    
    this.canReorder = this.el.dataset.canReorder === "true";
    
    if (!this.canReorder) {
      return; // Don't enable drag-and-drop if user can't reorder
    }
    
    this.setupDragAndDrop();
    this.setupTouchSupport();
    
    // Listen for rollback events from the server
    this.handleEvent("rollback_order", () => {
      this.rollbackOrder();
    });
  },

  setupDragAndDrop() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    
    items.forEach((item, index) => {
      // Make items draggable and add event listeners
      item.draggable = true;
      item.dataset.originalIndex = index;
      
      // Drag event listeners
      item.addEventListener('dragstart', this.handleDragStart.bind(this));
      item.addEventListener('dragend', this.handleDragEnd.bind(this));
      item.addEventListener('dragover', this.handleDragOver.bind(this));
      item.addEventListener('drop', this.handleDrop.bind(this));
      item.addEventListener('dragenter', this.handleDragEnter.bind(this));
      item.addEventListener('dragleave', this.handleDragLeave.bind(this));
    });
  },

  setupTouchSupport() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    
    items.forEach(item => {
      item.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: false });
      item.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: false });
      item.addEventListener('touchend', this.handleTouchEnd.bind(this), { passive: false });
    });
  },

  handleDragStart(e) {
    this.draggedElement = e.target.closest('[data-draggable="true"]');
    this.originalOrder = this.getCurrentOrder();
    
    // Add visual feedback
    this.draggedElement.classList.add('opacity-50', 'scale-95');
    
    // Set drag data
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/html', this.draggedElement.outerHTML);
    
    // Add drag image styling
    setTimeout(() => {
      this.draggedElement.classList.add('invisible');
    }, 0);
  },

  handleDragEnd(e) {
    // Clean up visual feedback
    this.draggedElement.classList.remove('opacity-50', 'scale-95', 'invisible');
    
    // Remove all drop indicators
    this.clearDropIndicators();
    
    this.draggedElement = null;
  },

  handleDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (dropTarget && dropTarget !== this.draggedElement) {
      this.showDropIndicator(dropTarget, e.clientY);
    }
  },

  handleDragEnter(e) {
    e.preventDefault();
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (dropTarget && dropTarget !== this.draggedElement) {
      dropTarget.classList.add('bg-blue-50', 'border-blue-200');
    }
  },

  handleDragLeave(e) {
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (dropTarget) {
      dropTarget.classList.remove('bg-blue-50', 'border-blue-200');
    }
  },

  handleDrop(e) {
    e.preventDefault();
    
    const dropTarget = e.target.closest('[data-draggable="true"]');
    if (!dropTarget || dropTarget === this.draggedElement) {
      return;
    }
    
    // Clean up visual feedback
    dropTarget.classList.remove('bg-blue-50', 'border-blue-200');
    this.clearDropIndicators();
    
    // Perform the reorder
    this.reorderElements(this.draggedElement, dropTarget);
  },

  // Touch support methods
  handleTouchStart(e) {
    if (e.touches.length !== 1) return;
    
    this.touchElement = e.target.closest('[data-draggable="true"]');
    this.touchStartY = e.touches[0].clientY;
    this.touchStartX = e.touches[0].clientX;
    this.hasMoved = false;
    this.originalOrder = this.getCurrentOrder();
    
    // Add visual feedback after a delay to distinguish from scrolling
    this.touchTimeout = setTimeout(() => {
      if (this.touchElement && !this.isDragging) {
        this.touchElement.classList.add('touch-dragging', 'scale-105', 'shadow-lg', 'z-50');
        this.isDragging = true;
        this.showMobileDragIndicator();
        
        // Provide haptic feedback if available
        if (navigator.vibrate) {
          navigator.vibrate(50);
        }
      }
    }, 150);
  },

  handleTouchMove(e) {
    if (!this.touchElement) return;
    
    const touch = e.touches[0];
    const deltaX = Math.abs(touch.clientX - this.touchStartX);
    const deltaY = Math.abs(touch.clientY - this.touchStartY);
    
    // Detect if this is a drag gesture vs scroll
    if (!this.hasMoved && (deltaX > 10 || deltaY > 10)) {
      this.hasMoved = true;
      
      // Cancel touch timeout if user starts scrolling horizontally
      if (deltaX > deltaY && this.touchTimeout) {
        clearTimeout(this.touchTimeout);
        return;
      }
    }
    
    if (!this.isDragging) return;
    
    e.preventDefault();
    
    // Throttle touch move for better performance
    if (!this.touchMoveThrottle) {
      this.touchMoveThrottle = setTimeout(() => {
        const elementUnderTouch = document.elementFromPoint(touch.clientX, touch.clientY);
        const dropTarget = elementUnderTouch?.closest('[data-draggable="true"]');
        
        if (dropTarget && dropTarget !== this.touchElement) {
          this.showDropIndicator(dropTarget, touch.clientY);
          this.updateMobileDragIndicator(dropTarget);
        } else {
          this.clearDropIndicators();
          this.updateMobileDragIndicator(null);
        }
        
        this.touchMoveThrottle = null;
      }, 16); // ~60fps
    }
  },

  handleTouchEnd(e) {
    // Clear timeout if touch ends before drag starts
    if (this.touchTimeout) {
      clearTimeout(this.touchTimeout);
      this.touchTimeout = null;
    }
    
    // Clear throttle timeout if active
    if (this.touchMoveThrottle) {
      clearTimeout(this.touchMoveThrottle);
      this.touchMoveThrottle = null;
    }
    
    if (!this.touchElement) return;
    
    let dropTarget = null;
    
    // Only check for drop target if we were actually dragging
    if (this.isDragging) {
      const touch = e.changedTouches[0];
      const elementUnderTouch = document.elementFromPoint(touch.clientX, touch.clientY);
      dropTarget = elementUnderTouch?.closest('[data-draggable="true"]');
      
      // Clean up visual feedback
      this.touchElement.classList.remove('touch-dragging', 'scale-105', 'shadow-lg', 'z-50');
      this.clearDropIndicators();
      this.hideMobileDragIndicator();
      
      // Perform reorder if valid drop target
      if (dropTarget && dropTarget !== this.touchElement) {
        this.reorderElements(this.touchElement, dropTarget);
        
        // Provide success feedback
        if (navigator.vibrate) {
          navigator.vibrate([30, 10, 30]);
        }
      }
    }
    
    // Reset touch state
    this.touchElement = null;
    this.isDragging = false;
    this.hasMoved = false;
  },

  reorderElements(draggedElement, dropTarget) {
    const draggedId = draggedElement.dataset.optionId;
    const dropTargetId = dropTarget.dataset.optionId;
    const draggedIndex = parseInt(draggedElement.dataset.originalIndex);
    const dropTargetIndex = parseInt(dropTarget.dataset.originalIndex);
    
    if (!draggedId || !dropTargetId || draggedId === dropTargetId) {
      return;
    }
    
    // Optimistically update the DOM
    this.updateDOMOrder(draggedElement, dropTarget, draggedIndex < dropTargetIndex);
    
    // Send update to server - target the LiveView component using proper targeting
    this.pushEventTo(this.el, 'reorder_option', {
      dragged_option_id: draggedId,
      target_option_id: dropTargetId,
      direction: draggedIndex < dropTargetIndex ? 'after' : 'before',
      original_order: this.originalOrder
    });
  },

  updateDOMOrder(draggedElement, dropTarget, insertAfter) {
    if (insertAfter) {
      dropTarget.parentNode.insertBefore(draggedElement, dropTarget.nextSibling);
    } else {
      dropTarget.parentNode.insertBefore(draggedElement, dropTarget);
    }
    
    // Update data attributes for proper tracking
    this.updateItemIndices();
  },

  updateItemIndices() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    items.forEach((item, index) => {
      item.dataset.originalIndex = index;
    });
  },

  showDropIndicator(element, clientY) {
    this.clearDropIndicators();
    
    const rect = element.getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;
    const isAbove = clientY < midpoint;
    
    const indicator = document.createElement('div');
    indicator.className = 'drop-indicator absolute left-0 right-0 h-1 bg-blue-400 rounded-full z-10 transition-all duration-150';
    indicator.style.pointerEvents = 'none';
    
    if (isAbove) {
      indicator.style.top = '-2px';
      element.style.position = 'relative';
      element.appendChild(indicator);
    } else {
      indicator.style.bottom = '-2px';
      element.style.position = 'relative';
      element.appendChild(indicator);
    }
  },

  clearDropIndicators() {
    const indicators = this.el.querySelectorAll('.drop-indicator');
    indicators.forEach(indicator => indicator.remove());
    
    // Remove highlighting
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    items.forEach(item => {
      item.classList.remove('bg-blue-50', 'border-blue-200');
    });
  },

  getCurrentOrder() {
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    return Array.from(items).map(item => ({
      id: item.dataset.optionId,
      index: parseInt(item.dataset.originalIndex)
    }));
  },

  // Called by LiveView when reorder fails - rollback the DOM changes
  rollbackOrder() {
    if (!this.originalOrder) return;
    
    const container = this.el.querySelector('[data-role="options-container"]');
    if (!container) return;
    
    // Reorder DOM elements to match original order
    this.originalOrder
      .sort((a, b) => a.index - b.index)
      .forEach(item => {
        const element = container.querySelector(`[data-option-id="${item.id}"]`);
        if (element) {
          container.appendChild(element);
        }
      });
    
    this.updateItemIndices();
    this.originalOrder = null;
  },

  // Mobile drag indicator methods
  showMobileDragIndicator() {
    if (this.mobileDragIndicator) return;
    
    this.mobileDragIndicator = document.createElement('div');
    this.mobileDragIndicator.className = 'mobile-drag-indicator';
    this.mobileDragIndicator.textContent = 'Drag to reorder • Release to drop';
    document.body.appendChild(this.mobileDragIndicator);
  },
  
  updateMobileDragIndicator(dropTarget) {
    if (!this.mobileDragIndicator) return;
    
    if (dropTarget) {
      this.mobileDragIndicator.textContent = 'Release to place here';
      this.mobileDragIndicator.style.backgroundColor = '#10b981';
    } else {
      this.mobileDragIndicator.textContent = 'Drag to reorder • Release to drop';
      this.mobileDragIndicator.style.backgroundColor = '#1f2937';
    }
    },
    
  hideMobileDragIndicator() {
    if (this.mobileDragIndicator) {
      this.mobileDragIndicator.remove();
      this.mobileDragIndicator = null;
    }
  },

  cleanupEventListeners() {
    // Clear any pending timeouts
    if (this.touchTimeout) {
      clearTimeout(this.touchTimeout);
      this.touchTimeout = null;
    }
    if (this.touchMoveThrottle) {
      clearTimeout(this.touchMoveThrottle);
      this.touchMoveThrottle = null;
    }
    
    // Clean up mobile indicator
    this.hideMobileDragIndicator();
    
    // Clear drop indicators
    this.clearDropIndicators();
    
    // Remove all event listeners from draggable items
    const items = this.el.querySelectorAll('[data-draggable="true"]');
    items.forEach(item => {
      // Remove drag event listeners
      item.removeEventListener('dragstart', this.handleDragStart);
      item.removeEventListener('dragend', this.handleDragEnd);
      item.removeEventListener('dragover', this.handleDragOver);
      item.removeEventListener('drop', this.handleDrop);
      item.removeEventListener('dragenter', this.handleDragEnter);
      item.removeEventListener('dragleave', this.handleDragLeave);
      
      // Remove touch event listeners
      item.removeEventListener('touchstart', this.handleTouchStart);
      item.removeEventListener('touchmove', this.handleTouchMove);
      item.removeEventListener('touchend', this.handleTouchEnd);
      
      // Clean up visual state
      item.classList.remove('touch-dragging', 'scale-105', 'shadow-lg', 'z-50', 'opacity-50', 'scale-95', 'invisible', 'bg-blue-50', 'border-blue-200');
    });
  }
};

// Cast Carousel Keyboard Navigation Hook
Hooks.CastCarouselKeyboard = {
  mounted() {
    this.handleKeydown = this.handleKeydown.bind(this);
    this.el.addEventListener('keydown', this.handleKeydown);
    
    // Add focus styling
    this.el.addEventListener('focus', () => {
      this.el.style.outline = '2px solid #4F46E5';
      this.el.style.outlineOffset = '2px';
    });
    
    this.el.addEventListener('blur', () => {
      this.el.style.outline = 'none';
    });
  },

  destroyed() {
    this.el.removeEventListener('keydown', this.handleKeydown);
  },

  handleKeydown(event) {
    const componentId = this.el.dataset.componentId;
    
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      this.pushEvent('scroll_left', {}, componentId);
    } else if (event.key === 'ArrowRight') {
      event.preventDefault();
      this.pushEvent('scroll_right', {}, componentId);
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

// Cast Carousel Scroll Handler
window.addEventListener("phx:scroll_cast_carousel", (e) => {
  const { target, direction, amount } = e.detail;
  const carousel = document.getElementById(target);
  
  if (carousel) {
    const scrollAmount = direction === "left" ? -amount : amount;
    carousel.scrollBy({
      left: scrollAmount,
      behavior: "smooth"
    });
  }
});

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
  
  // Initialize Stagewise toolbar in development mode
  if (process.env.NODE_ENV === 'development') {
    import('@stagewise/toolbar').then(({ initToolbar }) => {
      initToolbar({
        plugins: [],
      });
    }).catch(err => {
      console.log('Stagewise toolbar not available:', err);
    });
  }
});

// Google Places Autocomplete Hook for Poll Option Suggestions
Hooks.PlacesSuggestionSearch = {
  mounted() {
    if (process.env.NODE_ENV !== 'production') console.log("PlacesSuggestionSearch hook mounted on element:", this.el.id);
    this.inputEl = this.el;
    this.mounted = true;
    this.autocomplete = null;
    this.currentLocation = null;
    this.selectedCity = null;
    this.selectedPlaceData = null;
    
    // Initialize Google Places immediately
    this.initGooglePlaces();
    
    // Attempt to get user location for search biasing (privacy-first approach)
    this.initGeolocation();
    
    // Initialize city selector functionality
    this.initCitySelector();
    
    // Listen for form submissions to include place metadata
    this.setupFormSubmissionHandler();
  },
  
  destroyed() {
    this.mounted = false;
    
    // Clean up form submission handler
    if (this.formSubmitHandler) {
      const form = this.el.closest('form');
      if (form) {
        form.removeEventListener('submit', this.formSubmitHandler);
      }
    }
    
    // Clean up recent city data to prevent memory leaks
    if (this.recentCityData) {
      this.recentCityData.clear();
    }
    
    // Remove this hook from the waiting list if it exists
    if (window.placeSuggestionHooks && Array.isArray(window.placeSuggestionHooks)) {
      const index = window.placeSuggestionHooks.indexOf(this);
      if (index > -1) {
        window.placeSuggestionHooks.splice(index, 1);
      }
    }
    
    if (process.env.NODE_ENV !== 'production') console.log("PlacesSuggestionSearch hook destroyed");
  },
  
  initCitySelector() {
    if (!this.mounted) return;
    
    // Set up city selector dropdown if it exists
    this.cityDropdown = document.querySelector('.city-selector-dropdown');
    this.cityInput = document.querySelector('.city-selector-input');
    this.recentCitiesContainer = document.querySelector('.recent-cities-container');
    
    if (this.cityInput) {
      // Set up city autocomplete
      this.setupCityAutocomplete();
      
      // Load and display recent cities
      this.loadRecentCities();
      
      // Set up event handlers
      this.cityInput.addEventListener('focus', () => this.showCityDropdown());
      this.cityInput.addEventListener('blur', (e) => {
        // Delay hiding to allow for clicks on dropdown items
        setTimeout(() => this.hideCityDropdown(), 150);
      });
    }
  },
  
  setupCityAutocomplete() {
    if (!this.cityInput) return;
    
    // Wait for Google Maps to be loaded
    if (window.google && google.maps && google.maps.places) {
      this.initCityAutocomplete();
    } else {
      // Wait for Google Maps to load
      const checkGoogleMaps = setInterval(() => {
        if (window.google && google.maps && google.maps.places) {
          clearInterval(checkGoogleMaps);
          this.initCityAutocomplete();
        }
      }, 100);
    }
  },
  
  initCityAutocomplete() {
    if (!this.cityInput || this.cityAutocomplete) return;
    
    try {
      // Create autocomplete specifically for cities
      this.cityAutocomplete = new google.maps.places.Autocomplete(this.cityInput, {
        types: ['(cities)'], // Restrict to cities only
        fields: ['name', 'formatted_address', 'geometry', 'place_id']
      });
      
      // Handle city selection
      this.cityAutocomplete.addListener('place_changed', () => {
        const place = this.cityAutocomplete.getPlace();
        if (place && place.geometry) {
          this.selectCity(place);
        }
      });
      
      if (process.env.NODE_ENV !== 'production') console.log("City autocomplete initialized");
    } catch (error) {
      if (process.env.NODE_ENV !== 'production') console.error("Error initializing city autocomplete:", error);
    }
  },
  
  selectCity(place) {
    if (!place || !place.geometry) return;
    
    const cityData = {
      name: place.name,
      formatted_address: place.formatted_address,
      place_id: place.place_id,
      lat: place.geometry.location.lat(),
      lng: place.geometry.location.lng()
    };
    
    // Update selected city and location bias
    this.selectedCity = cityData;
    this.currentLocation = {
      lat: cityData.lat,
      lng: cityData.lng
    };
    
    // Apply new location bias to places search
    if (this.autocomplete) {
      this.applyLocationBias();
    }
    
    // Save to recent cities
    this.saveRecentCity(cityData);
    
    // Update UI
    this.updateCityDisplay();
    this.hideCityDropdown();
    
    if (process.env.NODE_ENV !== 'production') console.log("City selected:", cityData);
  },
  
    saveRecentCity(cityData) {
    try {
      const recentCities = this.getRecentCities();

      // Remove if already exists (to avoid duplicates)
      const filtered = recentCities.filter(city => city.place_id !== cityData.place_id);

      // Add to front and limit to 5 cities
      const updated = [cityData, ...filtered].slice(0, 5);

      try {
        localStorage.setItem('eventasaurus_recent_cities', JSON.stringify(updated));
      } catch (e) {
        // Handle quota exceeded error
        if (e.name === 'QuotaExceededError') {
          if (process.env.NODE_ENV !== 'production') console.warn("localStorage quota exceeded, clearing old data");
          // Clear old data and retry with fewer items
          localStorage.removeItem('eventasaurus_recent_cities');
          localStorage.setItem('eventasaurus_recent_cities', JSON.stringify(updated.slice(0, 3)));
        } else {
          throw e;
        }
      }

      // Update recent cities display
      this.loadRecentCities();
    } catch (error) {
      if (process.env.NODE_ENV !== 'production') console.error("Error saving recent city:", error);
    }
  },
  
  getRecentCities() {
    try {
      const stored = localStorage.getItem('eventasaurus_recent_cities');
      return stored ? JSON.parse(stored) : [];
    } catch (error) {
      if (process.env.NODE_ENV !== 'production') console.error("Error loading recent cities:", error);
      return [];
    }
  },
  
  loadRecentCities() {
    if (!this.recentCitiesContainer) return;
    
    const recentCities = this.getRecentCities();
    
    if (recentCities.length === 0) {
      this.recentCitiesContainer.innerHTML = '<div class="text-sm text-gray-500 p-2">No recent cities</div>';
      return;
    }
    
    const citiesHtml = recentCities.map((city, index) => {
      // Store city data in a Map instead of HTML attributes for security
      this.recentCityData = this.recentCityData || new Map();
      this.recentCityData.set(index.toString(), city);
      
      return `
        <button type="button" 
                class="recent-city-btn w-full text-left px-3 py-2 text-sm hover:bg-indigo-50 hover:text-indigo-600 transition-colors"
                data-city-index="${index}">
          <div class="font-medium">${this.escapeHtml(city.name)}</div>
          <div class="text-xs text-gray-500">${this.escapeHtml(city.formatted_address)}</div>
        </button>
      `;
    }).join('');
    
    this.recentCitiesContainer.innerHTML = citiesHtml;
    
    // Add click handlers for recent cities
    this.recentCitiesContainer.querySelectorAll('.recent-city-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        try {
          const cityIndex = e.currentTarget.dataset.cityIndex;
          const cityData = this.recentCityData && this.recentCityData.get(cityIndex);
          if (cityData) {
            this.selectCityFromRecent(cityData);
          }
        } catch (error) {
          if (process.env.NODE_ENV !== 'production') console.error("Error selecting recent city:", error);
        }
      });
    });
  },
  
  selectCityFromRecent(cityData) {
    // Update selected city and location bias
    this.selectedCity = cityData;
    this.currentLocation = {
      lat: cityData.lat,
      lng: cityData.lng
    };
    
    // Apply location bias
    if (this.autocomplete) {
      this.applyLocationBias();
    }
    
    // Update city input value
    if (this.cityInput) {
      this.cityInput.value = cityData.name;
    }
    
    // Save as recent (moves to front)
    this.saveRecentCity(cityData);
    
    // Update UI
    this.updateCityDisplay();
    this.hideCityDropdown();
    
    if (process.env.NODE_ENV !== 'production') console.log("Recent city selected:", cityData);
  },
  
  updateCityDisplay() {
    // Update any city display elements
    const cityDisplay = document.querySelector('.city-display');
    if (cityDisplay && this.selectedCity) {
      cityDisplay.textContent = `Searching near ${this.selectedCity.name}`;
      cityDisplay.classList.remove('hidden');
    }
  },
  
  showCityDropdown() {
    if (this.cityDropdown) {
      this.cityDropdown.classList.remove('hidden');
      this.loadRecentCities(); // Refresh recent cities
    }
  },
  
  hideCityDropdown() {
    if (this.cityDropdown) {
      this.cityDropdown.classList.add('hidden');
    }
  },
  
  initGeolocation() {
    if (!this.mounted) return;
    
    // Check if geolocation is available (following timezone detection pattern)
    if (navigator.geolocation) {
      if (process.env.NODE_ENV !== 'production') console.log("Attempting to get user location for place search biasing");
      
      // Use getCurrentPosition with no permission prompts (privacy-first)
      navigator.geolocation.getCurrentPosition(
        (position) => {
          if (!this.mounted) return;
          
          // Only use geolocation if no city is manually selected
          if (!this.selectedCity) {
            this.currentLocation = {
              lat: position.coords.latitude,
              lng: position.coords.longitude
            };
            
            if (process.env.NODE_ENV !== 'production') console.log("Location detected for place search biasing:", this.currentLocation);
            
            // Re-initialize autocomplete with location bias if already created
            if (this.autocomplete) {
              this.applyLocationBias();
            }
          }
        },
        (error) => {
          if (!this.mounted) return;
          
          // Graceful fallback - no location bias (following timezone pattern)
          if (process.env.NODE_ENV !== 'production') console.log("Geolocation not available, using global search:", error.message);
          this.currentLocation = null;
        },
        {
          // Privacy-first settings - no prompts, quick timeout
          enableHighAccuracy: false,
          timeout: 5000,
          maximumAge: 600000 // 10 minutes cache
        }
      );
    } else {
      if (process.env.NODE_ENV !== 'production') console.log("Geolocation not supported, using global search");
      this.currentLocation = null;
    }
  },
  
  applyLocationBias() {
    if (!this.autocomplete || !this.currentLocation) return;
    
    try {
      // Create location bias using current location (either geolocation or selected city)
      const center = new google.maps.LatLng(this.currentLocation.lat, this.currentLocation.lng);
      const radius = 50000; // 50km radius for local bias
      
      // Create circular bias area
      const circle = new google.maps.Circle({
        center: center,
        radius: radius
      });
      
      // Apply location bias to autocomplete
      this.autocomplete.setBounds(circle.getBounds());
      
      const source = this.selectedCity ? `selected city (${this.selectedCity.name})` : 'detected location';
      if (process.env.NODE_ENV !== 'production') console.log(`Applied location bias from ${source}:`, this.currentLocation);
    } catch (error) {
      if (process.env.NODE_ENV !== 'production') console.error("Error applying location bias:", error);
    }
  },
  
  initGooglePlaces() {
    if (!this.mounted) return;
    
    // Check if Google Maps API is loaded and ready
    if (window.google && google.maps && google.maps.places) {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps loaded, initializing places autocomplete");
      setTimeout(() => this.initPlacesAutocomplete(), 100);
    } else {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps not yet loaded, will initialize when ready");
      // Add this hook to the list of hooks waiting for Google Maps to load
      if (!window.placeSuggestionHooks) {
        window.placeSuggestionHooks = [];
      }
      
      // Ensure this hook isn't already in the list to prevent duplicates
      if (!window.placeSuggestionHooks.includes(this)) {
        window.placeSuggestionHooks.push(this);
      }
      
      // Set up the global callback for when Google Maps loads (only once)
      if (!window.initGooglePlacesForSuggestions) {
        window.initGooglePlacesForSuggestions = () => {
          if (window.placeSuggestionHooks && Array.isArray(window.placeSuggestionHooks)) {
            window.placeSuggestionHooks.forEach(hook => {
              if (hook.mounted) {
                try {
                  setTimeout(() => hook.initPlacesAutocomplete(), 100);
                } catch (error) {
                  if (process.env.NODE_ENV !== 'production') console.error("Error initializing places autocomplete for hook:", error);
                }
              }
            });
            // Clear the list after initialization
            window.placeSuggestionHooks = [];
          }
        };
      }
    }
  },
  
  // Google Places Autocomplete initialization for place suggestions
  initPlacesAutocomplete() {
    if (!this.mounted) return;
    
    try {
      if (process.env.NODE_ENV !== 'production') console.log("Initializing Google Places Autocomplete for suggestions");
      
      // Prevent creating multiple instances
      if (this.autocomplete) {
        if (process.env.NODE_ENV !== 'production') console.log("Places autocomplete already initialized");
        return;
      }
      
      // Create the autocomplete object with broader place types for "places" poll type
      // Using 'establishment' alone to support all business types (restaurants, shops, venues, etc.)
      // Note: 'establishment' cannot be mixed with other types per Google Maps API restrictions
      const options = {
        types: ['establishment']
      };
      
      this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
      
      // Apply location bias if available
      if (this.currentLocation) {
        this.applyLocationBias();
      }
      
      // When a place is selected from Google Places
      this.autocomplete.addListener('place_changed', () => {
        if (!this.mounted) return;
        
        if (process.env.NODE_ENV !== 'production') console.group("Google Places selection process for suggestions");
        const place = this.autocomplete.getPlace();
        if (process.env.NODE_ENV !== 'production') console.log("Place selected:", place);
        
        if (!place.geometry) {
          if (process.env.NODE_ENV !== 'production') console.error("No place geometry received");
          if (process.env.NODE_ENV !== 'production') console.groupEnd();
          // Notify user of incomplete selection
          this.pushEvent('place_selection_error', { error: 'Invalid place selected. Please try again.' });
          return;
        }
        
        // Validate required fields
        if (!place.name) {
          if (process.env.NODE_ENV !== 'production') console.error("No place name received");
          this.pushEvent('place_selection_error', { error: 'Selected place has no name. Please try again.' });
          return;
        }
        
        // Get place details
        const placeName = place.name || '';
        const placeAddress = place.formatted_address || '';
        let city = '', state = '', country = '';
        
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
        
        // Get coordinates (rounded to 4 decimal places for privacy)
        let lat = null, lng = null;
        if (place.geometry?.location) {
          lat = Math.round(place.geometry.location.lat() * 10000) / 10000;
          lng = Math.round(place.geometry.location.lng() * 10000) / 10000;
        }
        
        // Store place data for form submission instead of auto-submitting
        this.selectedPlaceData = {
          title: placeName,
          address: placeAddress,
          city: city,
          state: state,
          country: country,
          latitude: lat,
          longitude: lng,
          place_id: place.place_id || '',
          rating: place.rating || null,
          price_level: place.price_level || null,
          phone: place.formatted_phone_number || '',
          website: place.website || '',
          photos: place.photos ? place.photos.slice(0, 3).map(photo => photo.getUrl({maxWidth: 400})) : []
        };
        
        // Populate form fields instead of auto-submitting
        this.populateFormFields(placeName, placeAddress);
        
        // Close the Google Places dropdown after selection
        this.closePlacesDropdown();
        
        if (process.env.NODE_ENV !== 'production') console.log("Form fields populated with place data:", this.selectedPlaceData);
        if (process.env.NODE_ENV !== 'production') console.groupEnd();
      });
      
      if (process.env.NODE_ENV !== 'production') console.log("Google Places Autocomplete for suggestions initialized");
    } catch (error) {
      if (process.env.NODE_ENV !== 'production') console.error("Error in Google Places Autocomplete initialization:", error);
      // Notify the server that Places API is unavailable
      this.pushEvent('places_api_unavailable', { error: error.message });
      // Optionally fall back to manual input
      this.inputEl.placeholder = "Enter place name manually...";
    }
  },
  
  // Populate form fields with selected place data
  populateFormFields(placeName, placeAddress) {
    // Find form fields in the modal
    const titleInput = document.querySelector('input[name="poll_option[title]"]');
    const descriptionInput = document.querySelector('textarea[name="poll_option[description]"]');
    
    if (titleInput) {
      titleInput.value = placeName;
      titleInput.dispatchEvent(new Event('input', { bubbles: true }));
    }
    
    if (descriptionInput && placeAddress && placeAddress !== placeName) {
      descriptionInput.value = placeAddress;
      descriptionInput.dispatchEvent(new Event('input', { bubbles: true }));
    }
    
    if (process.env.NODE_ENV !== 'production') console.log("Form fields populated:", { title: placeName, description: placeAddress });
  },
  
  // Close the Google Places dropdown after selection
  closePlacesDropdown() {
    if (this.inputEl) {
      // Clear the input field to close the dropdown
      this.inputEl.value = '';
      this.inputEl.blur();
      
      // Also trigger input event to ensure proper cleanup
      this.inputEl.dispatchEvent(new Event('input', { bubbles: true }));
    }
    
    if (process.env.NODE_ENV !== 'production') console.log("Google Places dropdown closed");
  },
  
  // HTML escape helper to prevent XSS
  escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },
  
  // Setup form submission handler to include place metadata
  setupFormSubmissionHandler() {
    const form = this.el.closest('form');
    if (form) {
      this.formSubmitHandler = (event) => {
        if (this.selectedPlaceData) {
          // Add place metadata as hidden inputs before form submission
          this.addPlaceMetadataToForm(form);
        }
      };
      form.addEventListener('submit', this.formSubmitHandler);
    }
  },
  
  // Add place metadata as hidden form inputs
  addPlaceMetadataToForm(form) {
    // Remove any existing place-related inputs to avoid duplicates
    const existingInputs = form.querySelectorAll('input[name*="external_data"], input[name*="external_id"], input[name*="metadata"]');
    existingInputs.forEach(input => input.remove());
    
    // Add place data using the consistent external API pattern (same as movies)
    const placeData = this.selectedPlaceData;
    if (placeData) {
      // Create external_id following the "places:place_id" pattern
      const externalIdInput = document.createElement('input');
      externalIdInput.type = 'hidden';
      externalIdInput.name = 'poll_option[external_id]';
      externalIdInput.value = `places:${placeData.place_id}`;
      form.appendChild(externalIdInput);
      
      // Create external_data with complete Google Places data
      const externalDataInput = document.createElement('input');
      externalDataInput.type = 'hidden';
      externalDataInput.name = 'poll_option[external_data]';
      externalDataInput.value = JSON.stringify(placeData);
      form.appendChild(externalDataInput);
      
      // Create image_url if we have photos
      if (placeData.photos && placeData.photos.length > 0) {
        const imageUrlInput = document.createElement('input');
        imageUrlInput.type = 'hidden';
        imageUrlInput.name = 'poll_option[image_url]';
        imageUrlInput.value = placeData.photos[0]; // First photo URL
        form.appendChild(imageUrlInput);
      }
      
      if (process.env.NODE_ENV !== 'production') console.log("Added place data using external_id/external_data pattern");
    }
  }
};