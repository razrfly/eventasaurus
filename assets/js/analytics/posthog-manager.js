// PostHog Analytics Manager with Two-Tier Tracking
//
// ARCHITECTURE:
// - Tier 1 (Public/Anonymous): Cookieless mode, no consent required, GDPR compliant
// - Tier 2 (Authenticated): Full tracking with cookies, consent via Terms of Service
//
// This enables tracking of ALL visitors (9,000+/day) while respecting privacy.
// See: https://posthog.com/tutorials/cookieless-tracking

export class PostHogManager {
  constructor() {
    this.posthog = null;
    this.isLoaded = false;
    this.isLoading = false;
    this.eventQueue = [];
    this.loadAttempts = 0;
    this.maxLoadAttempts = 3;
    this.retryDelay = 2000;
    this.isOnline = navigator.onLine;

    // Determine tracking tier based on authentication status
    this.isAuthenticated = !!window.currentUser;
    this.trackingTier = this.isAuthenticated ? 'authenticated' : 'anonymous';

    // Enhanced features consent (session replay, etc.) - only for authenticated users
    this.enhancedConsent = this.getEnhancedConsent();

    // Listen for online/offline events
    window.addEventListener('online', () => {
      this.isOnline = true;
      this.processQueue();
    });

    window.addEventListener('offline', () => {
      this.isOnline = false;
    });

    // Listen for enhanced consent changes (session replay opt-in)
    window.addEventListener('posthog:enhanced-consent', (e) => {
      if (e.detail?.consent) {
        this.updateEnhancedConsent(e.detail.consent);
      }
    });

    // Legacy privacy consent listener for backwards compatibility
    window.addEventListener('posthog:privacy-consent', (e) => {
      // Map old consent format to new enhanced consent
      if (e.detail?.consent) {
        this.updateEnhancedConsent({
          sessionReplay: e.detail.consent.analytics,
          marketing: e.detail.consent.marketing
        });
      }
    });
  }

  async init() {
    if (this.isLoaded || this.isLoading) {
      console.log('PostHog init skipped:', {
        isLoaded: this.isLoaded,
        isLoading: this.isLoading
      });
      return;
    }

    this.isLoading = true;

    try {
      // Get PostHog config from window variables set by the server
      const posthogApiKey = window.POSTHOG_API_KEY;
      const posthogHost = window.POSTHOG_HOST || 'https://eu.i.posthog.com';

      if (!posthogApiKey) {
        // Silently disable analytics when no API key is present
        this.isLoading = false;
        return;
      }

      // Re-check authentication status (may have changed)
      this.isAuthenticated = !!window.currentUser;
      this.trackingTier = this.isAuthenticated ? 'authenticated' : 'anonymous';

      console.log('PostHog initialization:', {
        trackingTier: this.trackingTier,
        isAuthenticated: this.isAuthenticated,
        cookielessMode: !this.isAuthenticated,
        host: posthogHost
      });

      // Dynamic import to prevent blocking page render
      const { default: posthog } = await import('posthog-js');

      // Build configuration based on tracking tier
      const config = this.buildConfig(posthogApiKey, posthogHost);

      console.log('PostHog config:', {
        cookieless_mode: config.cookieless_mode,
        persistence: config.persistence,
        capture_pageview: config.capture_pageview
      });

      // Initialize PostHog
      posthog.init(posthogApiKey, config);

      this.posthog = posthog;
      this.isLoaded = true;
      this.isLoading = false;
      this.loadAttempts = 0;

      console.log(`PostHog loaded successfully (${this.trackingTier} tier)`);

      // Process any queued events
      this.processQueue();

    } catch (error) {
      console.error('Failed to load PostHog:', {
        error: error.message,
        loadAttempts: this.loadAttempts
      });
      this.isLoading = false;
      this.loadAttempts++;

      // Retry loading with exponential backoff
      if (this.loadAttempts < this.maxLoadAttempts) {
        const delay = this.retryDelay * Math.pow(2, this.loadAttempts - 1);
        console.log(`Retrying PostHog load in ${delay}ms (attempt ${this.loadAttempts}/${this.maxLoadAttempts})`);
        setTimeout(() => this.init(), delay);
      } else {
        console.warn('PostHog failed to load after multiple attempts');
        this.eventQueue = [];
      }
    }
  }

