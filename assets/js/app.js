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
        
        // Disable autocapture to prevent duplicate tracking with our custom events
        // We track specific poll interactions manually for better control
        autocapture: false,
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

// ModalCleanup hook to ensure overflow-hidden is removed when modal closes
Hooks.ModalCleanup = {
  mounted() {
    // Store the original overflow style
    this.originalOverflow = document.body.style.overflow;
    
    // Watch for changes to the modal's visibility
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'attributes' && 
            (mutation.attributeName === 'class' || mutation.attributeName === 'style')) {
          this.checkModalState();
        }
      });
    });
    
    // Start observing the modal element
    this.observer.observe(this.el, { 
      attributes: true, 
      attributeFilter: ['class', 'style'] 
    });
    
    // Initial check
    this.checkModalState();
  },
  
  checkModalState() {
    const isHidden = this.el.classList.contains('hidden') || 
                     this.el.style.display === 'none' ||
                     !this.el.offsetParent;
    
    if (isHidden) {
      // Modal is hidden, ensure overflow-hidden is removed
      document.body.classList.remove('overflow-hidden');
      document.body.style.overflow = this.originalOverflow || '';
    }
  },
  
  destroyed() {
    // Clean up when the hook is destroyed
    if (this.observer) {
      this.observer.disconnect();
    }
    // Ensure overflow-hidden is removed
    document.body.classList.remove('overflow-hidden');
    document.body.style.overflow = this.originalOverflow || '';
  },
  
  reconnected() {
    // Ensure cleanup on reconnection
    this.checkModalState();
  },
  
  disconnected() {
    // Ensure cleanup on disconnection
    document.body.classList.remove('overflow-hidden');
    document.body.style.overflow = this.originalOverflow || '';
  }
};

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

