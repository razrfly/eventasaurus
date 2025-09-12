// Initialization scripts that need to run on page load
// This file contains scripts previously inline in root.html.heex

// PostHog configuration
export function initPostHog() {
  // Configuration is set via data attributes on the body element
  const body = document.body;
  const apiKey = body.dataset.posthogApiKey;
  const host = body.dataset.posthogHost || 'https://eu.i.posthog.com';
  const userDataEl = document.getElementById('current-user-data');

  if (apiKey) {
    console.log("PostHog configuration loaded:", {
      apiKeyPresent: true,
      apiKeyLength: apiKey.length,
      host: host
    });
    
    window.POSTHOG_API_KEY = apiKey;
    window.POSTHOG_HOST = host;
    
    if (userDataEl) {
      const userData = JSON.parse(userDataEl.textContent || '{}');
      window.currentUser = userData;
    }
  } else {
    // PostHog disabled (no API key configured)
    window.POSTHOG_API_KEY = null;
  }
}

// Google Maps initialization
export function setupGoogleMaps() {
  console.log("Setting up Google Maps API loader...");
  
  // Track loading state
  window.googleMapsLoaded = false;
  
  // Error handler
  window.handleGoogleMapsError = function() {
    console.error("Failed to load Google Maps API. Check your API key and network connection.");
    window.googleMapsLoaded = false;
  };
  
  // Success handler
  window.initGoogleMaps = function() {
    console.log("Google Maps API loaded successfully");
    window.googleMapsLoaded = true;
    
    // Call any initialization hooks
    if (typeof window.initGooglePlaces === 'function') {
      console.log("Initializing Google Places components...");
      try {
        window.initGooglePlaces();
      } catch (e) {
        console.error("Error initializing Google Places:", e);
      }
    }
  };
}

// Load Google Maps script dynamically
export function loadGoogleMaps() {
  const mapsApiKey = document.body.dataset.googleMapsApiKey;
  
  if (mapsApiKey) {
    const googleMapsLoader = document.createElement('script');
    googleMapsLoader.src = `https://maps.googleapis.com/maps/api/js?key=${mapsApiKey}&libraries=places&v=weekly&callback=initGoogleMaps`;
    googleMapsLoader.async = true;
    googleMapsLoader.defer = true;
    googleMapsLoader.onerror = window.handleGoogleMapsError;
    document.head.appendChild(googleMapsLoader);
  }
}

// Mobile navigation
export function initMobileNavigation() {
  const mobileMenuButton = document.getElementById('mobile-menu-button');
  const mobileMenu = document.getElementById('mobile-menu');
  const mobileMenuOverlay = document.getElementById('mobile-menu-overlay');
  
  function toggleMobileMenu() {
    const isOpen = !mobileMenu.classList.contains('translate-x-full');
    
    if (isOpen) {
      // Close menu
      mobileMenu.classList.add('translate-x-full');
      mobileMenuOverlay.classList.add('opacity-0', 'pointer-events-none');
      document.body.classList.remove('overflow-hidden');
    } else {
      // Open menu
      mobileMenu.classList.remove('translate-x-full');
      mobileMenuOverlay.classList.remove('opacity-0', 'pointer-events-none');
      document.body.classList.add('overflow-hidden');
    }
  }
  
  if (mobileMenuButton && mobileMenu) {
    mobileMenuButton.addEventListener('click', toggleMobileMenu);
    mobileMenuOverlay.addEventListener('click', toggleMobileMenu);
    
    // Close menu on escape key
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && !mobileMenu.classList.contains('translate-x-full')) {
        toggleMobileMenu();
      }
    });
  }
}

// Privacy banner functionality
export function initPrivacyBanner() {
  const banner = document.getElementById('privacy-banner');
  const acceptBtn = document.getElementById('privacy-accept');
  const declineBtn = document.getElementById('privacy-decline');
  
  // Check if consent is already given
  const hasConsent = localStorage.getItem('posthog_privacy_consent');
  
  if (!hasConsent && banner) {
    // Show banner after a short delay
    setTimeout(() => {
      banner.classList.remove('hidden');
      requestAnimationFrame(() => {
        banner.classList.remove('translate-y-full');
      });
    }, 2000);
  }
  
  // Handle accept button
  if (acceptBtn) {
    acceptBtn.addEventListener('click', function() {
      const consent = { analytics: true, cookies: true, essential: true };
      localStorage.setItem('posthog_privacy_consent', JSON.stringify(consent));
      
      // Trigger PostHog consent event
      window.dispatchEvent(new CustomEvent('posthog:privacy-consent', {
        detail: { consent }
      }));
      
      hideBanner();
    });
  }
  
  // Handle decline button
  if (declineBtn) {
    declineBtn.addEventListener('click', function() {
      const consent = { analytics: false, cookies: false, essential: true };
      localStorage.setItem('posthog_privacy_consent', JSON.stringify(consent));
      
      // Trigger PostHog consent event
      window.dispatchEvent(new CustomEvent('posthog:privacy-consent', {
        detail: { consent }
      }));
      
      hideBanner();
    });
  }
  
  function hideBanner() {
    if (banner) {
      banner.classList.add('translate-y-full');
      setTimeout(() => {
        banner.classList.add('hidden');
      }, 300);
    }
  }
}

// Initialize everything on DOMContentLoaded
document.addEventListener('DOMContentLoaded', function() {
  initPostHog();
  setupGoogleMaps();
  loadGoogleMaps();
  initMobileNavigation();
  initPrivacyBanner();
});