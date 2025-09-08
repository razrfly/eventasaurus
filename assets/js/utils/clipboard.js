// Clipboard utility functions
// Extracted from app.js for better organization

function fallbackCopyTextToClipboard(text) {
  const textArea = document.createElement("textarea");
  textArea.value = text;
  textArea.style.top = "0";
  textArea.style.left = "0";
  textArea.style.position = "fixed";
  document.body.appendChild(textArea);
  textArea.focus();
  textArea.select();
  try {
    const successful = document.execCommand('copy');
    if (successful) {
      console.log("Text copied to clipboard (fallback):", text);
    } else {
      console.error("Failed to copy text (fallback)");
    }
  } catch (err) {
    console.error("Fallback copy failed:", err);
  }
  document.body.removeChild(textArea);
}

// Initialize clipboard functionality
export function initializeClipboard() {
  window.addEventListener("phx:copy_to_clipboard", (e) => {
    const text = e.detail.text;
    if (navigator.clipboard && window.isSecureContext) {
      // Use the modern clipboard API
      navigator.clipboard.writeText(text).then(() => {
        console.log("Text copied to clipboard:", text);
      }).catch(err => {
        console.error("Failed to copy text:", err);
        fallbackCopyTextToClipboard(text);
      });
    } else {
      // Fallback for older browsers
      fallbackCopyTextToClipboard(text);
    }
  });
}

export { fallbackCopyTextToClipboard };