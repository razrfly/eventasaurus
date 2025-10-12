/**
 * Mapbox Geocoding Provider
 *
 * Implementation of BaseGeocodingProvider for Mapbox Search Box API.
 * Uses SearchBoxCore programmatic API with professional styled UI.
 *
 * API Documentation: https://docs.mapbox.com/api/search/search-box/
 * Search JS Core Reference: https://docs.mapbox.com/mapbox-search-js/api/core/
 */
import BaseGeocodingProvider from '../base-provider.js';

export default class MapboxProvider extends BaseGeocodingProvider {
  constructor() {
    super();
    this.name = 'mapbox';
    this.displayName = 'Mapbox';
    this.selectedFeature = null;
    this.inputElement = null;
    this.searchBoxCore = null;
    this.sessionToken = null;
    this.searchOptions = null;
    this.suggestionsBox = null;
    this.debounceTimer = null;
  }

  /**
   * Check if Mapbox Search JS Core is loaded
   */
  isApiLoaded() {
    return !!(window.mapboxsearchcore && window.mapboxsearchcore.SearchBoxCore);
  }

  /**
   * Load Mapbox Search JS Core library
   */
  async loadApi() {
    // Check if already loaded
    if (this.isApiLoaded()) {
      return Promise.resolve();
    }

    return new Promise((resolve, reject) => {
      const searchScript = document.createElement('script');
      searchScript.src = 'https://api.mapbox.com/search-js/v1.0.0-beta.22/core.js';
      searchScript.onload = () => {
        console.log('Mapbox Search JS Core loaded');
        resolve();
      };
      searchScript.onerror = () => reject(new Error('Failed to load Mapbox Search JS Core'));
      document.head.appendChild(searchScript);
    });
  }

  /**
   * Create Mapbox Autocomplete using SearchBoxCore API
   *
   * Uses Mapbox's programmatic SearchBoxCore API for suggest/retrieve workflow.
   * This approach integrates cleanly with LiveView's input control.
   */
  createAutocomplete(inputElement, options) {
    const { mode, locationScope, searchLocation } = options;

    // Get Mapbox access token
    const accessToken = this.config.apiKey || window.MAPBOX_ACCESS_TOKEN;
    if (!accessToken) {
      console.error('MapboxProvider: No access token configured');
      throw new Error('Mapbox access token is required');
    }

    // Store reference to LiveView input
    this.inputElement = inputElement;

    // Create SearchBoxCore instance
    this.searchBoxCore = new window.mapboxsearchcore.SearchBoxCore({ accessToken });

    // Generate session token for billing optimization
    this.sessionToken = new window.mapboxsearchcore.SessionToken();

    // Configure search options
    this.searchOptions = {
      sessionToken: this.sessionToken,
      language: 'en',
      limit: 5
    };

    // Set types based on location scope
    const types = this.getMapboxTypes(mode, locationScope);
    if (types.length > 0) {
      this.searchOptions.types = types.join(',');
    }

    // Add proximity bias if search location provided
    if (searchLocation?.geometry) {
      this.searchOptions.proximity = [
        searchLocation.geometry.lng || searchLocation.geometry.lon,
        searchLocation.geometry.lat
      ];
    }

    // Set up professional styled suggestions dropdown
    this.setupSuggestionsBox();

    // Set up input event listener
    this.setupInputListener();

    this.autocompleteInstance = this.searchBoxCore;
    return this.searchBoxCore;
  }

  /**
   * Set up input event listener for autocomplete
   */
  setupInputListener() {
    if (!this.inputElement) return;

    this.inputElement.addEventListener('input', async (e) => {
      clearTimeout(this.debounceTimer);
      const query = e.target.value.trim();

      if (query.length < 2) {
        this.hideSuggestions();
        return;
      }

      this.debounceTimer = setTimeout(async () => {
        try {
          // Call SearchBoxCore.suggest() with query and options
          const response = await this.searchBoxCore.suggest(query, this.searchOptions);

          // response.suggestions contains the search results
          if (response && response.suggestions) {
            this.showSuggestions(response.suggestions);
          } else {
            this.hideSuggestions();
          }
        } catch (error) {
          console.error('Mapbox suggest error:', error);
          this.hideSuggestions();
        }
      }, 300);
    });
  }

