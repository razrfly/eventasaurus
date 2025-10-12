# Places Search Hooks - Modular Geocoding Provider System

Modular geocoding provider system for Phoenix LiveView with support for multiple providers (Google Places, Mapbox, HERE, etc.).

## Architecture

```
places-search/
├── index.js                          # Main exports and backward compatibility
├── base-provider.js                  # Abstract provider interface
├── unified-places-hook.js            # Provider-agnostic LiveView hook
├── provider-factory.js               # Provider instantiation logic
└── providers/
    └── google-places-provider.js     # Google Places implementation
```

## Phase 1: Modularization (✅ Completed)

The Google Places implementation has been refactored into a modular provider system:

- **`base-provider.js`**: Defines the contract all providers must implement
- **`google-places-provider.js`**: Google Places-specific implementation
- **`unified-places-hook.js`**: Provider-agnostic hook that works with any provider
- **`provider-factory.js`**: Creates provider instances based on configuration
- **`index.js`**: Exports hooks with backward compatibility

### Backward Compatibility

All existing hook names continue to work:
- `UnifiedGooglePlaces` - New modular implementation
- `EventLocationSearch` - Alias for event mode
- `VenueSearchWithFiltering` - Alias for event mode
- `PlacesSuggestionSearch` - Alias for poll mode
- `PlacesHistorySearch` - Alias for activity mode
- `CitySearch` - Separate city-specific hook

**No template changes required** - all existing uses of these hooks continue to work.

## Usage

### In LiveView Templates

```heex
<!-- Event creation form -->
<input
  type="text"
  phx-hook="UnifiedGooglePlaces"
  data-mode="event"
  data-show-persistent="true"
  data-show-recent="true"
  placeholder="Search for a venue..."
/>

<!-- Poll creation form -->
<input
  type="text"
  phx-hook="PlacesSuggestionSearch"
  data-mode="poll"
  placeholder="Search for a location..."
/>

<!-- City search -->
<input
  type="text"
  phx-hook="CitySearch"
  placeholder="Search for a city..."
/>
```

### Provider Configuration

Currently defaults to Google Places. In Phase 3, configuration will be read from page metadata:

```javascript
// Future: Set via backend configuration
window.GEOCODING_PROVIDER = {
  name: 'mapbox',  // or 'google_places', 'here', etc.
  apiKey: 'your_api_key_here'
};
```

## Provider Interface

All providers must implement `BaseGeocodingProvider`:

```javascript
class YourProvider extends BaseGeocodingProvider {
  getName() {
    return 'your_provider';
  }

  isApiLoaded() {
    // Check if provider API is loaded
  }

  async loadApi() {
    // Load provider's JavaScript API
  }

  createAutocomplete(inputElement, options) {
    // Create autocomplete instance
  }

  onPlaceSelected(callback) {
    // Set up place selection listener
  }

  extractPlaceData(place) {
    // Normalize place data to standard format
    return {
      place_id: string,
      name: string,
      formatted_address: string,
      latitude: number,
      longitude: number,
      city: string,
      state: string,
      country: string,
      rating: number|null,
      phone: string,
      website: string,
      photos: Array<string>,
      types: Array<string>
    };
  }

  destroy() {
    // Clean up resources
  }
}
```

## Phase 2: Mapbox Provider (✅ Completed)

The Mapbox provider has been successfully implemented:

- **`providers/mapbox-provider.js`**: Mapbox Geocoding API implementation
- Uses Mapbox GL Geocoder for autocomplete functionality
- Dynamic API loading (loads Mapbox GL JS and Geocoder on-demand)
- Normalizes results to standard format
- **Provider Configuration**: Added to `root.html.heex` for dynamic provider switching
- **Limitations**: No photos or ratings (Mapbox API limitation)

### Testing Mapbox

To test the Mapbox provider:

1. Set `MAPBOX_ACCESS_TOKEN` environment variable
2. Update `window.GEOCODING_PROVIDER.name` to `'mapbox'` in `root.html.heex`
3. Test venue search autocomplete in event creation
4. Verify place data extraction and form population

## Next Steps

### Phase 3: Connect to Provider Management UI

1. Add `use_for_frontend` column to `geocoding_providers` table
2. Extend backend `ProviderConfig` with frontend provider queries
3. Inject active provider config into page via `root.html.heex`
4. Add frontend toggle to `/admin/geocoding-providers`

## Testing

The modular system maintains 100% backward compatibility:
- All existing templates continue to work without changes
- Hook names remain the same
- Event names and data formats unchanged
- LiveView integration unchanged

To verify:
1. Build assets: `mix assets.build`
2. Start server: `mix phx.server`
3. Test event creation venue search
4. Test poll creation location search
5. Verify place selection and data extraction

## Backup

The original monolithic implementation is preserved at:
- `assets/js/hooks/places-search.js.backup`

## Related Documentation

- GitHub Issue: #1683 - Modularize Frontend Geocoding Providers
- Backend Provider System: `lib/eventasaurus_discovery/geocoding/providers/`
- Admin UI: `/admin/geocoding-providers`
