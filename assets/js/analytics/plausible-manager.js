// Plausible Analytics - Simple utility for custom event tracking
// The main script is loaded directly in root.html.heex
// This module provides a clean API for tracking custom events

/**
 * Track a custom event with Plausible
 * @param {string} eventName - The name of the event (must match goal in Plausible dashboard)
 * @param {Object} props - Optional custom properties
 * @example
 * trackEvent('Signup')
 * trackEvent('Download', { method: 'HTTP', file: 'report.pdf' })
 */
export function trackEvent(eventName, props = {}) {
  if (typeof window.plausible === 'function') {
    window.plausible(eventName, { props });
  }
}

/**
 * Track a custom event only if user has given analytics consent
 * Use this for events that might be considered more intrusive
 * @param {string} eventName - The name of the event
 * @param {Object} props - Optional custom properties
 */
export function trackEventWithConsent(eventName, props = {}) {
  const consent = getPrivacyConsent();
  if (consent.analytics && typeof window.plausible === 'function') {
    window.plausible(eventName, { props });
  }
}

/**
 * Get the current privacy consent state (shared with PostHog)
 */
function getPrivacyConsent() {
  try {
    const stored = localStorage.getItem('posthog_privacy_consent');
    if (stored) {
      return JSON.parse(stored);
    }
  } catch {
    // Ignore localStorage errors
  }
  return { analytics: true, essential: true }; // Plausible is privacy-first, default to enabled
}

// Legacy exports for backwards compatibility with existing code
export const plausibleManager = {
  trackEvent,
  trackEventWithConsent,
  // No-op init since script is loaded directly in HTML
  init: () => {},
};

export function initPlausibleClient() {
  // No-op - script is loaded directly in root.html.heex
}
