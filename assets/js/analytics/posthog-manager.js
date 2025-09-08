// PostHog Analytics Manager with performance optimizations
// Extracted from app.js for better organization

export class PostHogManager {
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
        // Storage/persistence aligned with consent
        disable_persistence: !this.privacyConsent.cookies,
        persistence: this.privacyConsent.cookies ? 'localStorage+cookie' : 'memory',
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
        
        // Batch settings for performance (using correct PostHog config keys)
        request_batching: true,
        request_queue_config: { 
          flush_interval_ms: 5000 
        },
        
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
        console.warn('PostHog failed to load after multiple attempts - dropping queued events');
        this.eventQueue = [];
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
    const prev = this.privacyConsent;
    this.privacyConsent = { ...prev, ...consent };
    const analyticsOn  = !prev.analytics && this.privacyConsent.analytics;
    const analyticsOff =  prev.analytics && !this.privacyConsent.analytics;
    const cookiesChanged = prev.cookies !== this.privacyConsent.cookies;
    
    try {
      localStorage.setItem('posthog_privacy_consent', JSON.stringify(this.privacyConsent));
    } catch (error) {
      console.warn('Failed to save privacy consent to localStorage:', error);
    }
    
    console.log('Privacy consent updated:', this.privacyConsent);
    
    // Apply changes
    if (analyticsOn) {
      if (this.isLoaded && this.posthog?.opt_in_capturing) {
        try { this.posthog.opt_in_capturing(); } catch {}
      } else {
        this.init();
      }
    } else if (analyticsOff && this.isLoaded) {
      this.disable();
    } 
    // Don't chain with else-if so cookies + analytics changes both apply
    if (this.isLoaded && cookiesChanged) {
      // Reconfigure persistence based on consent
      if (this.posthog?.set_config) {
        const cfg = this.privacyConsent.cookies
          ? { disable_persistence: false, persistence: 'localStorage+cookie' }
          : { disable_persistence: true,  persistence: 'memory' };
        try { this.posthog.set_config(cfg); } catch {}
      } else {
        // Fallback: re-init with new config
        this.isLoaded = false;
        this.init();
      }
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
    let missing = false;
    try { 
      missing = localStorage.getItem('posthog_privacy_consent') === null; 
    } catch {}
    
    if (missing) {
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

// Create and export the manager instance
export const posthogManager = new PostHogManager();

// Legacy compatibility function
export function initPostHogClient() {
  return posthogManager.init();
}