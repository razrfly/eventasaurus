/**
 * AuthSyncHook - Handles cross-tab authentication synchronization
 * 
 * This hook enables synchronization of authentication state across multiple
 * browser tabs/windows using localStorage events and Phoenix LiveView events.
 */
const AuthSyncHook = {
  mounted() {
    console.log('AuthSyncHook mounted - setting up cross-tab sync');

    // Listen for storage events to sync auth state across tabs
    this.handleStorageChange = (event) => {
      if (event.key === 'auth_state_change') {
        try {
          const authData = JSON.parse(event.newValue);
          console.log('Auth state change detected from another tab:', authData);
          
          // Notify the LiveView about the auth state change
          this.pushEvent('auth_state_changed', authData);
        } catch (error) {
          console.error('Failed to parse auth state change data:', error);
        }
      }
    };

    // Add the storage event listener
    window.addEventListener('storage', this.handleStorageChange);

    // Handle auth updates from LiveView (broadcast to other tabs)
    this.handleEvent('auth_updated', (data) => {
      console.log('Broadcasting auth update to other tabs:', data);
      
      // Use a timestamp to prevent echo effects and identify recent changes
      const authUpdate = {
        ...data,
        timestamp: Date.now(),
        tabId: this.generateTabId()
      };

      // Broadcast to other tabs via localStorage
      localStorage.setItem('auth_state_change', JSON.stringify(authUpdate));
      
      // Clean up old entries (prevent localStorage bloat)
      setTimeout(() => {
        const currentValue = localStorage.getItem('auth_state_change');
        if (currentValue) {
          try {
            const parsed = JSON.parse(currentValue);
            if (parsed.timestamp === authUpdate.timestamp) {
              localStorage.removeItem('auth_state_change');
            }
          } catch (e) {
            // Silent cleanup failure
          }
        }
      }, 1000);
    });

    // Handle session validation requests
    this.handleEvent('validate_session', (data) => {
      console.log('Validating session across tabs');
      
      // Check if we have fresh auth data in localStorage
      this.checkAndSyncSessionState();
    });

    // Handle logout events
    this.handleEvent('logout_broadcast', (data) => {
      console.log('Broadcasting logout to other tabs');
      
      const logoutData = {
        event: 'logout',
        userId: data.userId,
        timestamp: Date.now(),
        tabId: this.generateTabId()
      };

      localStorage.setItem('auth_state_change', JSON.stringify(logoutData));
      
      // Also clear any cached auth data
      this.clearAuthCache();
    });

    // Check for existing auth state on mount
    this.checkAndSyncSessionState();
  },

  destroyed() {
    console.log('AuthSyncHook destroyed - cleaning up');
    
    // Remove event listeners
    if (this.handleStorageChange) {
      window.removeEventListener('storage', this.handleStorageChange);
    }
  },

  /**
   * Generate a unique tab identifier to prevent processing our own events
   */
  generateTabId() {
    if (!this.tabId) {
      this.tabId = 'tab_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now();
    }
    return this.tabId;
  },

  /**
   * Check for existing session state and sync if needed
   */
  checkAndSyncSessionState() {
    try {
      const authState = localStorage.getItem('auth_state_change');
      if (authState) {
        const parsed = JSON.parse(authState);
        
        // Only process if it's recent (within last 30 seconds) and not from this tab
        const isRecent = (Date.now() - parsed.timestamp) < 30000;
        const isFromDifferentTab = parsed.tabId !== this.generateTabId();
        
        if (isRecent && isFromDifferentTab) {
          console.log('Found recent auth state change, syncing:', parsed);
          this.pushEvent('auth_state_changed', parsed);
        }
      }
    } catch (error) {
      console.error('Failed to check session state:', error);
    }
  },

  /**
   * Clear authentication cache data
   */
  clearAuthCache() {
    // Clear any auth-related localStorage items
    const authKeys = ['auth_state_change', 'user_session', 'access_token'];
    authKeys.forEach(key => {
      try {
        localStorage.removeItem(key);
      } catch (e) {
        // Silent failure for localStorage access issues
      }
    });
  },

  /**
   * Handle beforeunload to clean up if needed
   */
  beforeUnload() {
    // Optional: Clean up tab-specific data
    console.log('Tab closing, auth sync cleanup');
  }
};

export default AuthSyncHook; 