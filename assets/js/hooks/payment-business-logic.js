// Payment-related hooks for Stripe and taxation validation
// Extracted from app.js for better organization

// Stripe Payment Elements Hook
export const StripePaymentElements = {
  mounted() {
    console.log("Stripe Payment Elements hook mounted");
    
    // Get client secret from the page URL params
    const urlParams = new URLSearchParams(window.location.search);
    const clientSecret = urlParams.get('client_secret');
    
    if (!clientSecret || clientSecret.length < 10) {
      console.error("No valid client_secret found in URL");
      this.pushEvent("payment_failed", {error: {message: "Missing or invalid payment session"}});
      return;
    }
    
    if (!window.Stripe) {
      console.error("Stripe.js not loaded");
      return;
    }
    
    // Initialize Stripe with publishable key
    if (!window.stripePublishableKey) {
      console.error("Stripe publishable key not found");
      return;
    }
    
    const stripe = Stripe(window.stripePublishableKey);
    
    const elements = stripe.elements({
      clientSecret: clientSecret,
      appearance: {
        theme: 'stripe',
        variables: {
          colorPrimary: '#2563eb',
          colorBackground: '#ffffff',
          colorText: '#111827',
          colorDanger: '#dc2626',
          fontFamily: 'system-ui, sans-serif',
          spacingUnit: '6px',
          borderRadius: '8px'
        }
      }
    });
    
    // Create and mount the Payment Element
    const paymentElement = elements.create('payment');
    paymentElement.mount('#stripe-payment-element');
    
    // Handle form submission
    const submitButton = document.getElementById('stripe-submit-button');
    if (submitButton) {
      submitButton.addEventListener('click', async (e) => {
        e.preventDefault();
        
        if (submitButton.disabled) return;
        
        // Disable submit button
        submitButton.disabled = true;
        
        try {
          const {error, paymentIntent} = await stripe.confirmPayment({
            elements,
            confirmParams: {
              return_url: window.location.href
            },
            redirect: 'if_required'
          });
          
          if (error) {
            console.error("Payment failed:", error);
            this.pushEvent("payment_failed", {error: error});
            submitButton.disabled = false;
          } else if (paymentIntent && paymentIntent.status === 'succeeded') {
            console.log("Payment succeeded:", paymentIntent);
            this.pushEvent("payment_succeeded", {payment_intent_id: paymentIntent.id});
          }
        } catch (err) {
          console.error("Payment error:", err);
          submitButton.disabled = false;
        }
      });
    }
    
    // Store references for cleanup
    this.stripe = stripe;
    this.elements = elements;
    this.paymentElement = paymentElement;
  },
  
  destroyed() {
    console.log("Stripe Payment Elements hook destroyed");
    if (this.paymentElement) {
      this.paymentElement.unmount();
    }
  }
};

// TaxationTypeValidator hook for enhanced taxation type selection validation
export const TaxationTypeValidator = {
  mounted() {
    this.selectElement = this.el.querySelector('select');
    this.hiddenInput = this.el.querySelector('input[type="hidden"]');
    this.priceDisplay = document.querySelector('[data-price-display]');
    
    if (!this.selectElement) {
      console.error('TaxationTypeValidator: No select element found');
      return;
    }
    
    if (!this.hiddenInput) {
      console.error('TaxationTypeValidator: No hidden input found');
      return;
    }
    
    // Initialize with current values
    this.updateHiddenField();
    this.updatePriceDisplay();
    
    // Listen for changes
    this.selectElement.addEventListener('change', this.handleTaxationChange.bind(this));
    
    // Listen for price updates from other components
    document.addEventListener('price:updated', this.handlePriceUpdate.bind(this));
  },
  
  destroyed() {
    if (this.selectElement) {
      this.selectElement.removeEventListener('change', this.handleTaxationChange.bind(this));
    }
    document.removeEventListener('price:updated', this.handlePriceUpdate.bind(this));
  },
  
  handleTaxationChange() {
    this.updateHiddenField();
    this.updatePriceDisplay();
    
    // Notify other components about the taxation change
    this.pushEvent('taxation_type_changed', {
      taxation_type: this.selectElement.value,
      display_name: this.selectElement.selectedOptions[0]?.text || ''
    });
  },
  
  updateHiddenField() {
    if (this.hiddenInput && this.selectElement) {
      const selectedOption = this.selectElement.selectedOptions[0];
      const taxationData = {
        type: this.selectElement.value,
        display_name: selectedOption?.text || '',
        rate: parseFloat(selectedOption?.dataset.rate || '0'),
        is_inclusive: selectedOption?.dataset.inclusive === 'true'
      };
      
      this.hiddenInput.value = JSON.stringify(taxationData);
      
      // Trigger change event for LiveView
      this.hiddenInput.dispatchEvent(new Event('change', { bubbles: true }));
    }
  },
  
  updatePriceDisplay() {
    if (!this.priceDisplay || !this.selectElement) return;
    
    const selectedOption = this.selectElement.selectedOptions[0];
    if (!selectedOption) return;
    
    const basePrice = parseFloat(this.priceDisplay.dataset.basePrice || '0');
    const taxRate = parseFloat(selectedOption.dataset.rate || '0');
    const isInclusive = selectedOption.dataset.inclusive === 'true';
    
    let finalPrice = basePrice;
    let taxAmount = 0;
    
    if (isInclusive) {
      // Tax is included in the base price
      taxAmount = (basePrice * taxRate) / (1 + taxRate);
      finalPrice = basePrice;
    } else {
      // Tax is added to the base price
      taxAmount = basePrice * taxRate;
      finalPrice = basePrice + taxAmount;
    }
    
    // Update the display
    this.priceDisplay.textContent = this.formatPrice(finalPrice);
    
    // Update tax breakdown if present
    const taxBreakdown = document.querySelector('[data-tax-breakdown]');
    if (taxBreakdown) {
      if (taxAmount > 0) {
        taxBreakdown.innerHTML = `
          <div class="text-sm text-gray-600">
            <div>Base price: ${this.formatPrice(basePrice)}</div>
            <div>Tax (${(taxRate * 100).toFixed(1)}%): ${this.formatPrice(taxAmount)}</div>
            <div class="font-medium">Total: ${this.formatPrice(finalPrice)}</div>
          </div>
        `;
        taxBreakdown.classList.remove('hidden');
      } else {
        taxBreakdown.classList.add('hidden');
      }
    }
    
    // Dispatch price update event
    document.dispatchEvent(new CustomEvent('price:updated', {
      detail: {
        basePrice: basePrice,
        taxAmount: taxAmount,
        finalPrice: finalPrice,
        taxRate: taxRate,
        isInclusive: isInclusive
      }
    }));
  },
  
  handlePriceUpdate(event) {
    // Handle external price updates
    if (this.priceDisplay && event.detail && typeof event.detail.basePrice !== 'undefined') {
      this.priceDisplay.dataset.basePrice = event.detail.basePrice.toString();
      this.updatePriceDisplay();
    }
  },
  
  formatPrice(amount) {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD'
    }).format(amount);
  }
};

// Export all payment hooks as a default object for easy importing
export default {
  StripePaymentElements,
  TaxationTypeValidator
};