  /**
   * Build PostHog configuration based on tracking tier
   *
   * Anonymous users: Cookieless mode (GDPR compliant, no consent needed)
   * Authenticated users: Full tracking (consent via Terms of Service)
   */
  buildConfig(apiKey, host) {
    const baseConfig = {
      api_host: host,

      // Always capture pageviews - this is the core metric we need
      capture_pageview: true,
      capture_pageleave: true,

      // Disable autocapture to prevent noise - we track specific events manually
      autocapture: false,

      // Callback when loaded
      loaded: (posthogInstance) => {
        this.onPostHogLoaded(posthogInstance);
      },

      // Error handling
      on_request_error: (error) => {
        console.warn('PostHog request failed:', error);
      },

      // Batch settings for performance
      request_batching: true,
      request_queue_config: {
        flush_interval_ms: 5000
      },

      // Security
      secure_cookie: window.location.protocol === 'https:'
    };

    if (this.isAuthenticated) {
      // TIER 2: Full tracking for authenticated users
      // Consent is implied via Terms of Service at signup
      return {
        ...baseConfig,

        // Full cookie-based tracking
        cookieless_mode: 'off',
        persistence: 'localStorage+cookie',
        disable_persistence: false,

        // Cross-subdomain tracking for authenticated users
        cross_subdomain_cookie: true,

        // Session replay based on enhanced consent
        disable_session_recording: !this.enhancedConsent.sessionReplay,

        // No need to opt out by default - they accepted ToS
        opt_out_capturing_by_default: false,
        respect_dnt: false, // Authenticated users have explicit consent

        // Full data capture for authenticated users
        mask_all_element_attributes: false,
        mask_all_text: false
      };
    } else {
      // TIER 1: Cookieless tracking for anonymous users
      // GDPR compliant without requiring consent
      return {
        ...baseConfig,

        // COOKIELESS MODE: Uses privacy-preserving hash instead of cookies
        // This is GDPR compliant and doesn't require consent
        // Note: Hash rotates daily, so cross-day tracking is limited
        cookieless_mode: 'always',

        // Memory-only persistence (no cookies or localStorage)
        persistence: 'memory',
        disable_persistence: true,

        // No cross-subdomain tracking
        cross_subdomain_cookie: false,

        // Session replay disabled for anonymous users
        disable_session_recording: true,

        // Don't need to opt out - cookieless is privacy-preserving by design
        opt_out_capturing_by_default: false,
        respect_dnt: true, // Still respect DNT for anonymous

        // Privacy-preserving defaults
        mask_all_element_attributes: true,
        mask_all_text: false // Keep text for content analytics
      };
    }
  }

  onPostHogLoaded(posthogInstance) {
    console.log(`PostHog initialized (${this.trackingTier} tier)`);

    // Register common properties for all events
    posthogInstance.register({
      tracking_tier: this.trackingTier,
      is_authenticated: this.isAuthenticated
    });

    if (this.isAuthenticated && window.currentUser) {
      // Identify authenticated users
      const identifyProps = {
        user_type: 'authenticated',
        tracking_tier: 'authenticated'
      };

      // Add email hash if marketing consent given
      if (this.enhancedConsent.marketing && window.currentUser.email) {
        this.hashEmail(window.currentUser.email)
          .then(hashedEmail => {
            posthogInstance.identify(window.currentUser.id, {
              ...identifyProps,
              email_hash: hashedEmail,
              name: window.currentUser.name
            });
            console.log('PostHog user identified:', window.currentUser.id);
          })
          .catch(() => {
            // Fall back to identifying without email hash
            posthogInstance.identify(window.currentUser.id, identifyProps);
          });
      } else {
        posthogInstance.identify(window.currentUser.id, identifyProps);
        console.log('PostHog user identified:', window.currentUser.id);
      }
    } else {
      // Anonymous user - just register properties, no identification
      // (cookieless mode doesn't support identify() anyway)
      console.log('PostHog tracking anonymous visitor (cookieless)');
    }
  }

