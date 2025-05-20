// SupabaseImageUpload LiveView Hook
// This hook enables uploading images to Supabase Storage from the image picker modal
import { createClient } from '@supabase/supabase-js';

// To switch between local and production, adjust SUPABASE_URL only. The anon key is the same for both.
const SUPABASE_URL = document.body.dataset.supabaseUrl;
const SUPABASE_API_KEY = document.body.dataset.supabaseApiKey;
const BUCKET = 'event-images';

if (!SUPABASE_URL || !SUPABASE_API_KEY) {
  throw new Error("Supabase credentials are missing. Make sure your layout injects them as data attributes from .env/.env.local.");
}



const SupabaseImageUpload = {
  async mounted() {
    // Get the access token from the data attribute
    const accessToken = this.el.dataset.accessToken;
    console.log("[Supabase Upload] accessToken from dataset:", accessToken ? 'Token found (truncated for security)' : 'No token');
    
    if (!accessToken) {
      console.error("[Supabase Upload] No access token found on input element!");
      this.pushEvent('image_upload_error', { 
        error: 'Authentication error. Please refresh the page and try again.' 
      });
      return;
    }

    try {
      // Initialize Supabase client for this hook instance
      this.supabase = createClient(SUPABASE_URL, SUPABASE_API_KEY, {
        global: {
          headers: {
            'Authorization': `Bearer ${accessToken}`
          }
        }
      });
      // We'll use the access token directly in the fetch headers instead of relying on the Supabase client's auth
      
      // Set up the file input change handler
      this.el.addEventListener('change', this.handleFileUpload.bind(this));
      
    } catch (error) {
      console.error("[Supabase Upload] Initialization error:", error);
      this.pushEvent('image_upload_error', { 
        error: 'Authentication failed. Please refresh the page and try again.' 
      });
    }
  },
  
  async handleFileUpload(e) {
    const file = e.target.files[0];
    if (!file) return;
    
    // Get the access token from the input element
    const accessToken = this.el.dataset.accessToken;
    if (!accessToken) {
      console.error('[Supabase Upload] No access token available for upload');
      this.pushEvent('image_upload_error', {
        error: 'Authentication error. Please refresh the page and try again.'
      });
      return;
    }
    
    // Check file size (5MB max)
    const maxSize = 5 * 1024 * 1024; // 5MB
    if (file.size > maxSize) {
      this.pushEvent('image_upload_error', { 
        error: 'File size too large. Maximum size is 5MB.' 
      });
      return;
    }
    
    // Generate a unique filename
    const fileExt = file.name.split('.').pop();
    const fileName = `${Math.random().toString(36).substring(2, 15)}_${Date.now()}.${fileExt}`;
    const filePath = `events/${fileName}`;
    
    console.log(`[Supabase Upload] Starting upload of ${file.name} as ${filePath}`);
    
    try {
      // Upload file using Supabase SDK (best practice)
      const { data, error } = await this.supabase.storage.from(BUCKET).upload(filePath, file, {
        upsert: false
      });
      
      if (error) {
        console.error('[Supabase Upload] Upload error:', error);
        this.pushEvent('image_upload_error', {
          error: error.message || 'Unknown error during upload.'
        });
        return;
      }
      
      console.log('[Supabase Upload] Upload successful:', data);
      // Continue with your success logic here (e.g., emit event with file path, etc.)

      console.log('[Supabase Upload] Response status:', response.status);
      console.log('[Supabase Upload] Response headers:', Object.fromEntries(response.headers.entries()));
      
      // Handle non-OK responses
      if (!response.ok) {
        let errorMessage = `Upload failed with status ${response.status}`;
        try {
          const errorData = await response.json();
          console.error('[Supabase Upload] Error details:', errorData);
          errorMessage = errorData.error_description || errorData.message || errorMessage;
        } catch (e) {
          const text = await response.text();
          console.error('[Supabase Upload] Error response text:', text);
        }
        throw new Error(errorMessage);
      }
      
      // Parse successful response
      const data = await response.json().catch(e => {
        console.warn('[Supabase Upload] Failed to parse JSON response:', e);
        return null;
      });
      
      if (!data) {
        throw new Error('Received empty response from server');
      }
      
      console.log('[Supabase Upload] Upload successful:', data);
      
      // Get the public URL
      const { data: { publicUrl } } = supabase.storage
        .from(BUCKET)
        .getPublicUrl(filePath);
      
      this.pushEvent('image_uploaded', { 
        path: filePath,
        publicUrl: publicUrl
      });
      
    } catch (error) {
      console.error('[Supabase Upload] Upload failed:', error);
      
      // Log additional error details
      let errorDetails = {
        name: error.name,
        message: error.message,
        stack: error.stack,
        response: error.response,
        status: error.status,
        statusText: error.statusText,
        data: error.data,
        code: error.code
      };
      console.error('[Supabase Upload] Error details:', errorDetails);
      
      // More detailed error handling
      let userFriendlyError = 'Failed to upload image. Please try again.';
      let errorCode = '';
      
      if (error.message && error.message.includes('401')) {
        userFriendlyError = 'Authentication failed. Please refresh the page and try again.';
        errorCode = 'AUTH_ERROR';
      } else if (error.message && error.message.includes('413')) {
        userFriendlyError = 'File is too large. Please choose a smaller file.';
        errorCode = 'FILE_TOO_LARGE';
      } else if (error.message && error.message.includes('404')) {
        userFriendlyError = 'Storage bucket not found. Please check your configuration.';
        errorCode = 'BUCKET_NOT_FOUND';
      } else if (error.message) {
        userFriendlyError = error.message;
      }
      
      // Log to the server for debugging
      try {
        await fetch('/api/log_error', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            error: 'Image upload failed',
            details: errorDetails,
            timestamp: new Date().toISOString()
          })
        });
      } catch (logError) {
        console.error('Failed to log error to server:', logError);
      }
      
      this.pushEvent('image_upload_error', { 
        error: userFriendlyError,
        code: errorCode,
        details: errorDetails,
        timestamp: new Date().toISOString()
      });
    } finally {
      // Reset the input to allow selecting the same file again
      e.target.value = '';
    }
  }
};

export default SupabaseImageUpload;
