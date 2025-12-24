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
import { initClerkClient, ClerkAuthHandler, signOut as clerkSignOut, openSignIn as clerkOpenSignIn, openSignUp as clerkOpenSignUp } from "./auth/clerk-manager";
import FormHooks from "./hooks/forms";
import UIHooks from "./hooks/ui-interactions";
import PaymentHooks from "./hooks/payment-business-logic";
import MediaHooks from "./hooks/media-external-apis";
import PlacesHooks from "./hooks/places-search/index";
import DragDropHooks from "./hooks/poll-drag-drop";
import { ChartHook } from "./hooks/chart_hook";
import VenuesMap from "./hooks/venues-map";
import MapboxVenuesMap from "./hooks/mapbox-venues-map";
import CountdownHooks from "./hooks/countdown-timer";

// Define LiveView hooks here
import R2ImageUpload from "./r2_upload";

// Import unified uploaders for Phoenix LiveView external uploads
import Uploaders from "./uploaders";

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

// R2 image upload hook for file input (uses Cloudflare R2)
Hooks.R2ImageUpload = R2ImageUpload;




// Merge modular hooks with existing hooks
const ModularHooks = {
  ...FormHooks,
  ...UIHooks,
  ...PaymentHooks,
  ...MediaHooks,
  ...PlacesHooks,
  ...DragDropHooks,
  ...CountdownHooks, // Countdown timer for threshold deadlines
  ClerkAuthHandler, // Clerk auth handler
  AuthHandler: ClerkAuthHandler, // Active auth handler (Clerk)
  ChartHook, // Chart.js hook for Phase 6
  VenuesMap, // Interactive Google Maps for venues page
  MapboxVenuesMap // Interactive Mapbox map for venues page
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
  hooks: AllHooks,
  uploaders: Uploaders  // Unified R2 uploaders for external uploads
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

// CSV download handler for admin dashboards
window.addEventListener("phx:download_csv", (e) => {
  const { filename, data } = e.detail;

  // Create a Blob from the CSV data
  const blob = new Blob([data], { type: 'text/csv;charset=utf-8;' });

  // Create a temporary download link
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);

  link.setAttribute('href', url);
  link.setAttribute('download', filename);
  link.style.visibility = 'hidden';

  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);

  // Clean up the URL object
  URL.revokeObjectURL(url);
});

// Profile share handler - uses Web Share API with clipboard fallback
window.addEventListener("eventasaurus:share-profile", (e) => {
  const { title } = e.detail;
  const url = window.location.href;

  if (navigator.share) {
    navigator.share({ title, url }).catch(() => {
      // User cancelled or share failed, silently fall back to clipboard
      navigator.clipboard.writeText(url);
    });
  } else {
    navigator.clipboard.writeText(url);
  }
});

// Connect if there are any LiveViews on the page
liveSocket.connect();

// Expose liveSocket on window for web console debug logs and latency simulation
window.liveSocket = liveSocket;

// Expose signOut function on window for logout links
window.signOut = async function() {
  await clerkSignOut();
};

// Expose Clerk auth functions on window for checkout and other pages
window.openSignIn = function(options = {}) {
  clerkOpenSignIn(options);
};

window.openSignUp = function(options = {}) {
  clerkOpenSignUp(options);
};

// Initialize components on page load
document.addEventListener("DOMContentLoaded", function() {
  // Initialize PostHog analytics with privacy checks
  posthogManager.showPrivacyBanner();
  posthogManager.init();

  // Initialize Clerk authentication
  console.log('Initializing Clerk authentication...');
  initClerkClient();
});

// Initialize modular components
initializeClipboard();

