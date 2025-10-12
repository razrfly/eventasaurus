/**
 * Base Geocoding Provider Interface
 *
 * Abstract base class defining the contract for all geocoding providers.
 * Each provider (Google Places, Mapbox, HERE, etc.) must implement this interface.
 */
export default class BaseGeocodingProvider {
  constructor() {
    this.name = 'base';
    this.displayName = 'Base Provider';
    this.autocompleteInstance = null;
    this.config = {};
  }

  /**
   * Get provider name (used for configuration lookup)
   * @returns {string} Provider identifier (e.g., 'google_places', 'mapbox')
   */
  getName() {
    return this.name;
  }

  /**
   * Get provider display name (used in UI)
   * @returns {string} Human-readable provider name
   */
  getDisplayName() {
    return this.displayName;
  }

  /**
   * Initialize the provider with configuration
   * @param {Object} config - Provider configuration
   * @param {string} config.apiKey - API key for the provider
   * @param {Object} config.options - Additional provider-specific options
   * @returns {Promise<void>}
   */
  async initialize(config) {
    this.config = config;
    await this.loadApi();
  }

  /**
   * Check if the provider's API is loaded and ready
   * @returns {boolean} True if API is loaded
   */
  isApiLoaded() {
    throw new Error('isApiLoaded() must be implemented by provider');
  }

  /**
   * Load the provider's API/SDK
   * @returns {Promise<void>}
   */
  async loadApi() {
    throw new Error('loadApi() must be implemented by provider');
  }

  /**
   * Create autocomplete instance on input element
   * @param {HTMLInputElement} inputElement - The input element to attach autocomplete to
   * @param {Object} options - Autocomplete options
   * @param {string} options.mode - Mode: 'event', 'poll', 'activity'
   * @param {string} options.locationScope - Scope: 'place', 'city', 'region', 'venue'
   * @param {Object} options.searchLocation - Location for biasing results
   * @param {Object} options.searchLocation.geometry - Coordinates
   * @param {number} options.searchLocation.geometry.lat - Latitude
   * @param {number} options.searchLocation.geometry.lng - Longitude
   * @returns {Object} Autocomplete instance
   */
  createAutocomplete(inputElement, options) {
    throw new Error('createAutocomplete() must be implemented by provider');
  }

  /**
   * Set up place selection listener
   * @param {Function} callback - Callback function to handle place selection
   * @returns {void}
   */
  onPlaceSelected(callback) {
    throw new Error('onPlaceSelected() must be implemented by provider');
  }

  /**
   * Get the selected place from autocomplete
   * @returns {Object|null} Selected place data
   */
  getSelectedPlace() {
    throw new Error('getSelectedPlace() must be implemented by provider');
  }

  /**
   * Extract and normalize place data into standard format
   * @param {Object} place - Raw place data from provider
   * @returns {Object} Normalized place data
   * @returns {string} return.place_id - Unique place identifier
   * @returns {string} return.name - Place name
   * @returns {string} return.formatted_address - Full formatted address
   * @returns {number} return.latitude - Latitude coordinate
   * @returns {number} return.longitude - Longitude coordinate
   * @returns {string} return.city - City name
   * @returns {string} return.state - State/region code
   * @returns {string} return.country - Country code
   * @returns {number|null} return.rating - Place rating (if available)
   * @returns {number|null} return.price_level - Price level (if available)
   * @returns {string} return.phone - Phone number (if available)
   * @returns {string} return.website - Website URL (if available)
   * @returns {Array<string>} return.photos - Photo URLs (if available)
   * @returns {Array<string>} return.types - Place types/categories
   */
  extractPlaceData(place) {
    throw new Error('extractPlaceData() must be implemented by provider');
  }

  /**
   * Clean up and destroy autocomplete instance
   * @returns {void}
   */
  destroy() {
    if (this.autocompleteInstance) {
      this.autocompleteInstance = null;
    }
  }

  /**
   * Update autocomplete configuration (e.g., search location bias)
   * @param {Object} updates - Configuration updates
   * @returns {void}
   */
  updateConfig(updates) {
    this.config = { ...this.config, ...updates };
  }

  /**
   * Set location bias for search results
   * @param {Object} location - Location for biasing
   * @param {Object} location.geometry - Coordinates
   * @param {number} location.geometry.lat - Latitude
   * @param {number} location.geometry.lng - Longitude
   * @param {string} scope - Location scope: 'place', 'city', 'region'
   * @returns {void}
   */
  setBounds(location, scope) {
    throw new Error('setBounds() must be implemented by provider');
  }

  /**
   * Get types/categories for location scope
   * @param {string} scope - Scope: 'restaurant', 'entertainment', 'place', 'venue', 'city', 'region'
   * @returns {Array<string>} Provider-specific type filters
   */
  getTypesForScope(scope) {
    // Default implementation, can be overridden by provider
    switch(scope) {
      case 'restaurant':
        return ['restaurant', 'cafe', 'bar'];
      case 'entertainment':
        return ['entertainment', 'venue', 'attraction'];
      case 'place':
      case 'venue':
        return ['establishment', 'venue'];
      case 'city':
        return ['locality', 'city'];
      case 'region':
        return ['region', 'administrative'];
      default:
        return ['establishment'];
    }
  }
}
