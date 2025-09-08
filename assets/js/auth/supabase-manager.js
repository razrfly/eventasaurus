// Supabase authentication management
// Extracted from app.js for better organization

// Supabase client setup for identity management
let supabaseClient = null;

// Initialize Supabase client if needed
export function initSupabaseClient() {
  if (!supabaseClient && typeof window !== 'undefined') {
    try {
      // Get Supabase config from meta tags or data attributes
      let supabaseUrl = document.querySelector('meta[name="supabase-url"]')?.content;
      let supabaseAnonKey = document.querySelector('meta[name="supabase-anon-key"]')?.content;
      
      // Fallback to body data attributes if meta tags not found
      if (!supabaseUrl || !supabaseAnonKey) {
        const body = document.body;
        supabaseUrl = body.dataset.supabaseUrl;
        supabaseAnonKey = body.dataset.supabaseApiKey;
      }
      
      console.log('Supabase config found:', { 
        hasUrl: !!supabaseUrl, 
        hasKey: !!supabaseAnonKey,
        hasSupabaseGlobal: !!window.supabase 
      });
      
      if (supabaseUrl && supabaseAnonKey && window.supabase) {
        supabaseClient = window.supabase.createClient(supabaseUrl, supabaseAnonKey);
        console.log('Supabase client initialized successfully');
      } else {
        console.error('Missing Supabase configuration or library:', {
          supabaseUrl: !!supabaseUrl,
          supabaseAnonKey: !!supabaseAnonKey,
          supabaseLibrary: !!window.supabase
        });
      }
    } catch (error) {
      console.error('Error initializing Supabase client:', error);
    }
  }
  return supabaseClient;
}

// SupabaseAuthHandler hook to handle auth tokens from URL fragments
export const SupabaseAuthHandler = {
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

// Export the client for external use
export { supabaseClient };