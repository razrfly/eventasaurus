/**
 * Unified Places Hook
 *
 * Provider-agnostic LiveView hook for place autocomplete.
 * Uses provider pattern to support multiple geocoding services.
 */
import ProviderFactory from './provider-factory.js';

export const UnifiedPlacesHook = {
  async mounted() {
    this.inputEl = this.el;
    this.provider = null;
    this.selectedPlaceData = null;

    // Configuration from data attributes
    this.config = {
      // Mode: 'event' | 'poll' | 'activity'
      mode: this.el.dataset.mode || 'event',
      // Whether to show persistent selection display
      showPersistent: this.el.dataset.showPersistent !== 'false',
      // Whether to show recent locations (events only)
      showRecent: this.el.dataset.showRecent === 'true',
      // Location scope for biasing search
      locationScope: this.el.dataset.locationScope || 'place',
      // Search location for biasing
      searchLocation: this.parseSearchLocation(),
      // Whether this is required field
      required: this.el.hasAttribute('required')
    };

    console.log("UnifiedPlacesHook config:", this.config);

    // Initialize geocoding provider
    await this.initializeProvider();

    // Set up event handlers based on mode
    this.setupEventHandlers();
  },

  destroyed() {
    // Clean up provider
    if (this.provider) {
      this.provider.destroy();
      this.provider = null;
    }

    // Clean up event listeners
    if (this.inputClearHandler) {
      this.inputEl.removeEventListener('input', this.inputClearHandler);
    }
    if (this.focusHandler) {
      this.inputEl.removeEventListener('focus', this.focusHandler);
    }
    if (this.documentClickHandler) {
      document.removeEventListener('click', this.documentClickHandler);
    }
  },

  parseSearchLocation() {
    const data = this.el.dataset.searchLocation;
    if (!data) {
      console.log("No search location data found");
      return null;
    }

    try {
      const parsed = JSON.parse(data);
      console.log("Parsed search location:", parsed);
      return parsed;
    } catch (e) {
      console.error("Error parsing search location:", e, "Data:", data);
      return null;
    }
  },

  async initializeProvider() {
    try {
      // Destroy existing provider before reinitializing
      if (this.provider) {
        this.provider.destroy();
        this.provider = null;
      }

      // Create provider instance from page configuration
      this.provider = await ProviderFactory.createFromPageConfig();

      // Create autocomplete on input element
      this.provider.createAutocomplete(this.inputEl, {
        mode: this.config.mode,
        locationScope: this.config.locationScope,
        searchLocation: this.config.searchLocation
      });

      // Set up place selection handler
      this.provider.onPlaceSelected((placeData) => {
        this.handlePlaceSelection(placeData);
      });

      console.log(`UnifiedPlacesHook: Initialized with provider: ${this.provider.getDisplayName()}`);
    } catch (error) {
      console.error('UnifiedPlacesHook: Failed to initialize provider:', error);
      // Could show error to user or fallback to manual entry
    }
  },

  setupEventHandlers() {
    // Handle input clearing
    this.inputClearHandler = () => {
      if (this.inputEl.value === '') {
        this.clearSelection();
      }
    };
    this.inputEl.addEventListener('input', this.inputClearHandler);

    // Handle focus for showing suggestions
    this.focusHandler = () => {
      this.showSuggestions();
    };
    this.inputEl.addEventListener('focus', this.focusHandler);

    // Handle clicks outside to hide suggestions
    this.documentClickHandler = (e) => {
      if (!this.el.contains(e.target)) {
        this.hideSuggestions();
      }
    };
    document.addEventListener('click', this.documentClickHandler);
  },

  handlePlaceSelection(placeData) {
    if (!placeData) {
      console.warn('UnifiedPlacesHook: Place selection failed - no data');
      return;
    }

    // Store selected place data
    this.selectedPlaceData = placeData;

    // Send event to LiveView based on mode
    this.sendPlaceSelectedEvent();

    // Update UI
    this.updateSelectionDisplay();

    // Hide suggestions
    this.hideSuggestions();
  },

  sendPlaceSelectedEvent() {
    // For poll mode, use the original form field mechanism
    if (this.config.mode === 'poll') {
      this.updatePollHiddenFields();
      // Also handle form submission as in original
      this.handlePollSelection();
    } else {
      // For other modes, send LiveView events
      const eventName = this.getEventName();
      const eventData = {
        place: this.selectedPlaceData,
        mode: this.config.mode,
        input_name: this.inputEl.name || 'location'
      };

      this.pushEvent(eventName, eventData);
    }
  },

  // Restore original poll hidden field handling - scoped to current form
  updatePollHiddenFields() {
    const data = this.selectedPlaceData;
    const jsonData = JSON.stringify(data);

    // Find the form containing this input to scope field searches
    const form = this.el.closest('form');
    if (!form) {
      console.error('updatePollHiddenFields: No form found');
      return;
    }

    // Save in external_data field (what backend expects) - scoped to current form
    let externalDataField = form.querySelector('input[name="poll_option[external_data]"]');
    if (!externalDataField) {
      // Create the field if it doesn't exist
      const input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'poll_option[external_data]';
      input.value = jsonData;
      form.appendChild(input);
      externalDataField = input;
    } else {
      externalDataField.value = jsonData;
    }

    // Also set place_id and external_id for backend processing - scoped to current form
    let placeIdField = form.querySelector('input[name="poll_option[place_id]"]');
    if (!placeIdField) {
      const input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'poll_option[place_id]';
      input.value = data.place_id;
      form.appendChild(input);
    } else {
      placeIdField.value = data.place_id;
    }

    let externalIdField = form.querySelector('input[name="poll_option[external_id]"]');
    if (!externalIdField) {
      const input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'poll_option[external_id]';
      input.value = data.place_id;
      form.appendChild(input);
    } else {
      externalIdField.value = data.place_id;
    }
  },

  // Restore original poll selection handling
  handlePollSelection() {
    // Check if direct add mode is enabled
    const directAdd = this.inputEl.dataset.directAdd === 'true';

    if (directAdd && this.selectedPlaceData) {
      // Direct addition: send event to the owning component when available
      const componentElement =
        this.el.closest('[data-phx-component]') ||
        this.el.closest('[phx-target],[data-poll-id]');
      const payload = { place_data: this.selectedPlaceData };
      if (componentElement) {
        this.pushEventTo(componentElement, 'add_place', payload);
      } else {
        this.pushEvent('add_place', payload);
      }

      // Clear the form and hide it
      this.inputEl.value = '';
      this.clearSelection();
    } else {
      // Original form filling behavior
      if (this.selectedPlaceData) {
        // Set the input value to the place name for submission
        this.inputEl.value = this.selectedPlaceData.name || '';
      }

      // Submit the form after selection
      const form = this.el.closest('form');
      if (form && this.config.required) {
        // Trigger form validation
        const event = new Event('submit', { bubbles: true, cancelable: true });
        form.dispatchEvent(event);
      }
    }
  },

  getEventName() {
    const eventMap = {
      'event': 'location_selected',
      'poll': 'poll_location_selected',
      'activity': 'activity_location_selected'
    };

    return eventMap[this.config.mode] || 'location_selected';
  },

  getClearEventName() {
    const eventMap = {
      'event': 'location_cleared',
      'poll': 'poll_location_cleared',
      'activity': 'activity_location_cleared'
    };

    return eventMap[this.config.mode] || 'location_cleared';
  },

  updateSelectionDisplay() {
    if (!this.config.showPersistent || !this.selectedPlaceData) return;

    // Update input with place name
    this.inputEl.value = this.selectedPlaceData.name;

    // Show selection info if container exists
    const infoContainer = this.el.parentElement.querySelector('.place-selection-info');
    if (infoContainer) {
      infoContainer.innerHTML = this.createSelectionHTML();
      infoContainer.style.display = 'block';

      // Add clear button event handler
      const clearBtn = infoContainer.querySelector('.place-clear-btn');
      if (clearBtn) {
        clearBtn.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          this.clearSelection();
        });
      }
    }
  },

  createSelectionHTML() {
    if (!this.selectedPlaceData) return '';

    const place = this.selectedPlaceData;
    let html = `
      <div class="place-info bg-gray-50 rounded-lg p-3 mt-2">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <h4 class="font-medium text-gray-900">${this.escapeHtml(place.name)}</h4>
            <p class="text-sm text-gray-600">${this.escapeHtml(place.formatted_address)}</p>
    `;

    // Add rating if available
    if (place.rating) {
      html += `
        <div class="flex items-center mt-1">
          <div class="flex text-yellow-400">
            ${'★'.repeat(Math.floor(place.rating))}${'☆'.repeat(5 - Math.floor(place.rating))}
          </div>
          <span class="ml-1 text-sm text-gray-600">${place.rating}</span>
        </div>
      `;
    }

    // Add contact info if available
    if (place.phone || place.website) {
      html += '<div class="mt-2 text-sm">';
      if (place.phone) {
        html += `<div class="text-gray-600">📞 ${this.escapeHtml(place.phone)}</div>`;
      }
      if (place.website) {
        const sanitizedUrl = this.sanitizeUrl(place.website);
        if (sanitizedUrl) {
          html += `<div class="text-gray-600">🌐 <a href="${this.escapeHtml(sanitizedUrl)}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">Website</a></div>`;
        }
      }
      html += '</div>';
    }

    html += `
          </div>
          <button type="button" class="place-clear-btn ml-3 p-1 text-gray-400 hover:text-gray-600">
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
            </svg>
          </button>
        </div>
      </div>
    `;

    return html;
  },

  clearSelection() {
    this.selectedPlaceData = null;

    // Clear input
    this.inputEl.value = '';

    // Hide selection info
    const infoContainer = this.el.parentElement.querySelector('.place-selection-info');
    if (infoContainer) {
      infoContainer.style.display = 'none';
      infoContainer.innerHTML = '';
    }

    // Send clear event using same naming pattern as selection events
    const clearEventName = this.getClearEventName();
    this.pushEvent(clearEventName, { mode: this.config.mode });
  },

  showSuggestions() {
    // Show recent places for events mode
    if (this.config.mode === 'event' && this.config.showRecent) {
      this.showRecentPlaces();
    }
  },

  hideSuggestions() {
    // Hide provider-specific suggestions (e.g., Mapbox dropdown)
    if (this.provider && typeof this.provider.hideSuggestions === 'function') {
      this.provider.hideSuggestions();
    }

    // Hide any custom suggestion containers
    const suggestionsContainer = this.el.parentElement.querySelector('.places-suggestions');
    if (suggestionsContainer) {
      suggestionsContainer.style.display = 'none';
    }
  },

  showRecentPlaces() {
    // This would typically fetch from LiveView
    this.pushEvent('show_recent_places', { mode: this.config.mode });
  },

  escapeHtml(unsafe) {
    if (typeof unsafe !== 'string') {
      return '';
    }
    return unsafe
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  },

  sanitizeUrl(url) {
    if (!url || typeof url !== 'string') {
      return '';
    }

    // Remove any whitespace
    const trimmed = url.trim();

    // Reject javascript:, data:, and other dangerous protocols
    const dangerousProtocols = /^(javascript|data|vbscript|file|about):/i;
    if (dangerousProtocols.test(trimmed)) {
      return '';
    }

    // Accept valid http/https URLs
    if (/^https?:\/\//i.test(trimmed)) {
      return trimmed;
    }

    // Reject anything else (including protocol-relative URLs which could be dangerous)
    return '';
  },

  // Handle LiveView events
  handleEvent(event, payload) {
    switch(event) {
      case 'update_search_location':
        this.config.searchLocation = payload.location;
        // Update provider with new bias
        if (this.provider) {
          this.provider.setBounds(payload.location, this.config.locationScope);
        }
        break;

      case 'set_location_scope':
        this.config.locationScope = payload.scope;
        // Destroy and reinitialize provider with new types
        if (this.provider) {
          this.provider.destroy();
          this.provider = null;
          this.initializeProvider();
        }
        break;

      case 'clear_selection':
        this.clearSelection();
        break;
    }
  },

  updated() {
    // Handle any updates from LiveView
    const newValue = this.inputEl.value;

    // If input was cleared by LiveView, clear our selection
    if (!newValue && this.selectedPlaceData) {
      this.clearSelection();
    }

    // If input has a value but no selection, it might be from server
    if (newValue && !this.selectedPlaceData) {
      // Try to restore selection from data attributes
      this.restoreSelectionFromData();
    }
  },

  restoreSelectionFromData() {
    const placeData = this.el.dataset.selectedPlace;
    if (placeData) {
      try {
        this.selectedPlaceData = JSON.parse(placeData);
        this.updateSelectionDisplay();
      } catch (e) {
        console.error('Error parsing selected place data:', e);
      }
    }
  },

  async reconnected() {
    // Reinitialize provider after LiveView reconnection
    if (!this.provider) {
      await this.initializeProvider();
    }
  },

  beforeUpdate() {
    // Preserve input focus if needed
    this.hadFocus = document.activeElement === this.inputEl;
  },

  afterUpdate() {
    // Restore focus if it was focused before update
    if (this.hadFocus) {
      this.inputEl.focus();
    }
    // Keep the title populated for form submission
    if (this.selectedPlaceData) {
      this.inputEl.value = this.selectedPlaceData.name || this.inputEl.value;
    }
  }
};
