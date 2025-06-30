import QRCode from 'qrcode'

export const TicketQR = {
  mounted() {
    this.generateQRCode()
  },

  updated() {
    this.generateQRCode()
  },

  generateQRCode() {
    const canvas = this.el.querySelector('.qr-code-canvas')
    const ticketData = this.el.dataset
    
    if (canvas && ticketData.ticketId) {
      // Create ticket verification URL with proper encoding
      const baseUrl = window.location.origin
      const ticketId = encodeURIComponent(ticketData.ticketId)
      const orderId = encodeURIComponent(ticketData.orderId)
      const verificationUrl = `${baseUrl}/tickets/verify/${ticketId}?order=${orderId}`
      
      // Generate QR code
      QRCode.toCanvas(canvas, verificationUrl, {
        width: 200,
        margin: 2,
        color: {
          dark: '#000000',
          light: '#FFFFFF'
        }
      }, (error) => {
        if (error) {
          console.error('QR Code generation failed:', error)
          // Show fallback text
          canvas.style.display = 'none'
          const fallback = this.el.querySelector('.qr-fallback')
          if (fallback) {
            fallback.style.display = 'block'
            fallback.textContent = `Ticket ID: ${ticketData.ticketId}`
          }
        }
      })
    }
  }
}

// Note: Auto-initialization removed to prevent conflicts with LiveView hooks
// QR codes are initialized via LiveView's phx-hook system

// Export for use with Phoenix LiveView hooks
window.TicketQR = TicketQR 