// FocusTrap Hook for modal focus management
Hooks.FocusTrap = {
  mounted() {
    // Store the previously focused element
    this.previouslyFocused = document.activeElement;
    
    this.FOCUSABLE_SELECTOR =
      'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';
    this.focusableElements = this.getFocusableElements();

    if (this.focusableElements.length > 0) {
      this.focusableElements[0].focus();
    } else {
      // Make container focusable and focus it as a fallback
      if (!this.el.hasAttribute('tabindex')) this.el.setAttribute('tabindex', '-1');
      this.el.focus();
    }

    // Add keydown listener for Tab navigation
    this.handleKeyDown = (e) => {
      if (e.key === 'Tab') {
        this.trapFocus(e);
      }
    };

    this.el.addEventListener('keydown', this.handleKeyDown);
  },

  updated() {
    // Recompute after LiveView updates modal content
    this.focusableElements = this.getFocusableElements();
  },

  destroyed() {
    // Remove event listener
    if (this.handleKeyDown) {
      this.el.removeEventListener('keydown', this.handleKeyDown);
    }

    // Restore focus to the previously focused element
    if (this.previouslyFocused && this.previouslyFocused.focus) {
      this.previouslyFocused.focus();
    }
  },

  trapFocus(e) {
    this.focusableElements = this.getFocusableElements();
    if (this.focusableElements.length === 0) return;

    const firstFocusable = this.focusableElements[0];
    const lastFocusable = this.focusableElements[this.focusableElements.length - 1];

    if (e.shiftKey) {
      // Shift + Tab
      if (document.activeElement === firstFocusable) {
        e.preventDefault();
        lastFocusable.focus();
      }
    } else {
      // Tab
      if (document.activeElement === lastFocusable) {
        e.preventDefault();
        firstFocusable.focus();
      }
    }
  },

  getFocusableElements() {
    return Array.from(
      this.el.querySelectorAll(this.FOCUSABLE_SELECTOR + ', [contenteditable=""], [contenteditable="true"]')
    ).filter(el => {
      const style = window.getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      const notHidden = style.visibility !== 'hidden' && style.display !== 'none';
      const hasSize = rect.width > 0 && rect.height > 0;

      // Element itself is not aria-hidden or hidden
      const notAriaHiddenSelf = el.getAttribute('aria-hidden') !== 'true' && !el.hasAttribute('hidden');

      // No inert or aria-hidden ancestors
      const inertAncestor = el.closest('[inert]');
      const ariaHiddenAncestor = el.closest('[aria-hidden="true"]');

      return notHidden && hasSize && notAriaHiddenSelf && !inertAncestor && !ariaHiddenAncestor;
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

// Event Location Search Hook - Native Google Places Autocomplete (modular & simplified)
Hooks.EventLocationSearch = {
  mounted() {
    this.inputEl = this.el;
    this.debounceTimeout = null;
    this.autocomplete = null;
    this.hasSelectedPlace = false;
    this.initRetryHandle = null;
    
    // Initialize Google Places Autocomplete
    this.initAutocomplete();
    
    // Add input listener for filtering recent locations
    this.inputEl.addEventListener('input', (e) => {
      const query = e.target.value.trim();
      
      // Debounce the filtering
      if (this.debounceTimeout) {
        clearTimeout(this.debounceTimeout);
      }
      
      this.debounceTimeout = setTimeout(() => {
        // Filter recent locations for dropdown
        if (query.length >= 2) {
          this.pushEvent('filter_recent_locations', { query: query });
          // Ensure dropdown is visible while filtering
          this.pushEvent('show_recent_locations', {});
        }
      }, 150);
      
      // If user is editing after a selection, clear hidden fields to avoid stale data
      if (this.hasSelectedPlace) {
        const idSuffix = this.inputEl.id.split('-').pop();
        this.clearHiddenVenueFields(idSuffix);
        this.hasSelectedPlace = false;
      }
    });
    
    // Show recent locations on focus if input is empty
    this.inputEl.addEventListener('focus', () => {
      if (this.inputEl.value.trim().length === 0) {
        this.pushEvent('show_recent_locations', {});
      }
    });
    
    // Hide recent locations when clicking outside
    this.documentClickHandler = (e) => {
      if (e.target && !this.inputEl.contains(e.target) && !e.target.closest('.recent-locations-dropdown')) {
        this.pushEvent('hide_recent_locations', {});
      }
    };
    document.addEventListener('click', this.documentClickHandler);
  },
  
  destroyed() {
    // Clean up autocomplete
    if (this.autocomplete) {
      google.maps.event.clearInstanceListeners(this.autocomplete);
      this.autocomplete = null;
    }
    
    // Clear debounce timeout
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout);
    }
    
    // Remove document click handler
    if (this.documentClickHandler) {
      document.removeEventListener('click', this.documentClickHandler);
    }
    
    // Cancel any pending init retries
    if (this.initRetryHandle) {
      clearTimeout(this.initRetryHandle);
      this.initRetryHandle = null;
    }
  },
  
  initAutocomplete() {
    // Wait for Google Maps to load
    if (!window.google?.maps?.places) {
      this.initRetryHandle = setTimeout(() => this.initAutocomplete(), 100);
      return;
    }
    
    // Configure autocomplete for venues and addresses
    const options = {
      types: ['establishment', 'geocode'],
      fields: [
        'place_id',
        'name',
        'formatted_address',
        'geometry',
        'address_components'
      ]
    };
    
    // Create autocomplete instance
    this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
    
    // Handle place selection
    this.autocomplete.addListener('place_changed', () => {
      this.handlePlaceSelection();
    });
  },
  
  handlePlaceSelection() {
    const place = this.autocomplete.getPlace();
    
    if (!place?.geometry) {
      return;
    }
    
    // Mark that a place has been selected
    this.hasSelectedPlace = true;
    
    // Extract venue information
    const venueName = place.name || '';
    const venueAddress = place.formatted_address || '';
    
    // Extract address components
    let city = '', state = '', country = '';
    
    if (place.address_components) {
      for (const component of place.address_components) {
        const types = component.types;
        if (types.includes('locality')) {
          city = component.long_name;
        } else if (types.includes('administrative_area_level_1')) {
          state = component.long_name;
        } else if (types.includes('country')) {
          country = component.long_name;
        }
      }
    }
    
    // Extract coordinates
    const lat = Math.round(place.geometry.location.lat() * 10000) / 10000;
    const lng = Math.round(place.geometry.location.lng() * 10000) / 10000;
    
    // Get ID suffix from input element
    const idSuffix = this.inputEl.id.split('-').pop(); // "new" or "edit"
    
    // Update hidden fields
    this.setHiddenField(`venue-name-${idSuffix}`, venueName);
    this.setHiddenField(`venue-address-${idSuffix}`, venueAddress);
    this.setHiddenField(`venue-city-${idSuffix}`, city);
    this.setHiddenField(`venue-state-${idSuffix}`, state);
    this.setHiddenField(`venue-country-${idSuffix}`, country);
    this.setHiddenField(`venue-lat-${idSuffix}`, lat);
    this.setHiddenField(`venue-lng-${idSuffix}`, lng);
    
    // Update display
    this.inputEl.value = venueName ? `${venueName}, ${city || venueAddress}` : venueAddress;
    
    // Send to LiveView
    const venueData = {
      name: venueName,
      address: venueAddress,
      city: city,
      state: state,
      country: country,
      latitude: lat,
      longitude: lng
    };
    
    this.pushEvent('venue_selected', venueData);
    this.pushEvent('hide_recent_locations', {});
  },
  
  setHiddenField(id, value) {
    const field = document.getElementById(id);
    if (field) {
      field.value = value || '';
      field.dispatchEvent(new Event('input', { bubbles: true }));
      field.dispatchEvent(new Event('change', { bubbles: true }));
    }
  },
  
  clearHiddenVenueFields(idSuffix) {
    const ids = [
      `venue-name-${idSuffix}`,
      `venue-address-${idSuffix}`,
      `venue-city-${idSuffix}`,
      `venue-state-${idSuffix}`,
      `venue-country-${idSuffix}`,
      `venue-lat-${idSuffix}`,
      `venue-lng-${idSuffix}`
    ];
    ids.forEach(id => this.setHiddenField(id, ''));
  }
};

// Backward compatibility alias for VenueSearchWithFiltering
Hooks.VenueSearchWithFiltering = Hooks.EventLocationSearch;

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
  
});

