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
      // Create ticket verification URL
      const baseUrl = window.location.origin
      const verificationUrl = `${baseUrl}/tickets/verify/${ticketData.ticketId}?order=${ticketData.orderId}`
      
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

// Auto-initialize QR codes on page load
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-qr-ticket]').forEach(element => {
    const hook = Object.create(TicketQR)
    hook.el = element
    hook.mounted()
  })
})

// Export for use with Phoenix LiveView hooks
window.TicketQR = TicketQR 