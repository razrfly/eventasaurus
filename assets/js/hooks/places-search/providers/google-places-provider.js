/**
 * Google Places Geocoding Provider
 *
 * Implementation of BaseGeocodingProvider for Google Places API.
 * Wraps Google Maps JavaScript API Places Autocomplete functionality.
 */
import BaseGeocodingProvider from '../base-provider.js';

export default class GooglePlacesProvider extends BaseGeocodingProvider {
  constructor() {
    super();
    this.name = 'google_places';
    this.displayName = 'Google Places';
    this.initRetryHandle = null;
    this.placeChangedListener = null;
  }

  /**
   * Check if Google Maps API is loaded
   */
  isApiLoaded() {
    return !!(window.google?.maps?.places);
  }

  /**
   * Load Google Maps API (waits with retry)
   */
  async loadApi() {
    return new Promise((resolve) => {
      const checkLoaded = () => {
        if (this.isApiLoaded()) {
          resolve();
        } else {
          this.initRetryHandle = setTimeout(checkLoaded, 100);
        }
      };
      checkLoaded();
    });
  }

  /**
   * Create Google Places Autocomplete instance
   */
  createAutocomplete(inputElement, options) {
    const { mode, locationScope } = options;

    // Configure autocomplete options
    const autocompleteOptions = {
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
    if (mode === 'event') {
      autocompleteOptions.types = ['establishment', 'geocode'];
    } else {
      // For polls and activities, use location scope
      const types = this.getTypesForScope(locationScope);
      if (types.length > 0) {
        autocompleteOptions.types = types;
      }
    }

    // Create autocomplete
    this.autocompleteInstance = new google.maps.places.Autocomplete(
      inputElement,
      autocompleteOptions
    );

    // Apply location bias if provided
    if (options.searchLocation?.geometry) {
      this.setBounds(options.searchLocation, locationScope);
    }

    return this.autocompleteInstance;
  }

  /**
   * Set up place selection listener
   */
  onPlaceSelected(callback) {
    if (!this.autocompleteInstance) {
      console.error('GooglePlacesProvider: Autocomplete instance not created');
      return;
    }

    // Store listener for cleanup
    this.placeChangedListener = google.maps.event.addListener(
      this.autocompleteInstance,
      'place_changed',
      () => {
        const place = this.getSelectedPlace();
        if (place && place.geometry) {
          const normalizedPlace = this.extractPlaceData(place);
          callback(normalizedPlace);
        } else {
          console.warn('GooglePlacesProvider: Place selection failed - incomplete data');
        }
      }
    );
  }

  /**
   * Get selected place from autocomplete
   */
  getSelectedPlace() {
    if (!this.autocompleteInstance) {
      return null;
    }
    return this.autocompleteInstance.getPlace();
  }

  /**
   * Extract and normalize place data from Google Places result
   */
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
          country = component.short_name;
        }
      }
    }

    // Extract coordinates
    const latitude = place.geometry?.location?.lat?.() || 0;
    const longitude = place.geometry?.location?.lng?.() || 0;

    // Build normalized place data
    return {
      place_id: place.place_id,
      name: place.name || '',
      formatted_address: place.formatted_address || '',
      city: city,
      state: state,
      country: country,
      latitude: Math.round(latitude * 10000) / 10000,
      longitude: Math.round(longitude * 10000) / 10000,
      rating: place.rating || null,
      price_level: place.price_level || null,
      phone: place.formatted_phone_number || '',
      website: place.website || '',
      photos: place.photos?.slice(0, 3).map(p => p.getUrl({maxWidth: 400})) || [],
      types: place.types || []
    };
  }

  /**
   * Set location bounds for search bias
   */
  setBounds(location, scope) {
    if (!this.autocompleteInstance || !location?.geometry) {
      return;
    }

    const center = {
      lat: location.geometry.lat,
      lng: location.geometry.lng
    };

    // Create bias circle based on location scope
    let radius = 50000; // Default 50km for venues
    if (scope === 'city') {
      radius = 100000; // 100km for city scope
    } else if (scope === 'region') {
      radius = 200000; // 200km for region scope
    }

    try {
      this.autocompleteInstance.setBounds(
        new google.maps.Circle({
          center: center,
          radius: radius
        }).getBounds()
      );
    } catch (error) {
      console.error('GooglePlacesProvider: Error setting bounds:', error);
      // Fallback to simple circle bounds
      const bounds = new google.maps.LatLngBounds();
      const offset = radius / 111000; // Rough conversion from meters to degrees
      bounds.extend(new google.maps.LatLng(center.lat - offset, center.lng - offset));
      bounds.extend(new google.maps.LatLng(center.lat + offset, center.lng + offset));
      this.autocompleteInstance.setBounds(bounds);
    }
  }

  /**
   * Get Google Places types for location scope
   */
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
  }

  /**
   * Clean up Google Places resources
   */
  destroy() {
    // Clear retry handle
    if (this.initRetryHandle) {
      clearTimeout(this.initRetryHandle);
      this.initRetryHandle = null;
    }

    // Remove event listener
    if (this.placeChangedListener) {
      google.maps.event.removeListener(this.placeChangedListener);
      this.placeChangedListener = null;
    }

    // Clear autocomplete instance listeners
    if (this.autocompleteInstance) {
      google.maps.event.clearInstanceListeners(this.autocompleteInstance);
      this.autocompleteInstance = null;
    }

    super.destroy();
  }
}
