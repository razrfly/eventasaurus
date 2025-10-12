/**
 * Provider Factory
 *
 * Factory for creating geocoding provider instances.
 * Handles provider instantiation and configuration.
 */
import GooglePlacesProvider from './providers/google-places-provider.js';
import MapboxProvider from './providers/mapbox-provider.js';

class ProviderFactory {
  constructor() {
    // Registry of available providers
    this.providers = {
      'google_places': GooglePlacesProvider,
      'mapbox': MapboxProvider,
      // Future providers will be added here:
      // 'here': HereProvider,
      // 'locationiq': LocationIQProvider,
      // etc.
    };

    // Default provider if none specified
    // TODO: In Phase 3, this will be read from backend configuration
    this.defaultProvider = 'google_places';
  }

  /**
   * Get list of available provider names
   * @returns {Array<string>} Provider names
   */
  getAvailableProviders() {
    return Object.keys(this.providers);
  }

  /**
   * Check if a provider is available
   * @param {string} providerName - Provider name to check
   * @returns {boolean} True if provider exists
   */
  hasProvider(providerName) {
    return providerName in this.providers;
  }

  /**
   * Create a provider instance
   * @param {string} providerName - Name of provider to create (e.g., 'google_places')
   * @param {Object} config - Provider configuration
   * @param {string} config.apiKey - API key for the provider
   * @param {Object} config.options - Additional provider-specific options
   * @returns {Promise<BaseGeocodingProvider>} Provider instance
   * @throws {Error} If provider is unknown
   */
  async createProvider(providerName, config = {}) {
    const ProviderClass = this.providers[providerName];

    if (!ProviderClass) {
      console.error(`ProviderFactory: Unknown provider: ${providerName}`);
      console.log('Available providers:', this.getAvailableProviders());
      throw new Error(`Unknown geocoding provider: ${providerName}`);
    }

    try {
      // Instantiate provider
      const provider = new ProviderClass();

      // Initialize with configuration
      await provider.initialize(config);

      console.log(`ProviderFactory: Created provider: ${provider.getDisplayName()}`);
      return provider;
    } catch (error) {
      console.error(`ProviderFactory: Failed to create provider ${providerName}:`, error);
      throw error;
    }
  }

  /**
   * Create provider from page configuration
   * Reads provider settings from window.GEOCODING_PROVIDER or defaults to Google Places
   * @returns {Promise<BaseGeocodingProvider>} Provider instance
   */
  async createFromPageConfig() {
    // Read provider config from page (will be injected by backend in Phase 3)
    const pageConfig = window.GEOCODING_PROVIDER || {
      name: this.defaultProvider,
      apiKey: null
    };

    const providerName = pageConfig.name || this.defaultProvider;
    const config = {
      apiKey: pageConfig.apiKey,
      ...(pageConfig.options || {})
    };

    console.log(`ProviderFactory: Creating provider from page config: ${providerName}`);
    return this.createProvider(providerName, config);
  }

  /**
   * Register a new provider
   * Allows dynamic registration of providers (for testing or plugins)
   * @param {string} name - Provider name
   * @param {Function} providerClass - Provider class constructor
   */
  registerProvider(name, providerClass) {
    if (this.hasProvider(name)) {
      console.warn(`ProviderFactory: Provider ${name} already registered, overwriting`);
    }
    this.providers[name] = providerClass;
    console.log(`ProviderFactory: Registered provider: ${name}`);
  }
}

// Export singleton instance
export default new ProviderFactory();
