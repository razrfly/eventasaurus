// Clerk authentication management
// Equivalent to supabase-manager.js for Clerk-based authentication

let clerkInstance = null;
let clerkLoaded = false;

// Wait for Clerk.js to be loaded from CDN
async function waitForClerk(maxWait = 10000, interval = 100) {
  const startTime = Date.now();

  while (!window.Clerk) {
    if (Date.now() - startTime > maxWait) {
      throw new Error('Timeout waiting for Clerk.js to load');
    }
    await new Promise(resolve => setTimeout(resolve, interval));
  }

  return window.Clerk;
}

// Initialize Clerk client
export async function initClerkClient() {
  if (clerkLoaded || typeof window === 'undefined') {
    return clerkInstance;
  }

  try {
    // Get Clerk config from meta tags
    const publishableKey = document.querySelector('meta[name="clerk-publishable-key"]')?.content;

    if (!publishableKey) {
      console.error('Missing Clerk publishable key configuration');
      return null;
    }

    // Wait for Clerk.js to be loaded (it loads async from CDN)
    try {
      await waitForClerk();
    } catch (error) {
      console.error('Clerk library not loaded. Ensure the Clerk script is included.');
      return null;
    }

    // Initialize Clerk
    await window.Clerk.load();
    clerkInstance = window.Clerk;
    clerkLoaded = true;

    console.log('Clerk client initialized successfully');

    // Set up auth state listener
    setupAuthListener();

    return clerkInstance;
  } catch (error) {
    console.error('Error initializing Clerk client:', error);
    return null;
  }
}

// Set up auth state change listener
function setupAuthListener() {
  if (!clerkInstance) return;

  // Clerk fires this when user signs in/out
  clerkInstance.addListener(({ user, session }) => {
    console.log('Clerk auth state changed:', {
      hasUser: !!user,
      hasSession: !!session
    });

    // Dispatch custom event for other components to listen to
    window.dispatchEvent(new CustomEvent('clerk:auth-change', {
      detail: { user, session }
    }));
  });
}

// ClerkAuthHandler hook to handle authentication state
// Note: Unlike Supabase, Clerk doesn't use URL hash fragments for tokens.
// Clerk uses its own session cookie (__session) which is handled automatically.
export const ClerkAuthHandler = {
  mounted() {
    this.initializeClerk();
  },

  async initializeClerk() {
    // Initialize Clerk if not already done
    await initClerkClient();

    // Check for any pending auth actions (e.g., from sign-in redirects)
    this.handlePendingAuth();
  },

  handlePendingAuth() {
    // Check URL for Clerk redirect parameters
    const url = new URL(window.location.href);

    // Clerk uses query parameters for some flows
    const redirectUrl = url.searchParams.get('redirect_url');
    const signInSuccess = url.searchParams.get('__clerk_created_session');

    if (signInSuccess) {
      // Clean up URL
      url.searchParams.delete('__clerk_created_session');
      url.searchParams.delete('redirect_url');

      const cleanUrl = url.pathname + (url.search || '');
      if (history.replaceState) {
        history.replaceState(null, '', cleanUrl);
      }

      console.log('Clerk sign-in completed, cleaned URL');

      // Notify LiveView that auth state may have changed
      this.pushEvent('clerk_auth_complete', {});
    }
  }
};

// Get current user from Clerk
export function getCurrentUser() {
  if (!clerkInstance) return null;
  return clerkInstance.user;
}

// Get current session from Clerk
export function getSession() {
  if (!clerkInstance) return null;
  return clerkInstance.session;
}

// Get the session token for API requests
export async function getSessionToken() {
  const session = getSession();
  if (!session) return null;

  try {
    return await session.getToken();
  } catch (error) {
    console.error('Error getting session token:', error);
    return null;
  }
}

// Sign out the current user
export async function signOut() {
  if (!clerkInstance) {
    console.error('Clerk not initialized');
    return;
  }

  try {
    await clerkInstance.signOut();
    // Redirect to home or login page after sign out
    window.location.href = '/';
  } catch (error) {
    console.error('Error signing out:', error);
  }
}

// Open Clerk sign-in modal
export function openSignIn(options = {}) {
  if (!clerkInstance) {
    console.error('Clerk not initialized');
    return;
  }

  clerkInstance.openSignIn({
    redirectUrl: options.redirectUrl || window.location.href,
    ...options
  });
}

// Open Clerk sign-up modal
export function openSignUp(options = {}) {
  if (!clerkInstance) {
    console.error('Clerk not initialized');
    return;
  }

  clerkInstance.openSignUp({
    redirectUrl: options.redirectUrl || window.location.href,
    ...options
  });
}

// Open Clerk user profile modal
export function openUserProfile(options = {}) {
  if (!clerkInstance) {
    console.error('Clerk not initialized');
    return;
  }

  clerkInstance.openUserProfile(options);
}

// Export the client for external use
export { clerkInstance };