// City Search Hook for Poll Creation Component
Hooks.CitySearch = {
  mounted() {
    if (process.env.NODE_ENV !== 'production') console.log("CitySearch hook mounted");
    this.inputEl = this.el;
    this.mounted = true;
    this.autocomplete = null;
    this.hiddenInput = document.getElementById('poll_search_location_data');
    
    // Initialize Google Places autocomplete for cities
    this.initCityAutocomplete();
  },
  
  destroyed() {
    if (this.autocomplete) {
      google.maps.event.clearInstanceListeners(this.autocomplete);
      this.autocomplete = null;
    }
    this.mounted = false;
  },
  
  initCityAutocomplete() {
    if (!this.mounted || !window.google || !window.google.maps || !window.google.maps.places) {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps not loaded yet for CitySearch, waiting...");
      setTimeout(() => this.initCityAutocomplete(), 100);
      return;
    }
    
    try {
      // Create autocomplete for cities only
      this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, {
        types: ['(cities)'],
        fields: ['place_id', 'name', 'formatted_address', 'geometry']
      });
      
      // Listen for place selection
      this.autocomplete.addListener('place_changed', () => {
        const place = this.autocomplete.getPlace();
        if (place && place.place_id) {
          // Store the city data in the hidden input
          const cityData = {
            place_id: place.place_id,
            name: place.name,
            formatted_address: place.formatted_address,
            geometry: {
              lat: place.geometry.location.lat(),
              lng: place.geometry.location.lng()
            }
          };
          
          if (this.hiddenInput) {
            this.hiddenInput.value = JSON.stringify(cityData);
            // Trigger change event to update LiveView
            this.hiddenInput.dispatchEvent(new Event('change', { bubbles: true }));
          }
          
          // Also trigger change on the visible input
          this.inputEl.dispatchEvent(new Event('change', { bubbles: true }));
        }
      });
      
      if (process.env.NODE_ENV !== 'production') console.log("City autocomplete initialized successfully");
    } catch (error) {
      console.error("Error initializing city autocomplete:", error);
    }
  }
};

// Simplified Google Places Autocomplete Hook for Polls
// Following issue #771 recommendations - using native Google Autocomplete widget
// Reduced from 642 lines to ~200 lines while maintaining all functionality

