// Import dependencies
import "phoenix_html";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import topbar from "../vendor/topbar";
import { TicketQR } from "./ticket_qr";
import { MusicBrainzSearch } from "./musicbrainz_search";
import { SpotifySearch } from "./spotify_search";

// Import new modular components (shadow implementation - keeping existing code)
import { initializeClipboard } from "./utils/clipboard";
import { posthogManager, initPostHogClient } from "./analytics/posthog-manager";
import { initSupabaseClient, SupabaseAuthHandler } from "./auth/supabase-manager";
import FormHooks from "./hooks/forms";
import UIHooks from "./hooks/ui-interactions";
import PaymentHooks from "./hooks/payment-business-logic";
import MediaHooks from "./hooks/media-external-apis";
import PlacesHooks from "./hooks/places-search";
import DragDropHooks from "./hooks/poll-drag-drop";

// Supabase client setup for identity management
let supabaseClient = null;

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

// Supabase image upload hook for file input
Hooks.SupabaseImageUpload = SupabaseImageUpload;


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


// Merge modular hooks with existing hooks (shadow implementation)
// This allows the new modular hooks to override the old implementations
const ModularHooks = {
  ...FormHooks,
  ...UIHooks,
  ...PaymentHooks,
  ...MediaHooks,
  ...PlacesHooks,
  ...DragDropHooks,
  SupabaseAuthHandler // Individual hook import
};

// Merge all hooks - modular ones take precedence if there are conflicts
const AllHooks = {
  ...Hooks,      // Existing hooks (kept for safety)
  ...ModularHooks // New modular hooks (override existing)
};

// All hooks registered successfully - debug logging removed

// Set up LiveView
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: AllHooks
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

// Initialize modular components (shadow implementation)
// Initialize clipboard functionality from the modular version
initializeClipboard();

// Initialize PostHog manager (if not already initialized by existing code)
// The modular PostHogManager is already exposed as posthogManager above

// Initialize Supabase client (if not already initialized by existing code)
// This will use the modular version
initSupabaseClient();

