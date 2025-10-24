// Import dependencies
import "phoenix_html";
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";
import topbar from "../vendor/topbar";
import { TicketQR } from "./ticket_qr";
import { MusicBrainzSearch } from "./musicbrainz_search";
import { SpotifySearch } from "./spotify_search";

// Import modular components
import { initializeClipboard } from "./utils/clipboard";
import { posthogManager, initPostHogClient } from "./analytics/posthog-manager";
import { initSupabaseClient, SupabaseAuthHandler } from "./auth/supabase-manager";
import FormHooks from "./hooks/forms";
import UIHooks from "./hooks/ui-interactions";
import PaymentHooks from "./hooks/payment-business-logic";
import MediaHooks from "./hooks/media-external-apis";
import PlacesHooks from "./hooks/places-search/index";
import DragDropHooks from "./hooks/poll-drag-drop";
import { ChartHook } from "./hooks/chart_hook";
import { VenueMap } from "./hooks/venue-map";

// Supabase client setup for identity management
let supabaseClient = null;

// Define LiveView hooks here
import SupabaseImageUpload from "./supabase_upload";
let Hooks = {};


// TicketQR hook for generating QR codes on tickets
Hooks.TicketQR = TicketQR;

// Language cookie hook for persistence
Hooks.LanguageCookie = {
  mounted() {
    this.handleEvent("set_language_cookie", ({ language }) => {
      const secure = location.protocol === "https:" ? "; Secure" : ""
      document.cookie =
        `language_preference=${encodeURIComponent(language)}; ` +
        `Max-Age=${60 * 60 * 24 * 365}; Path=/; SameSite=Lax${secure}`
    })
  }
}

// SupabaseAuthHandler hook is imported from auth/supabase-manager.js

// Supabase image upload hook for file input
Hooks.SupabaseImageUpload = SupabaseImageUpload;




// Merge modular hooks with existing hooks
const ModularHooks = {
  ...FormHooks,
  ...UIHooks,
  ...PaymentHooks,
  ...MediaHooks,
  ...PlacesHooks,
  ...DragDropHooks,
  SupabaseAuthHandler, // Individual hook import
  ChartHook, // Chart.js hook for Phase 6
  VenueMap // Leaflet map hook for venue location
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

// Initialize components on page load
document.addEventListener("DOMContentLoaded", function() {
  // Handle Supabase Auth Callback FIRST (critical for password reset links)
  if (window.location.hash && window.location.hash.includes("access_token")) {
    console.log('Processing Supabase auth tokens from URL hash...');
    // Parse hash params
    const hashParams = window.location.hash.substring(1).split("&").reduce((acc, pair) => {
      const [key, value] = pair.split("=");
      acc[key] = decodeURIComponent(value);
      return acc;
    }, {});

    console.log('Parsed hash params:', Object.keys(hashParams));

    // Check for required tokens
    if (hashParams.access_token) {
      console.log('Found access_token, creating form to submit to callback...');
      
      // Create a form to post the tokens
      const form = document.createElement("form");
      form.method = "POST";
      form.action = "/auth/callback";
      form.style.display = "none";

      // Add CSRF token (Phoenix default meta tag)
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
      if (csrfToken) {
        const csrfInput = document.createElement("input");
        csrfInput.type = "hidden";
        csrfInput.name = "_csrf_token";
        csrfInput.value = csrfToken;
        form.appendChild(csrfInput);
      }

      // Add the tokens
      const accessTokenInput = document.createElement("input");
      accessTokenInput.type = "hidden";
      accessTokenInput.name = "access_token";
      accessTokenInput.value = hashParams.access_token;
      form.appendChild(accessTokenInput);

      if (hashParams.refresh_token) {
        const refreshTokenInput = document.createElement("input");
        refreshTokenInput.type = "hidden";
        refreshTokenInput.name = "refresh_token";
        refreshTokenInput.value = hashParams.refresh_token;
        form.appendChild(refreshTokenInput);
      }

      // Add callback type
      const typeInput = document.createElement("input");
      typeInput.type = "hidden";
      typeInput.name = "type";
      typeInput.value = hashParams.type || "unknown";
      form.appendChild(typeInput);

      // Submit form to handle tokens server-side
      document.body.appendChild(form);
      console.log('Submitting auth callback form...');
      form.submit();

      // Remove hash from URL (to prevent tokens from staying in browser history)
      window.history.replaceState(null, null, window.location.pathname);
      return; // Exit early, form submission will navigate away
    }
  }

  // Initialize PostHog analytics with privacy checks
  posthogManager.showPrivacyBanner();
  posthogManager.init();
  
  // Initialize Supabase client
  initSupabaseClient();
});

// Initialize modular components
initializeClipboard();