Hooks.PlacesSuggestionSearch = {
  mounted() {
    this.inputEl = this.el;
    this.autocomplete = null;
    this.selectedPlaceData = null;
    
    // Get configuration from data attributes
    this.locationScope = this.el.dataset.locationScope || 'place';
    this.searchLocation = this.parseSearchLocation();
    
    // Initialize Google Places Autocomplete
    this.initAutocomplete();
    
    // Set up form submission handler
    this.setupFormHandler();
  },
  
  destroyed() {
    // Clean up autocomplete instance
    if (this.autocomplete) {
      google.maps.event.clearInstanceListeners(this.autocomplete);
    }
    
    // Clean up form handler
    if (this.formHandler) {
      const form = this.el.closest('form');
      if (form) {
        form.removeEventListener('submit', this.formHandler);
      }
    }
    
    // Clean up input clear handler
    if (this.inputClearHandler) {
      this.inputEl.removeEventListener('input', this.inputClearHandler);
      this.inputClearHandler = null;
    }
  },
  
  parseSearchLocation() {
    const data = this.el.dataset.searchLocation;
    if (!data) return null;
    
    try {
      return JSON.parse(data);
    } catch (e) {
      console.error("Error parsing search location:", e);
      return null;
    }
  },
  
  initAutocomplete() {
    // Wait for Google Maps to load
    if (!window.google?.maps?.places) {
      // Retry in 100ms
      setTimeout(() => this.initAutocomplete(), 100);
      return;
    }
    
    // Configure autocomplete based on location scope
    const options = {
      fields: [
        'place_id',
        'name', 
        'formatted_address',
        'geometry',
        'address_components',
        'rating',
        'price_level',
        'formatted_phone_number',
        'website',
        'photos',
        'types'
      ]
    };
    
    // Set types based on location scope
    const types = this.getTypesForScope(this.locationScope);
    if (types.length > 0) {
      options.types = types;
    }
    
    // Create autocomplete instance
    this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
    
    // Apply location bias if search location is set
    if (this.searchLocation?.geometry) {
      const center = {
        lat: this.searchLocation.geometry.lat,
        lng: this.searchLocation.geometry.lng
      };
      
      // Create bias circle based on location scope - same as PlacesHistorySearch
      // venue/place: 50km radius, city: 100km, region: 200km
      let radius = 50000; // Default 50km for venues
      if (this.locationScope === 'city') {
        radius = 100000; // 100km for city scope
      } else if (this.locationScope === 'region') {
        radius = 200000; // 200km for region scope
      }
      const circle = new google.maps.Circle({ center, radius });
      this.autocomplete.setBounds(circle.getBounds());
    }
    
    // Handle place selection
    this.autocomplete.addListener('place_changed', () => {
      this.handlePlaceSelection();
    });
  },
  
  getTypesForScope(scope) {
    // Map location scopes to Google Places types
    const scopeTypes = {
      'place': ['establishment'],
      'city': ['(cities)'],
      'region': ['(regions)'],  // Fixed: Use proper collection type for regions
      'country': ['(regions)'],  // Fixed: 'country' is not valid, use regions collection
      'custom': [] // No restrictions
    };
    
    return scopeTypes[scope] || ['establishment'];
  },
  
  handlePlaceSelection() {
    const place = this.autocomplete.getPlace();
    
    // Validate place data
    if (!place?.geometry) {
      // User entered text without selecting from dropdown
      // Let them submit plain text if they want
      return;
    }
    
    // Extract place data
    this.selectedPlaceData = this.extractPlaceData(place);
    
    // Update input with formatted display
    const displayName = place.name || '';
    const shortAddress = this.getShortAddress(place);
    this.inputEl.value = shortAddress ? `${displayName}, ${shortAddress}` : displayName;
    
    // Store place data for form submission
    this.inputEl.dataset.hasPlaceData = 'true';
  },
  
  getShortAddress(place) {
    // Extract city/region for display
    if (!place.address_components) return '';
    
    for (const component of place.address_components) {
      if (component.types.includes('locality')) {
        return component.short_name;
      }
    }
    
    // Fallback to administrative area
    for (const component of place.address_components) {
      if (component.types.includes('administrative_area_level_1')) {
        return component.short_name;
      }
    }
    
    return '';
  },
  
  extractPlaceData(place) {
    // Extract address components
    let city = '', state = '', country = '';
    
    if (place.address_components) {
      for (const component of place.address_components) {
        const types = component.types;
        if (types.includes('locality')) {
          city = component.long_name;
        } else if (types.includes('administrative_area_level_1')) {
          state = component.long_name;
        } else if (types.includes('country')) {
          country = component.long_name;
        }
      }
    }
    
    // Build place data object
    return {
      title: place.name,
      address: place.formatted_address || '',
      city: city,
      state: state,
      country: country,
      latitude: Math.round(place.geometry.location.lat() * 10000) / 10000, // Round for privacy
      longitude: Math.round(place.geometry.location.lng() * 10000) / 10000,
      place_id: place.place_id,
      rating: place.rating || null,
      price_level: place.price_level || null,
      phone: place.formatted_phone_number || '',
      website: place.website || '',
      photos: place.photos?.slice(0, 3).map(p => p.getUrl({maxWidth: 400})) || []
    };
  },
  
  setupFormHandler() {
    // Intercept form submission to include place data
    const form = this.el.closest('form');
    if (!form) return;
    
    this.formHandler = (e) => {
      // Only add place data if a place was selected
      if (this.selectedPlaceData && this.inputEl.dataset.hasPlaceData === 'true') {
        // Create hidden fields for place metadata
        const metadata = {
          external_data: JSON.stringify(this.selectedPlaceData),
          external_id: this.selectedPlaceData.place_id,
          metadata: JSON.stringify({
            city: this.selectedPlaceData.city,
            state: this.selectedPlaceData.state,
            country: this.selectedPlaceData.country,
            latitude: this.selectedPlaceData.latitude,
            longitude: this.selectedPlaceData.longitude
          })
        };
        
        // Add hidden inputs
        Object.entries(metadata).forEach(([key, value]) => {
          const existing = form.querySelector(`input[name="poll_option[${key}]"]`);
          if (existing) {
            existing.value = value;
          } else {
            const input = document.createElement('input');
            input.type = 'hidden';
            input.name = `poll_option[${key}]`;
            input.value = value;
            form.appendChild(input);
          }
        });
        
        // Add image URL if available
        if (this.selectedPlaceData.photos && this.selectedPlaceData.photos.length > 0) {
          const imageInput = document.createElement('input');
          imageInput.type = 'hidden';
          imageInput.name = 'poll_option[image_url]';
          imageInput.value = this.selectedPlaceData.photos[0];
          form.appendChild(input);
        }
      }
    };
    
    form.addEventListener('submit', this.formHandler);
    
    // Clear selection if user edits after choosing a place
    this.inputClearHandler = () => {
      this.selectedPlaceData = null;
      this.inputEl.dataset.hasPlaceData = 'false';
    };
    this.inputEl.addEventListener('input', this.inputClearHandler);
  }
};

