// Places search hooks for Google Places API integration
// Extracted from app.js for better organization

// UnifiedGooglePlaces hook - Main places search functionality
// Replaces EventLocationSearch, PlacesSuggestionSearch, and PlacesHistorySearch
export const UnifiedGooglePlaces = {
  mounted() {
    this.inputEl = this.el;
    this.autocomplete = null;
    this.selectedPlaceData = null;
    this.initRetryHandle = null;
    
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
    
    console.log("UnifiedGooglePlaces config:", this.config);
    
    // Initialize Google Places Autocomplete
    this.initAutocomplete();
    
    // Set up event handlers based on mode
    this.setupEventHandlers();
  },
  
  destroyed() {
    // Clean up autocomplete
    if (this.autocomplete) {
      google.maps.event.clearInstanceListeners(this.autocomplete);
      this.autocomplete = null;
    }
    
    // Clear any pending init retries
    if (this.initRetryHandle) {
      clearTimeout(this.initRetryHandle);
      this.initRetryHandle = null;
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
  
  initAutocomplete() {
    // Wait for Google Maps to load
    if (!window.google?.maps?.places) {
      this.initRetryHandle = setTimeout(() => this.initAutocomplete(), 100);
      return;
    }
    
    // Configure autocomplete based on mode and location scope
    const options = {
      fields: [
        'place_id',
        'name',
        'formatted_address',
        'geometry',
        'address_components',
        'rating',
        'price_level',
        'formatted_phone_number',
        'website',
        'photos',
        'types'
      ]
    };
    
    // Set types based on mode and location scope
    if (this.config.mode === 'event') {
      options.types = ['establishment', 'geocode'];
    } else {
      // For polls and activities, use location scope
      const types = this.getTypesForScope(this.config.locationScope);
      if (types.length > 0) {
        options.types = types;
      }
    }
    
    // Create autocomplete
    this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, options);
    
    // Apply location bias if search location is set
    if (this.config.searchLocation?.geometry) {
      const center = {
        lat: this.config.searchLocation.geometry.lat,
        lng: this.config.searchLocation.geometry.lng
      };
      
      // Create bias circle based on location scope
      let radius = 50000; // Default 50km for venues
      if (this.config.locationScope === 'city') {
        radius = 100000; // 100km for city scope
      } else if (this.config.locationScope === 'region') {
        radius = 200000; // 200km for region scope
      }
      
      try {
        this.autocomplete.setBounds(
          new google.maps.Circle({
            center: center,
            radius: radius
          }).getBounds()
        );
      } catch (error) {
        console.error('Error setting autocomplete bounds:', error);
        // Fallback to simple circle bounds
        const bounds = new google.maps.LatLngBounds();
        const offset = radius / 111000; // Rough conversion from meters to degrees
        bounds.extend(new google.maps.LatLng(center.lat - offset, center.lng - offset));
        bounds.extend(new google.maps.LatLng(center.lat + offset, center.lng + offset));
        this.autocomplete.setBounds(bounds);
      }
    }
    
    // Set up place selection handler
    this.autocomplete.addListener('place_changed', () => {
      this.handlePlaceSelection();
    });
  },
  
  getTypesForScope(scope) {
    switch(scope) {
      case 'restaurant':
        return ['restaurant', 'cafe', 'bar'];
      case 'entertainment':
        return ['movie_theater', 'museum', 'stadium', 'park', 'tourist_attraction'];
      case 'place':
      case 'venue':
        return ['establishment'];
      case 'city':
        return ['locality', 'administrative_area_level_3'];
      case 'region':
        return ['administrative_area_level_1', 'administrative_area_level_2'];
      default:
        return ['establishment'];
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
  
  handlePlaceSelection() {
    const place = this.autocomplete.getPlace();
    
    if (!place || !place.geometry) {
      console.warn('Place selection failed: incomplete place data');
      return;
    }
    
    // Extract all place data using the original comprehensive method
    this.selectedPlaceData = this.extractPlaceData(place);
    
    // Send event to LiveView based on mode
    this.sendPlaceSelectedEvent();
    
    // Update UI
    this.updateSelectionDisplay();
    
    // Hide suggestions
    this.hideSuggestions();
  },
  
  // Extract comprehensive place data - restored from original implementation
  extractPlaceData(place) {
    // Parse address components to extract city, state, country
    let city = '';
    let state = '';
    let country = '';
    
    if (place.address_components) {
      for (const component of place.address_components) {
        const types = component.types || [];
        
        if (types.includes('locality')) {
          city = component.long_name;
        } else if (types.includes('administrative_area_level_1')) {
          state = component.short_name;
        } else if (types.includes('country')) {
          country = component.long_name;
        }
      }
    }
    
    // Build comprehensive place data - matches original format exactly
    return {
      place_id: place.place_id,
      name: place.name || '',
      formatted_address: place.formatted_address || '',
      city: city,
      state: state,
      country: country,
      latitude: Math.round(place.geometry.location.lat() * 10000) / 10000,
      longitude: Math.round(place.geometry.location.lng() * 10000) / 10000,
      rating: place.rating || null,
      price_level: place.price_level || null,
      phone: place.formatted_phone_number || '',
      website: place.website || '',
      photos: place.photos?.slice(0, 3).map(p => p.getUrl({maxWidth: 400})) || [],
      types: place.types || []
    };
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
    // For polls, set the title field and submit the form
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
        html += `<div class="text-gray-600">🌐 <a href="${this.escapeHtml(place.website)}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">Website</a></div>`;
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
    return unsafe
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  },
  
  // Handle LiveView events
  handleEvent(event, payload) {
    switch(event) {
      case 'update_search_location':
        this.config.searchLocation = payload.location;
        // Reinitialize with new bias
        if (this.autocomplete) {
          this.initAutocomplete();
        }
        break;
        
      case 'set_location_scope':
        this.config.locationScope = payload.scope;
        // Reinitialize with new types
        if (this.autocomplete) {
          this.initAutocomplete();
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
  
  reconnected() {
    // Reinitialize after LiveView reconnection
    if (!this.autocomplete) {
      this.initAutocomplete();
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

// CitySearch hook for city-specific autocomplete
export const CitySearch = {
  mounted() {
    this.inputEl = this.el;
    this.initRetryHandle = null;
    
    // Configuration from data attributes for context awareness
    this.config = {
      mode: this.el.dataset.mode || 'default'
    };
    
    // Initialize Google Places autocomplete for cities
    this.initCityAutocomplete();
  },
  
  destroyed() {
    if (this.autocomplete) {
      google.maps.event.clearInstanceListeners(this.autocomplete);
      this.autocomplete = null;
    }
    
    if (this.initRetryHandle) {
      clearTimeout(this.initRetryHandle);
      this.initRetryHandle = null;
    }
  },
  
  initCityAutocomplete() {
    if (!window.google || !window.google.maps || !window.google.maps.places) {
      if (process.env.NODE_ENV !== 'production') console.log("Google Maps not loaded yet for CitySearch, waiting...");
      this.initRetryHandle = setTimeout(() => this.initCityAutocomplete(), 100);
      return;
    }
    
    this.autocomplete = new google.maps.places.Autocomplete(this.inputEl, {
      types: ['(cities)'],
      fields: ['place_id', 'name', 'formatted_address', 'geometry', 'address_components']
    });
    
    this.autocomplete.addListener('place_changed', () => {
      const place = this.autocomplete.getPlace();
      
      if (!place || !place.geometry) {
        console.warn('City selection failed: incomplete place data');
        return;
      }
      
      const cityData = {
        place_id: place.place_id,
        name: place.name,
        formatted_address: place.formatted_address,
        geometry: {
          lat: place.geometry.location.lat(),
          lng: place.geometry.location.lng()
        },
        address_components: place.address_components || []
      };
      
      // Find city and country from address components
      const addressComponents = place.address_components || [];
      addressComponents.forEach(component => {
        if (component.types.includes('locality') || component.types.includes('administrative_area_level_1')) {
          cityData.city = component.long_name;
        }
        if (component.types.includes('country')) {
          cityData.country = component.long_name;
          cityData.country_code = component.short_name;
        }
      });
      
      // Only send city selected event if we're in a context that can handle it
      // This prevents crashes when the hook is used in contexts that don't expect this event
      const componentElement = this.el.closest('[phx-click],[phx-target],[data-poll-id]');
      if (componentElement) {
        // Send to the specific component context
        this.pushEventTo(componentElement, 'city_selected', { city: cityData });
      }
      // If no specific component context found, don't send the event to prevent crashes
    });
  },
  
  getCityEventName() {
    // For now, just return city_selected as the backend expects it
    // This can be extended in the future if different contexts need different events
    return 'city_selected';
  }
};

// Backward compatibility aliases for deprecated hook names
export const EventLocationSearch = {
  ...UnifiedGooglePlaces,
  mounted() {
    // Set mode for unified hook
    this.el.dataset.mode = 'event';
    this.el.dataset.showPersistent = 'true';
    this.el.dataset.showRecent = 'true';
    
    // Delegate to unified hook
    UnifiedGooglePlaces.mounted.call(this);
  }
};

export const VenueSearchWithFiltering = EventLocationSearch;

export const PlacesSuggestionSearch = {
  ...UnifiedGooglePlaces,
  mounted() {
    // Set mode for unified hook
    this.el.dataset.mode = 'poll';
    this.el.dataset.showPersistent = 'true';
    this.el.dataset.showRecent = 'false';
    
    // Delegate to unified hook
    UnifiedGooglePlaces.mounted.call(this);
  }
};

export const PlacesHistorySearch = {
  ...UnifiedGooglePlaces,
  mounted() {
    // Set mode for unified hook
    this.el.dataset.mode = 'activity';
    this.el.dataset.showPersistent = 'true';
    this.el.dataset.showRecent = 'false';
    
    // Delegate to unified hook
    UnifiedGooglePlaces.mounted.call(this);
  }
};

// Export all places search hooks as a default object for easy importing
export default {
  UnifiedGooglePlaces,
  CitySearch,
  EventLocationSearch,
  VenueSearchWithFiltering,
  PlacesSuggestionSearch,
  PlacesHistorySearch
};