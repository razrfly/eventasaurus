/**
 * Unified Uploaders for Phoenix LiveView External Uploads
 *
 * This module provides client-side upload handlers for direct browser-to-R2 uploads.
 * It integrates with Phoenix LiveView's external upload feature.
 *
 * Usage:
 * Register with LiveSocket in app.js:
 *
 *   import Uploaders from "./uploaders"
 *
 *   let liveSocket = new LiveSocket("/live", Socket, {
 *     params: {_csrf_token: csrfToken},
 *     uploaders: Uploaders,
 *     hooks: Hooks
 *   })
 */

let Uploaders = {}

/**
 * R2 Uploader - Direct upload to Cloudflare R2 using presigned URLs
 *
 * This uploader receives presigned PUT URLs from the server and uploads
 * files directly to R2, bypassing the Phoenix server for file data.
 *
 * Expected entry.meta format:
 * {
 *   uploader: "R2",
 *   url: "https://...",      // Presigned PUT URL
 *   public_url: "https://cdn2.wombie.com/...",  // Final CDN URL
 *   key: "folder/filename.jpg"  // Object key in bucket
 * }
 */
Uploaders.R2 = function (entries, onViewError) {
  entries.forEach(entry => {
    const xhr = new XMLHttpRequest()

    // Abort upload if the LiveView encounters an error
    onViewError(() => xhr.abort())

    // Handle successful upload
    xhr.onload = () => {
      if (xhr.status === 200) {
        // R2 returns 200 for successful PUT
        entry.progress(100)
      } else {
        console.error(`[R2 Upload] Upload failed with status ${xhr.status}:`, xhr.responseText)
        entry.error(`Upload failed: ${xhr.status}`)
      }
    }

    // Handle network errors
    xhr.onerror = () => {
      console.error('[R2 Upload] Network error during upload')
      entry.error('Network error. Please check your connection and try again.')
    }

    // Handle upload timeout
    xhr.ontimeout = () => {
      console.error('[R2 Upload] Upload timed out')
      entry.error('Upload timed out. Please try again.')
    }

    // Track upload progress
    xhr.upload.addEventListener('progress', (event) => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100)
        // Don't report 100% here - let onload handle completion
        if (percent < 100) {
          entry.progress(percent)
        }
      }
    })

    // Set a reasonable timeout (5 minutes for large files)
    xhr.timeout = 300000

    // Open PUT request to presigned URL
    const { url } = entry.meta
    xhr.open('PUT', url, true)

    // Set content type header
    xhr.setRequestHeader('Content-Type', entry.file.type)

    // Log for debugging (can be removed in production)
    if (process.env.NODE_ENV === 'development') {
      console.log(`[R2 Upload] Starting upload of ${entry.file.name} (${formatBytes(entry.file.size)})`)
    }

    // Send the file
    xhr.send(entry.file)
  })
}

/**
 * Format bytes to human readable string
 */
function formatBytes(bytes) {
  if (bytes === 0) return '0 Bytes'
  const k = 1024
  const sizes = ['Bytes', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

export default Uploaders
