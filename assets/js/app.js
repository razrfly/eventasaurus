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

// SupabaseAuthHandler hook is imported from auth/supabase-manager.js

// Supabase image upload hook for file input
Hooks.SupabaseImageUpload = SupabaseImageUpload;




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

// Initialize components on page load
document.addEventListener("DOMContentLoaded", function() {
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