  capture(event, properties = {}) {
    const eventData = {
      event,
      properties: {
        ...properties,
        timestamp: Date.now(),
        tracking_tier: this.trackingTier,
        is_authenticated: this.isAuthenticated,
        is_online: this.isOnline
      }
    };

    if (this.isLoaded && this.posthog && this.isOnline) {
      try {
        this.posthog.capture(event, eventData.properties);
        console.log('PostHog event captured:', event);
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

    // Initialize retry count if not present
    if (typeof eventData.retryCount === 'undefined') {
      eventData.retryCount = 0;
    }

    this.eventQueue.push(eventData);
    console.log(`Event queued (${this.eventQueue.length} total):`, eventData.event);
  }

  processQueue() {
    if (!this.isLoaded || !this.posthog || !this.isOnline) {
      return;
    }

    if (this.eventQueue.length === 0) return;

    console.log(`Processing ${this.eventQueue.length} queued events`);

    const eventsToProcess = [...this.eventQueue];
    this.eventQueue = [];

    const maxRetries = 3;

    eventsToProcess.forEach(eventData => {
      try {
        this.posthog.capture(eventData.event, eventData.properties);
      } catch (error) {
        console.warn('Failed to process queued event:', error);
        // Only re-queue if under retry limit
        if (eventData.retryCount < maxRetries) {
          eventData.retryCount++;
          this.queueEvent(eventData);
        } else {
          console.warn(`Dropping event after ${maxRetries} retries:`, eventData.event);
        }
      }
    });
  }

  /**
   * Get enhanced feature consent (session replay, marketing)
   * Only relevant for authenticated users
   */
  getEnhancedConsent() {
    // Default: session replay enabled for authenticated users, marketing opt-in
    const defaults = {
      sessionReplay: this.isAuthenticated, // On by default for authenticated
      marketing: false // Off by default
    };

    try {
      const stored = localStorage.getItem('posthog_enhanced_consent');
      if (stored) {
        return { ...defaults, ...JSON.parse(stored) };
      }

      // Check legacy consent format for migration
      const legacyConsent = localStorage.getItem('posthog_privacy_consent');
      if (legacyConsent) {
        const legacy = JSON.parse(legacyConsent);
        return {
          sessionReplay: legacy.analytics ?? defaults.sessionReplay,
          marketing: legacy.marketing ?? defaults.marketing
        };
      }
    } catch (error) {
      console.warn('Failed to read enhanced consent:', error);
    }

    return defaults;
  }

  /**
   * Update enhanced feature consent
   * Used for session replay opt-out, marketing preferences
   */
  updateEnhancedConsent(consent) {
    const prev = this.enhancedConsent;
    this.enhancedConsent = { ...prev, ...consent };

    try {
      localStorage.setItem('posthog_enhanced_consent', JSON.stringify(this.enhancedConsent));
    } catch (error) {
      console.warn('Failed to save enhanced consent:', error);
    }

    console.log('Enhanced consent updated:', this.enhancedConsent);

    // Apply session replay changes if PostHog is loaded
    if (this.isLoaded && this.posthog) {
      const replayChanged = prev.sessionReplay !== this.enhancedConsent.sessionReplay;

      if (replayChanged && this.isAuthenticated) {
        if (this.enhancedConsent.sessionReplay) {
          // Enable session replay
          try {
            this.posthog.startSessionRecording?.();
          } catch {}
        } else {
          // Disable session replay
          try {
            this.posthog.stopSessionRecording?.();
          } catch {}
        }
      }
    }
  }

  /**
   * Disable all tracking (emergency opt-out)
   */
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

  /**
   * Re-enable tracking after disable
   */
  enable() {
    if (this.posthog) {
      try {
        this.posthog.opt_in_capturing();
        console.log('PostHog tracking enabled');
      } catch (error) {
        console.warn('Failed to enable PostHog:', error);
      }
    }
  }

  /**
   * Hash email for GDPR compliance
   */
  async hashEmail(email) {
    if (!email || typeof email !== 'string') {
      throw new Error('Invalid email');
    }

    if (typeof crypto?.subtle !== 'object') {
      throw new Error('crypto.subtle not available');
    }

    const data = new TextEncoder().encode(email);
    const digest = await crypto.subtle.digest('SHA-256', data);
    return Array.from(new Uint8Array(digest))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
  }

  /**
   * Show enhanced features consent banner (for session replay opt-in)
   * Only shown to authenticated users who haven't chosen yet
   */
  showEnhancedConsentBanner() {
    if (!this.isAuthenticated) return; // Only for authenticated users

    let hasChosen = false;
    try {
      hasChosen = localStorage.getItem('posthog_enhanced_consent') !== null;
    } catch {}

    if (!hasChosen) {
      window.dispatchEvent(new CustomEvent('posthog:show-enhanced-consent'));

      const banner = document.getElementById('enhanced-consent-banner');
      if (banner) {
        banner.style.display = 'block';
        setTimeout(() => {
          banner.style.transform = 'translateY(0)';
        }, 100);
      }
    }
  }

  // ============================================
  // LEGACY COMPATIBILITY
  // ============================================

  /**
   * @deprecated Use enhancedConsent instead
   * Kept for backwards compatibility with existing code
   */
  get privacyConsent() {
    return {
      analytics: true, // Always true now (cookieless doesn't need consent)
      cookies: this.isAuthenticated,
      marketing: this.enhancedConsent.marketing,
      essential: true
    };
  }

  /**
   * @deprecated Privacy consent no longer blocks basic tracking
   */
  getPrivacyConsent() {
    return this.privacyConsent;
  }

  /**
   * @deprecated Use updateEnhancedConsent instead
   */
  updatePrivacyConsent(consent) {
    this.updateEnhancedConsent({
      sessionReplay: consent.analytics,
      marketing: consent.marketing
    });
  }

  /**
   * @deprecated No longer needed - basic tracking doesn't require consent
   */
  showPrivacyBanner() {
    // Only show for enhanced features now
    this.showEnhancedConsentBanner();
  }
}

// Create and export the manager instance
export const posthogManager = new PostHogManager();

// Legacy compatibility function
export function initPostHogClient() {
  return posthogManager.init();
}