  /**
   * Create and set up professional styled suggestions dropdown
   */
  setupSuggestionsBox() {
    this.suggestionsBox = document.createElement('div');
    this.suggestionsBox.className = 'mapbox-autocomplete-dropdown';

    // Professional styling matching Mapbox's design
    this.suggestionsBox.style.cssText = `
      position: absolute;
      z-index: 1000;
      background: white;
      border: 1px solid #e0e0e0;
      border-radius: 6px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.15);
      max-height: 360px;
      overflow-y: auto;
      display: none;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    `;

    document.body.appendChild(this.suggestionsBox);
  }

  /**
   * Update suggestions box position relative to input
   */
  updateSuggestionsPosition() {
    if (!this.suggestionsBox || !this.inputElement) return;

    const inputRect = this.inputElement.getBoundingClientRect();
    // Position 8px below the input to avoid covering it
    this.suggestionsBox.style.top = `${inputRect.bottom + window.scrollY + 8}px`;
    this.suggestionsBox.style.left = `${inputRect.left + window.scrollX}px`;
    this.suggestionsBox.style.width = `${inputRect.width}px`;
  }

  /**
   * Show autocomplete suggestions with professional styling
   */
  showSuggestions(suggestions) {
    if (!this.suggestionsBox || !suggestions || suggestions.length === 0) {
      this.hideSuggestions();
      return;
    }

    // Update position before showing
    this.updateSuggestionsPosition();

    this.suggestionsBox.innerHTML = '';

    suggestions.forEach((suggestion, index) => {
      const item = document.createElement('div');
      item.className = 'mapbox-suggestion-item';

      // Professional list item styling
      item.style.cssText = `
        padding: 12px 16px;
        cursor: pointer;
        border-bottom: ${index < suggestions.length - 1 ? '1px solid #f0f0f0' : 'none'};
        transition: background-color 0.15s ease;
        display: flex;
        align-items: center;
        gap: 10px;
      `;

      // Add location icon
      const icon = document.createElement('div');
      icon.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M8 0C5.24 0 3 2.24 3 5c0 3.75 5 11 5 11s5-7.25 5-11c0-2.76-2.24-5-5-5zm0 7.5c-1.38 0-2.5-1.12-2.5-2.5S6.62 2.5 8 2.5s2.5 1.12 2.5 2.5S9.38 7.5 8 7.5z" fill="#6b7280"/>
        </svg>
      `;
      icon.style.flexShrink = '0';

      // Add text content
      const textContainer = document.createElement('div');
      textContainer.style.cssText = 'flex: 1; min-width: 0;';

      const name = document.createElement('div');
      name.textContent = suggestion.name || suggestion.place_formatted;
      name.style.cssText = `
        color: #1f2937;
        font-size: 14px;
        font-weight: 500;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      `;

      const address = document.createElement('div');
      address.textContent = suggestion.place_formatted || suggestion.full_address || '';
      address.style.cssText = `
        color: #6b7280;
        font-size: 12px;
        margin-top: 2px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      `;

      textContainer.appendChild(name);
      if (address.textContent) {
        textContainer.appendChild(address);
      }

      item.appendChild(icon);
      item.appendChild(textContainer);

      // Hover effects
      item.addEventListener('mouseenter', () => {
        item.style.backgroundColor = '#f9fafb';
      });

      item.addEventListener('mouseleave', () => {
        item.style.backgroundColor = 'white';
      });

      item.addEventListener('click', () => {
        this.selectSuggestion(suggestion);
      });

      this.suggestionsBox.appendChild(item);
    });

    this.suggestionsBox.style.display = 'block';
  }

  /**
   * Hide suggestions dropdown
   */
  hideSuggestions() {
    if (this.suggestionsBox) {
      this.suggestionsBox.style.display = 'none';
    }
  }

  /**
   * Handle suggestion selection and retrieve full details
   */
  async selectSuggestion(suggestion) {
    this.hideSuggestions();

    // Set input value
    if (this.inputElement) {
      this.inputElement.value = suggestion.name || suggestion.place_formatted;
    }

    // Retrieve full feature details using SearchBoxCore.retrieve()
    try {
      const response = await this.searchBoxCore.retrieve(suggestion, {
        sessionToken: this.sessionToken
      });

      if (response && response.features && response.features.length > 0) {
        const feature = response.features[0];
        this.selectedFeature = feature;
        const normalizedPlace = this.extractPlaceData(feature);

        // Trigger the callback if set
        if (this.onPlaceSelectedCallback) {
          this.onPlaceSelectedCallback(normalizedPlace);
        }
      }
    } catch (error) {
      console.error('Mapbox retrieve error:', error);
    }
  }

  /**
   * Set up place selection listener
   */
  onPlaceSelected(callback) {
    this.onPlaceSelectedCallback = callback;
  }

  /**
   * Get selected place (stored when user selects from autocomplete)
   */
  getSelectedPlace() {
    return this.selectedFeature || null;
  }

  /**
   * Extract and normalize Mapbox Search Box feature to standard format
   */
  extractPlaceData(feature) {
    // Store for later retrieval
    this.selectedFeature = feature;

    // Extract coordinates from geometry
    const coordinates = feature.geometry?.coordinates || [0, 0];
    const longitude = coordinates[0];
    const latitude = coordinates[1];

    // Extract properties
    const props = feature.properties || {};
    const name = props.name || '';
    const formattedAddress = props.full_address || props.place_formatted || '';

    // Extract city, state, country from context
    const context = props.context || {};
    const city = context.place?.name || '';
    const state = context.region?.region_code || context.region?.name || '';
    const country = context.country?.country_code || context.country?.name || '';

    // Mapbox doesn't provide business data - set to null
    const rating = null;
    const price_level = null;
    const phone = '';
    const website = '';
    const photos = [];

    // Build normalized place data
    return {
      place_id: feature.id || feature.mapbox_id || `mapbox-${Date.now()}`,
      name: name,
      formatted_address: formattedAddress,
      city: city,
      state: state,
      country: country,
      latitude: Math.round(latitude * 10000) / 10000,
      longitude: Math.round(longitude * 10000) / 10000,
      rating: rating,
      price_level: price_level,
      phone: phone,
      website: website,
      photos: photos,
      types: feature.properties?.feature_type ? [feature.properties.feature_type] : []
    };
  }

  /**
   * Set location bounds for search bias
   */
  setBounds(location, scope) {
    if (!this.searchOptions || !location?.geometry) {
      return;
    }

    // Update proximity option in search options
    this.searchOptions.proximity = [
      location.geometry.lng || location.geometry.lon,
      location.geometry.lat
    ];
  }

  /**
   * Get Mapbox Search Box types for location scope
   *
   * Mapbox types: country, region, postcode, district, place,
   * locality, neighborhood, address, poi, street, block
   */
  getMapboxTypes(mode, scope) {
    switch(scope) {
      case 'restaurant':
        return ['poi']; // Points of interest
      case 'entertainment':
        return ['poi'];
      case 'place':
      case 'venue':
        return ['poi', 'address'];
      case 'city':
        return ['place', 'locality'];
      case 'region':
        return ['region', 'district'];
      default:
        return ['poi', 'address'];
    }
  }

  /**
   * Get Mapbox-specific types for location scope
   */
  getTypesForScope(scope) {
    // Return Mapbox type strings
    return this.getMapboxTypes(null, scope);
  }

  /**
   * Clean up Mapbox resources
   */
  destroy() {
    // Clear debounce timer
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }

    // Remove suggestions box
    if (this.suggestionsBox) {
      this.suggestionsBox.remove();
      this.suggestionsBox = null;
    }

    // Clean up search box core
    if (this.searchBoxCore) {
      this.searchBoxCore = null;
    }

    this.selectedFeature = null;
    this.inputElement = null;
    this.onPlaceSelectedCallback = null;
    this.sessionToken = null;
    this.searchOptions = null;

    super.destroy();
  }
}
