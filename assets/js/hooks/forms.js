// Form-related hooks for validation, synchronization, and interaction
// Extracted from app.js for better organization

// Input Sync Hook to ensure hidden fields stay in sync with LiveView state
export const InputSync = {
  mounted() {
    // This ensures the hidden input values are updated when the form is submitted
    this.handleEvent("sync_inputs", ({ values }) => {
      if (values && values[this.el.id]) {
        this.el.value = values[this.el.id];
      }
    });
  }
};

// Pricing Validator Hook - Real-time validation for flexible pricing
export const PricingValidator = {
  mounted() {
    this.validatePricing = this.validatePricing.bind(this);
    
    // Add event listeners for input changes
    this.el.addEventListener('input', this.validatePricing);
    this.el.addEventListener('blur', this.validatePricing);
    
    // Initial validation
    setTimeout(this.validatePricing, 100);
  },

  destroyed() {
    this.el.removeEventListener('input', this.validatePricing);
    this.el.removeEventListener('blur', this.validatePricing);
  },

  validatePricing() {
    const form = this.el.closest('form');
    if (!form) return;

    // Get all pricing inputs
    const basePriceInput = form.querySelector('#base-price-input');
    const minimumPriceInput = form.querySelector('#minimum-price-input');
    const suggestedPriceInput = form.querySelector('#suggested-price-input');

    // Get error elements
    const basePriceError = form.querySelector('#base-price-error');
    const minimumPriceError = form.querySelector('#minimum-price-error');
    const suggestedPriceError = form.querySelector('#suggested-price-error');

    if (!basePriceInput || !basePriceError) return;

    // Parse values
    const basePrice = parseFloat(basePriceInput.value) || 0;
    const minimumPrice = minimumPriceInput ? (parseFloat(minimumPriceInput.value) || 0) : 0;
    const suggestedPrice = suggestedPriceInput ? parseFloat(suggestedPriceInput.value) : null;

    // Clear all errors first
    this.clearError(basePriceError);
    if (minimumPriceError) this.clearError(minimumPriceError);
    if (suggestedPriceError) this.clearError(suggestedPriceError);

    // Only validate if flexible pricing fields are visible
    if (!minimumPriceInput || !suggestedPriceInput) return;

    // Validation logic
    let hasErrors = false;

    // Base price validation
    if (basePrice <= 0) {
      this.showError(basePriceError, 'Base price must be greater than 0');
      hasErrors = true;
    }

    // Minimum price validation
    if (minimumPrice < 0) {
      this.showError(minimumPriceError, 'Minimum price cannot be negative');
      hasErrors = true;
    } else if (minimumPrice > basePrice) {
      this.showError(minimumPriceError, 'Minimum price cannot exceed base price');
      hasErrors = true;
    }

    // Suggested price validation
    if (suggestedPrice !== null && !isNaN(suggestedPrice)) {
      if (suggestedPrice < minimumPrice) {
        this.showError(suggestedPriceError, 'Suggested price cannot be lower than minimum price');
        hasErrors = true;
      } else if (suggestedPrice > basePrice) {
        this.showError(suggestedPriceError, 'Suggested price cannot exceed base price');
        hasErrors = true;
      }
    }

    // Update input styling
    this.updateInputStyling(basePriceInput, !hasErrors);
    if (minimumPriceInput) this.updateInputStyling(minimumPriceInput, !hasErrors);
    if (suggestedPriceInput) this.updateInputStyling(suggestedPriceInput, !hasErrors);
  },

  showError(errorElement, message) {
    errorElement.textContent = message;
    errorElement.classList.remove('hidden');
  },

  clearError(errorElement) {
    errorElement.textContent = '';
    errorElement.classList.add('hidden');
  },

  updateInputStyling(input, isValid) {
    if (isValid) {
      input.classList.remove('border-red-500', 'focus:ring-red-500');
      input.classList.add('border-gray-300', 'focus:ring-blue-500');
    } else {
      input.classList.remove('border-gray-300', 'focus:ring-blue-500');
      input.classList.add('border-red-500', 'focus:ring-red-500');
    }
  }
};

