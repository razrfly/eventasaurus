/**
 * Places Search Hooks - Main Export
 *
 * Modular geocoding provider system for Phoenix LiveView.
 * Exports all hooks and provides backward compatibility with legacy hook names.
 */
import { UnifiedPlacesHook } from './unified-places-hook.js';

// CitySearch hook for city-specific autocomplete
// This remains separate as it has different requirements
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
      const componentElement =
        this.el.closest('[data-phx-component]') ||
        this.el.closest('[phx-click],[phx-target],[data-poll-id]');
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

// Main unified hook (new modular implementation)
export const UnifiedGooglePlaces = UnifiedPlacesHook;

// Backward compatibility aliases for deprecated hook names
// These allow existing templates to continue working without changes
export const EventLocationSearch = {
  ...UnifiedPlacesHook,
  mounted() {
    // Set mode for unified hook
    this.el.dataset.mode = 'event';
    this.el.dataset.showPersistent = 'true';
    this.el.dataset.showRecent = 'true';

    // Delegate to unified hook
    UnifiedPlacesHook.mounted.call(this);
  }
};

export const VenueSearchWithFiltering = EventLocationSearch;

export const PlacesSuggestionSearch = {
  ...UnifiedPlacesHook,
  mounted() {
    // Set mode for unified hook
    this.el.dataset.mode = 'poll';
    this.el.dataset.showPersistent = 'true';
    this.el.dataset.showRecent = 'false';

    // Delegate to unified hook
    UnifiedPlacesHook.mounted.call(this);
  }
};

export const PlacesHistorySearch = {
  ...UnifiedPlacesHook,
  mounted() {
    // Set mode for unified hook
    this.el.dataset.mode = 'activity';
    this.el.dataset.showPersistent = 'true';
    this.el.dataset.showRecent = 'false';

    // Delegate to unified hook
    UnifiedPlacesHook.mounted.call(this);
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
