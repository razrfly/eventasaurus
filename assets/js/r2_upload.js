// R2ImageUpload LiveView Hook
// This hook enables uploading images to Cloudflare R2 Storage from the image picker modal
// Uses presigned URLs for secure direct-to-R2 uploads

const R2ImageUpload = {
  mounted() {
    // Set up the file input change handler
    this.el.addEventListener('change', this.handleFileUpload.bind(this));
  },

  async handleFileUpload(e) {
    const file = e.target.files[0];
    if (!file) return;

    // Check file size (5MB max)
    const maxSize = 5 * 1024 * 1024; // 5MB
    if (file.size > maxSize) {
      this.pushEvent('image_upload_error', {
        error: 'File size too large. Maximum size is 5MB.'
      });
      e.target.value = '';
      return;
    }

    // Validate file type
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif'];
    if (!allowedTypes.includes(file.type)) {
      this.pushEvent('image_upload_error', {
        error: 'Invalid file type. Please upload a JPEG, PNG, GIF, WEBP, or AVIF image.'
      });
      e.target.value = '';
      return;
    }

    // Get the folder from data attribute or default to 'events'
    const folder = this.el.dataset.folder || 'events';

    // Sanitize filename - only allow alphanumeric, dash, underscore, and dots
    const originalName = file.name;
    const sanitizedName = originalName.replace(/[^a-zA-Z0-9_\-\.]/g, '_');

    console.log(`[R2 Upload] Starting upload of ${originalName} to ${folder}/`);

    try {
      // Step 1: Get presigned URL from backend
      const presignResponse = await this.getPresignedUrl(folder, sanitizedName, file.type, file.size);

      if (!presignResponse.ok) {
        const errorData = await presignResponse.json();
        throw new Error(errorData.error || 'Failed to get upload URL');
      }

      const presignData = await presignResponse.json();
      console.log('[R2 Upload] Got presigned URL, uploading to R2...');

      // Step 2: Upload directly to R2 using presigned URL
      const uploadResponse = await fetch(presignData.upload_url, {
        method: 'PUT',
        headers: {
          'Content-Type': file.type
        },
        body: file
      });

      if (!uploadResponse.ok) {
        throw new Error(`Upload failed with status ${uploadResponse.status}`);
      }

      console.log('[R2 Upload] Upload successful!');

      // Step 3: Push success event with the public CDN URL
      this.pushEvent('image_uploaded', {
        path: presignData.path,
        publicUrl: presignData.public_url
      });

    } catch (error) {
      console.error('[R2 Upload] Upload failed:', error);

      let userFriendlyError = 'Failed to upload image. Please try again.';

      if (error.message) {
        if (error.message.includes('401') || error.message.includes('403')) {
          userFriendlyError = 'Authentication failed. Please refresh the page and try again.';
        } else if (error.message.includes('413')) {
          userFriendlyError = 'File is too large. Please choose a smaller file.';
        } else if (error.message.includes('network') || error.message.includes('Network')) {
          userFriendlyError = 'Network error. Please check your connection and try again.';
        } else {
          userFriendlyError = error.message;
        }
      }

      this.pushEvent('image_upload_error', {
        error: userFriendlyError
      });
    } finally {
      // Reset the input to allow selecting the same file again
      e.target.value = '';
    }
  },

  async getPresignedUrl(folder, filename, contentType, fileSize) {
    // Get CSRF token from meta tag
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');

    return fetch('/api/upload/presign', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-csrf-token': csrfToken
      },
      body: JSON.stringify({
        folder: folder,
        filename: filename,
        content_type: contentType,
        file_size: fileSize
      })
    });
  }
};

export default R2ImageUpload;
