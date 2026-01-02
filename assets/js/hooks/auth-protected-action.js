/**
 * AuthProtectedAction Hook
 *
 * Wraps interactive elements that require authentication on CDN-cached pages.
 * Checks Clerk auth state client-side before allowing the action to proceed.
 *
 * This solves the "Islands Architecture" problem where:
 * - Page HTML is cached by CDN (same for everyone)
 * - Phoenix session cookie is stripped by Cloudflare
 * - LiveView doesn't know the user is authenticated
 * - But Clerk's __session cookie IS present (set directly by Clerk)
 *
 * The solution:
 * - If server knows user is authenticated (window.currentUser) → push LiveView event
 * - If Clerk knows user is authenticated BUT server doesn't → reload page with cache-bust
 *   (this forces a fresh server response with proper session cookies)
 * - If user is NOT authenticated → redirect to login
 *
 * Usage:
 *   <button phx-hook="AuthProtectedAction"
 *           data-auth-event="open_plan_modal"
 *           data-auth-redirect="/auth/login">
 *     Plan with Friends
 *   </button>
 *
 * Attributes:
 *   data-auth-event    - The phx-click event to fire if authenticated
 *   data-auth-redirect - Where to redirect if not authenticated (default: /auth/login)
 *   data-auth-message  - Flash message to show on redirect (optional)
 *
 * See: https://github.com/razrfly/eventasaurus/issues/3144
 */

import { initClerkClient, getCurrentUser } from "../auth/clerk-manager";

const AuthProtectedAction = {
  mounted() {
    this.event = this.el.dataset.authEvent;
    this.redirectUrl = this.el.dataset.authRedirect || "/auth/login";
    this.message = this.el.dataset.authMessage || "Please log in to continue";

    // Remove any existing phx-click to prevent double-firing
    this.el.removeAttribute("phx-click");

    // Add our click handler
    this.el.addEventListener("click", (e) => this.handleClick(e));

    // Initialize Clerk in background
    initClerkClient().catch(() => {});
  },

  async handleClick(e) {
    e.preventDefault();
    e.stopPropagation();

    // Check for server-side auth first (set in root.html.heex)
    // If this exists, the page wasn't cached (or cache is warm with our session)
    if (window.currentUser) {
      console.log("[AuthProtectedAction] Server auth found, proceeding with event:", this.event);
      this.pushEvent(this.event, {});
      return;
    }

    // Check Clerk client-side auth
    try {
      await initClerkClient();
      const user = getCurrentUser();

      if (user) {
        // User IS authenticated via Clerk, but server doesn't know (cached page)
        // Solution: Reload the page with cache-busting param to get fresh response
        // The fresh response will have proper session cookies set
        console.log("[AuthProtectedAction] Clerk auth found but page is cached, reloading...");

        const url = new URL(window.location.href);
        // Add cache-busting timestamp to bypass CDN cache
        url.searchParams.set('_refresh', Date.now().toString());
        // Add param to auto-open the modal after reload
        url.searchParams.set('open_modal', this.event);

        window.location.href = url.toString();
      } else {
        console.log("[AuthProtectedAction] No auth found, redirecting to:", this.redirectUrl);
        // Store the current URL for redirect back after login
        const returnUrl = encodeURIComponent(window.location.href);
        window.location.href = `${this.redirectUrl}?return_to=${returnUrl}`;
      }
    } catch (error) {
      console.error("[AuthProtectedAction] Error checking auth:", error);
      // On error, redirect to login as fallback
      window.location.href = this.redirectUrl;
    }
  },

  destroyed() {
    // Cleanup handled automatically by LiveView
  }
};

export default AuthProtectedAction;