// DateTimeSync Hook - Keeps end date/time in sync with start date/time
export const DateTimeSync = {
  mounted() {
    const startDate = this.el.querySelector('[data-role="start-date"]');
    const startTime = this.el.querySelector('[data-role="start-time"]');
    const endDate = this.el.querySelector('[data-role="end-date"]');
    const endTime = this.el.querySelector('[data-role="end-time"]');

    // Check for polling deadline fields
    const pollingDate = this.el.querySelector('[data-role="polling-deadline-date"]');
    const pollingTime = this.el.querySelector('[data-role="polling-deadline-time"]');
    const pollingHidden = this.el.querySelector('[data-role="polling-deadline"]');

    // Handle polling deadline combination
    if (pollingDate && pollingTime && pollingHidden) {
      const combinePollingDateTime = () => {
        if (pollingDate.value && pollingTime.value) {
          // Combine date and time into ISO string
          const dateTimeString = `${pollingDate.value}T${pollingTime.value}:00`;
          pollingHidden.value = dateTimeString;
        } else {
          // Clear the hidden input if either date or time is empty
          pollingHidden.value = '';
        }
        pollingHidden.dispatchEvent(new Event('change', { bubbles: true }));
      };

      // Set initial value
      combinePollingDateTime();

      // Listen for both input and change events
      const eventTypes = ['change', 'input'];
      eventTypes.forEach(eventType => {
        pollingDate.addEventListener(eventType, combinePollingDateTime);
        pollingTime.addEventListener(eventType, combinePollingDateTime);
      });

      // Store cleanup function for later removal
      this.pollingCleanup = () => {
        eventTypes.forEach(eventType => {
          pollingDate.removeEventListener(eventType, combinePollingDateTime);
          pollingTime.removeEventListener(eventType, combinePollingDateTime);
        });
      };
    }

    // Original start/end date logic
    if (!startDate || !startTime || !endDate || !endTime) return;

    // Helper: round up to next 30-min interval
    function getNextHalfHour(now) {
      let mins = now.getMinutes();
      let rounded = mins < 30 ? 30 : 0;
      let hour = now.getHours() + (mins >= 30 ? 1 : 0);
      return { hour: hour % 24, minute: rounded };
    }

    function setInitialTimes() {
      const now = new Date();
      const { hour, minute } = getNextHalfHour(now);

      // Format to HH:MM
      const pad = n => n.toString().padStart(2, '0');
      const startTimeVal = `${pad(hour)}:${pad(minute)}`;
      startTime.value = startTimeVal;

      // Set start date to today if empty
      if (!startDate.value) {
        startDate.value = now.toISOString().slice(0, 10);
      }

      // Set end date to match start date
      endDate.value = startDate.value;

      // Set end time to +1 hour
      let endHour = (hour + 1) % 24;
      endTime.value = `${pad(endHour)}:${pad(minute)}`;
    }

    // Sync end date/time when start changes
    function syncEndFields() {
      // Copy start date to end date
      endDate.value = startDate.value;
      endDate.dispatchEvent(new Event('change', { bubbles: true }));

      // Parse start time
      const [sHour, sMinute] = startTime.value.split(':').map(Number);
      let endHour = (sHour + 1) % 24;
      endTime.value = `${endHour.toString().padStart(2, '0')}:${sMinute.toString().padStart(2, '0')}`;
    }

    // On mount, set initial times if start time is empty
    if (!startTime.value) setInitialTimes();

    startDate.addEventListener('change', syncEndFields);
    startTime.addEventListener('change', syncEndFields);
  },

  destroyed() {
    // Clean up polling deadline event listeners
    if (this.pollingCleanup) {
      this.pollingCleanup();
    }
  }
};

// TimeSync Hook - For date polling mode where we only sync time fields
export const TimeSync = {
  mounted() {
    const pollingTimeField = this.el.querySelector('[data-role="polling-time"]');
    const pollingDateHidden = this.el.querySelector('[data-role="polling-date-hidden"]');
    
    if (!pollingTimeField || !pollingDateHidden) return;

    // Function to combine selected date with time
    const updateDateTime = () => {
      const selectedDate = this.el.dataset.selectedDate;
      const selectedTime = pollingTimeField.value;
      
      if (selectedDate && selectedTime) {
        const dateTimeString = `${selectedDate}T${selectedTime}:00`;
        pollingDateHidden.value = dateTimeString;
        pollingDateHidden.dispatchEvent(new Event('change', { bubbles: true }));
      }
    };

    // Listen for time changes
    pollingTimeField.addEventListener('change', updateDateTime);
    pollingTimeField.addEventListener('input', updateDateTime);
    
    // Initial sync
    updateDateTime();
  }
};

// Calendar Form Sync Hook - Updates hidden form field when calendar dates change
export const CalendarFormSync = {
  mounted() {
    // Handle calendar date selection events from the calendar component
    this.handleEvent("calendar_dates_updated", ({ dates }) => {
      // Update the hidden form field with the selected dates
      const hiddenInput = this.el.querySelector('input[type="hidden"]');
      if (hiddenInput && Array.isArray(dates)) {
        hiddenInput.value = JSON.stringify(dates);
        hiddenInput.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
    
    // Handle individual date toggles
    this.handleEvent("date_toggled", ({ date, selected }) => {
      const hiddenInput = this.el.querySelector('input[type="hidden"]');
      if (hiddenInput) {
        try {
          const currentDates = JSON.parse(hiddenInput.value || '[]');
          let updatedDates;
          
          if (selected) {
            // Add date if not already present
            updatedDates = currentDates.includes(date) ? currentDates : [...currentDates, date];
          } else {
            // Remove date
            updatedDates = currentDates.filter(d => d !== date);
          }
          
          hiddenInput.value = JSON.stringify(updatedDates);
          hiddenInput.dispatchEvent(new Event('change', { bubbles: true }));
        } catch (e) {
          console.error('Error parsing calendar dates:', e);
        }
      }
    });
  }
};

// Export all form hooks as a default object for easy importing
export default {
  InputSync,
  PricingValidator,
  DateTimeSync,
  TimeSync,
  CalendarFormSync
};