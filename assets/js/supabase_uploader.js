// Minimal uploader for direct-to-Supabase Storage uploads
// Only needed when using the direct upload feature

const SupabaseUploaders = {};

// Direct to Supabase uploader that works with Phoenix LiveView external uploads
SupabaseUploaders.SupabaseStorage = function(entries, onViewError) {
  entries.forEach(entry => {
    // Create HTTP request
    const xhr = new XMLHttpRequest();
    
    // Allow LiveView to abort upload if needed
    onViewError(() => xhr.abort());
    
    // Handle successful completion
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        entry.progress(100);
      } else {
        entry.error();
      }
    };
    
    // Handle network errors
    xhr.onerror = () => entry.error();
    
    // Report progress back to LiveView
    xhr.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100);
        if (percent < 100) {
          entry.progress(percent);
        }
      }
    });
    
    // Perform PUT request to Supabase Storage
    xhr.open("PUT", entry.meta.url, true);
    xhr.setRequestHeader("Content-Type", entry.file.type);
    xhr.setRequestHeader("x-upsert", "true"); // Allow overwriting
    xhr.send(entry.file);
  });
};

export default SupabaseUploaders; 