// Simplified Google Places Autocomplete Hook for History (Places)
// Uses SAME logic as PlacesSuggestionSearch for consistency
Hooks.PlacesHistorySearch = {
  mounted() {
    this.inputEl = this.el;
    this.autocomplete = null;
    this.selectedPlaceData = null;
    
    // Get configuration from data attributes (same as PlacesSuggestionSearch)
    this.locationScope = this.el.dataset.locationScope || 'place';
    this.searchLocation = this.parseSearchLocation();
    
    // Initialize Google Places Autocomplete
    this.initAutocomplete();
    
    // Clear hidden fields if user edits after selection
    this.inputClearHandler = () => {
      this.selectedPlaceData = null;
      const prefix = 'place-search-';
      const formId = (this.el.id && this.el.id.startsWith(prefix))
        ? this.el.id.slice(prefix.length)
        : null;
      if (!formId) return;
      
      const placeIdField = document.getElementById(`place-id-${formId}`);
      const addressField = document.getElementById(`place-address-${formId}`);
      const ratingField = document.getElementById(`place-rating-${formId}`);
      const photosField = document.getElementById(`place-photos-${formId}`);
      if (placeIdField) placeIdField.value = '';
      if (addressField) addressField.value = '';
      if (ratingField) ratingField.value = '';
      if (photosField) photosField.value = '[]';
    };
    this.inputEl.addEventListener('input', this.inputClearHandler);
  },
  
  destroyed() {
    // Clean up autocomplete instance
    if (this.autocomplete) {
      google.maps.event.clearInstanceListeners(this.autocomplete);
    }
    // Clean up input handler
    if (this.inputClearHandler) {
      this.inputEl.removeEventListener('input', this.inputClearHandler);
      this.inputClearHandler = null;
    }
  },
  
  parseSearchLocation() {
    const data = this.el.dataset.searchLocation;
    if (!data) return null;
    
    try {
      return JSON.parse(data);
    } catch (e) {
      console.error("Error parsing search location:", e);
      return null;
    }
  },
  
  initAutocomplete() {
    // Wait for Google Maps to load
    if (!window.google?.maps?.places) {
      setTimeout(() => this.initAutocomplete(), 100);
      return;
    }
    
    // Configure autocomplete for places (same as polls)
    const options = {
      types: ['establishment'], // Same as polls - includes restaurants, cafes, bars, venues, etc.
      fields: [
        'place_id',
        'name',
        'formatted_address',
        'geometry',
        'rating',
        'price_level',
        'website',
        'formatted_phone_number',
        'photos',
        'types',
        'address_components'
      ]
    };
    
    // Create autocomplete instance
    this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
    
    // Apply location bias if search location is set (same as PlacesSuggestionSearch)
    if (this.searchLocation?.geometry) {
      const center = {
        lat: this.searchLocation.geometry.lat,
        lng: this.searchLocation.geometry.lng
      };
      
      // Create bias circle based on location scope
      // venue/place: 50km radius, city: 100km, region: 200km
      let radius = 50000; // Default 50km for venues
      if (this.locationScope === 'city') {
        radius = 100000; // 100km for city scope
      } else if (this.locationScope === 'region') {
        radius = 200000; // 200km for region scope
      }
      
      const circle = new google.maps.Circle({ center, radius });
      this.autocomplete.setBounds(circle.getBounds());
    }
    
    // Handle place selection
    this.autocomplete.addListener('place_changed', () => {
      this.handlePlaceSelection();
    });
  },
  
  handlePlaceSelection() {
    const place = this.autocomplete.getPlace();
    
    if (!place?.geometry) {
      return;
    }
    
    // Extract address components (SAME as PlacesSuggestionSearch for consistency)
    let city = '', state = '', country = '';
    
    if (place.address_components) {
      for (const component of place.address_components) {
        const types = component.types;
        if (types.includes('locality')) {
          city = component.long_name;
        } else if (types.includes('administrative_area_level_1')) {
          state = component.long_name;
        } else if (types.includes('country')) {
          country = component.long_name;
        }
      }
    }
    
    // Build place data object (SAME structure as PlacesSuggestionSearch for consistency)
    this.selectedPlaceData = {
      title: place.name,
      address: place.formatted_address || '',
      city: city,
      state: state,
      country: country,
      latitude: Math.round(place.geometry.location.lat() * 10000) / 10000,
      longitude: Math.round(place.geometry.location.lng() * 10000) / 10000,
      place_id: place.place_id,
      rating: place.rating || null,
      price_level: place.price_level || null,
      phone: place.formatted_phone_number || '',
      website: place.website || '',
      photos: place.photos?.slice(0, 3).map(p => p.getUrl({maxWidth: 400})) || []
    };
    
    // Update input with display name (keep it for user feedback)
    const displayName = place.name || '';
    const shortAddress = this.getShortAddress(place);
    this.inputEl.value = shortAddress ? `${displayName}, ${shortAddress}` : displayName;
    
    // Populate hidden fields with place data (SAME approach as PlacesSuggestionSearch)
    const formId = this.el.id.replace('place-search-', '');
    
    // Find and populate hidden fields
    const placeIdField = document.getElementById(`place-id-${formId}`);
    const addressField = document.getElementById(`place-address-${formId}`);
    const ratingField = document.getElementById(`place-rating-${formId}`);
    const photosField = document.getElementById(`place-photos-${formId}`);
    
    if (placeIdField) placeIdField.value = this.selectedPlaceData.place_id || '';
    if (addressField) addressField.value = this.selectedPlaceData.address || '';
    if (ratingField) ratingField.value = this.selectedPlaceData.rating || '';
    if (photosField) photosField.value = JSON.stringify(this.selectedPlaceData.photos || []);
  },
  
  getShortAddress(place) {
    // Extract city/region for display
    if (!place.address_components) return '';
    
    for (const component of place.address_components) {
      if (component.types.includes('locality')) {
        return component.short_name;
      }
    }
    
    // Fallback to administrative area
    for (const component of place.address_components) {
      if (component.types.includes('administrative_area_level_1')) {
        return component.short_name;
      }
    }
    
    return '';
  }
};

