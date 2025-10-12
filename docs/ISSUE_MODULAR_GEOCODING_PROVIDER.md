# Modularize Geocoding Provider: Replace Google Places with Mapbox Search.js

## Overview

Replace Google Places API with Mapbox Search.js as the default geocoding provider for private event venue search, while maintaining a modular architecture that allows easy switching between providers (Google, Mapbox, Geoapify, etc.).

## Problem Statement

**Current Implementation:**
- Private event forms use Google Places JavaScript API for venue autocomplete
- Tightly coupled to Google Places SDK in `places-search.js` (580 lines)
- Database stores Google-specific `place_id` with unique constraint
- Cost: ~$5-10/month for private event autocomplete
- No ability to switch providers without significant refactoring

**Desired State:**
- Use Mapbox Search.js as default provider (free tier: 100K requests/month)
- Maintain modular architecture for easy provider switching
- Preserve option to revert to Google or add other providers
- Support provider-specific metadata while maintaining consistency

## Goals

1. **Switch to Mapbox** as default geocoding provider for private events
2. **Modular Architecture** - Easy to switch between Google, Mapbox, Geoapify, MapTiler
3. **Backward Compatibility** - Existing Google Places data continues to work
4. **Provider-Agnostic Database** - Schema supports multiple providers
5. **Cost Reduction** - Reduce geocoding costs by ~90% (~$0.50/month vs $5-10/month)
6. **Future-Proof** - Easy to add new providers or revert to Google

## Non-Goals

- ❌ Migrating public event scrapers (already use OSM with Google fallback)
- ❌ Implementing all providers at once (focus on Mapbox + Google)
- ❌ Changing venue deduplication logic in VenueStore
- ❌ Rich metadata (ratings, photos) from Mapbox (not available)

## Technical Design

### 1. Database Schema Changes

**Add geocoding_provider field:**

```elixir
# priv/repo/migrations/YYYYMMDD_add_geocoding_provider_to_venues.exs
defmodule EventasaurusApp.Repo.Migrations.AddGeocodingProviderToVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :geocoding_provider, :string
    end

    # Backfill existing venues with place_id
    execute """
    UPDATE venues
    SET geocoding_provider = 'google'
    WHERE place_id IS NOT NULL AND source = 'google'
    """, ""
  end
end
```

**Keep `place_id` for backward compatibility:**
- Continue using for Google Place IDs
- For Mapbox, store `mapbox_id` in metadata
- For other providers, store provider-specific IDs in metadata

**Standardized Metadata Structure:**

```json
{
  "provider": "mapbox",
  "mapbox": {
    "mapbox_id": "dXJuOm1ieHBvaTo...",
    "categories": ["restaurant", "bar"],
    "context": {
      "postcode": "10001",
      "region": "New York"
    }
  },
  "google": {
    "place_id": "ChIJ...",
    "rating": 4.5,
    "price_level": 2,
    "photos": ["https://..."],
    "phone": "+1-555-0123",
    "website": "https://example.com"
  }
}
```

**Update Venue Model:**

```elixir
# lib/eventasaurus_app/venues/venue.ex
schema "venues" do
  field(:geocoding_provider, :string)  # 'google', 'mapbox', 'geoapify', 'osm'
  # ... existing fields
end

def changeset(venue, attrs) do
  venue
  |> cast(attrs, [..., :geocoding_provider])
  |> validate_inclusion(:geocoding_provider,
      ["google", "mapbox", "geoapify", "osm", "user"])
  # ... rest of changeset
end
```

### 2. Frontend Provider Abstraction

**New File Structure:**

```
assets/js/hooks/
  ├─ geocoding-search.js (main hook, replaces places-search.js)
  └─ geocoding-providers/
      ├─ base-provider.js (abstract interface)
      ├─ google-provider.js (Google Places implementation)
      ├─ mapbox-provider.js (Mapbox Search.js implementation)
      └─ provider-factory.js (runtime provider selection)
```

**Unified Data Format:**

All providers normalize responses to this format:

```javascript
{
  provider: "mapbox",           // or "google", "geoapify"
  external_id: "mapbox_id...",  // provider's unique identifier
  name: "Blue Note Jazz Club",
  formatted_address: "131 W 3rd St, New York, NY 10012",
  coordinates: {
    lat: 40.7308,
    lng: -74.0014
  },
  address_components: {
    street: "131 W 3rd St",
    city: "New York",
    state: "NY",
    country: "US",
    postal_code: "10012"
  },
  provider_data: {
    // Provider-specific metadata preserved here
    mapbox: { mapbox_id: "...", categories: [...], context: {...} }
  }
}
```

**Base Provider Interface:**

```javascript
// assets/js/hooks/geocoding-providers/base-provider.js
export class BaseGeocodingProvider {
  constructor(config) {
    this.config = config;
  }

  async initialize() {
    throw new Error('Not implemented');
  }

  async search(query) {
    throw new Error('Not implemented');
  }

  normalizeResult(providerData) {
    throw new Error('Not implemented');
  }

  destroy() {
    // Cleanup
  }
}
```

**Mapbox Provider Implementation:**

```javascript
// assets/js/hooks/geocoding-providers/mapbox-provider.js
import { BaseGeocodingProvider } from './base-provider';

export class MapboxProvider extends BaseGeocodingProvider {
  async initialize() {
    if (!window.mapboxsearch) {
      await this.loadMapboxScript();
    }

    this.searchBox = mapboxsearch.autofill({
      accessToken: this.config.accessToken,
      options: {
        country: this.config.country || 'us',
        language: this.config.language || 'en'
      }
    });
  }

  async search(query) {
    const url = `https://api.mapbox.com/search/searchbox/v1/suggest?q=${encodeURIComponent(query)}&access_token=${this.config.accessToken}`;
    const response = await fetch(url);
    const data = await response.json();

    return data.suggestions.map(s => this.normalizeResult(s));
  }

  async retrieve(mapboxId) {
    const url = `https://api.mapbox.com/search/searchbox/v1/retrieve/${mapboxId}?access_token=${this.config.accessToken}`;
    const response = await fetch(url);
    const data = await response.json();

    return this.normalizeResult(data.features[0]);
  }

  normalizeResult(mapboxFeature) {
    const props = mapboxFeature.properties;
    const coords = mapboxFeature.geometry.coordinates;

    return {
      provider: 'mapbox',
      external_id: props.mapbox_id,
      name: props.name,
      formatted_address: props.full_address || props.place_formatted,
      coordinates: {
        lat: coords[1],
        lng: coords[0]
      },
      address_components: {
        street: props.address,
        city: props.context?.place?.name,
        state: props.context?.region?.region_code,
        country: props.context?.country?.country_code,
        postal_code: props.context?.postcode?.name
      },
      provider_data: {
        mapbox: {
          mapbox_id: props.mapbox_id,
          categories: props.poi_category || [],
          context: props.context
        }
      }
    };
  }
}
```

**Google Provider (Refactored):**

```javascript
// assets/js/hooks/geocoding-providers/google-provider.js
import { BaseGeocodingProvider } from './base-provider';

export class GoogleProvider extends BaseGeocodingProvider {
  async initialize() {
    if (!window.google?.maps?.places) {
      throw new Error('Google Maps not loaded');
    }

    this.autocomplete = new google.maps.places.Autocomplete(
      this.config.inputElement,
      {
        fields: ['place_id', 'name', 'formatted_address', 'geometry',
                 'address_components', 'rating', 'price_level',
                 'formatted_phone_number', 'website', 'photos', 'types']
      }
    );
  }

  normalizeResult(googlePlace) {
    // Extract address components
    let city = '', state = '', country = '', postal_code = '';
    for (const component of googlePlace.address_components || []) {
      const types = component.types;
      if (types.includes('locality')) city = component.long_name;
      if (types.includes('administrative_area_level_1')) state = component.short_name;
      if (types.includes('country')) country = component.short_name;
      if (types.includes('postal_code')) postal_code = component.long_name;
    }

    return {
      provider: 'google',
      external_id: googlePlace.place_id,
      name: googlePlace.name,
      formatted_address: googlePlace.formatted_address,
      coordinates: {
        lat: googlePlace.geometry.location.lat(),
        lng: googlePlace.geometry.location.lng()
      },
      address_components: {
        city,
        state,
        country,
        postal_code
      },
      provider_data: {
        google: {
          place_id: googlePlace.place_id,
          rating: googlePlace.rating,
          price_level: googlePlace.price_level,
          phone: googlePlace.formatted_phone_number,
          website: googlePlace.website,
          photos: googlePlace.photos?.slice(0, 3).map(p => p.getUrl({maxWidth: 400})) || [],
          types: googlePlace.types
        }
      }
    };
  }
}
```

**Provider Factory:**

```javascript
// assets/js/hooks/geocoding-providers/provider-factory.js
import { GoogleProvider } from './google-provider';
import { MapboxProvider } from './mapbox-provider';

export class ProviderFactory {
  static create(providerName, config) {
    switch(providerName) {
      case 'google':
        return new GoogleProvider(config);
      case 'mapbox':
        return new MapboxProvider(config);
      default:
        throw new Error(`Unknown provider: ${providerName}`);
    }
  }
}
```

**Updated Main Hook:**

```javascript
// assets/js/hooks/geocoding-search.js
import { ProviderFactory } from './geocoding-providers/provider-factory';

export const UnifiedGeocodingSearch = {
  mounted() {
    this.inputEl = this.el;

    // Get provider from data attribute (default to mapbox)
    const providerName = this.el.dataset.geocodingProvider || 'mapbox';

    // Provider-specific configuration
    const providerConfig = {
      inputElement: this.inputEl,
      accessToken: this.el.dataset.mapboxToken,
      apiKey: this.el.dataset.googleApiKey,
      country: this.el.dataset.country || 'us'
    };

    // Create provider instance
    this.provider = ProviderFactory.create(providerName, providerConfig);
    this.provider.initialize();

    this.setupEventHandlers();
  },

  async handlePlaceSelection(providerData) {
    // Provider normalizes to unified format
    const normalizedData = this.provider.normalizeResult(providerData);

    // Send to LiveView (same event, compatible format)
    this.pushEvent('location_selected', {
      place: normalizedData,
      mode: this.config.mode
    });

    this.updateSelectionDisplay(normalizedData);
  }
};
```

### 3. Backend Changes

**Update LiveView Handler:**

```elixir
# lib/eventasaurus_web/live/event_live/new.ex (and edit.ex)
def handle_event("location_selected", %{"place" => place_data}, socket) do
  # Extract provider information
  provider = place_data["provider"] || "google"
  external_id = place_data["external_id"]

  # Update form data with unified structure
  form_data =
    (socket.assigns.form_data || %{})
    |> Map.put("venue_name", place_data["name"])
    |> Map.put("venue_address", place_data["formatted_address"])
    |> Map.put("venue_city", get_in(place_data, ["address_components", "city"]))
    |> Map.put("venue_state", get_in(place_data, ["address_components", "state"]))
    |> Map.put("venue_country", get_in(place_data, ["address_components", "country"]))
    |> Map.put("venue_external_id", external_id)
    |> Map.put("venue_geocoding_provider", provider)
    |> Map.put("venue_latitude", get_in(place_data, ["coordinates", "lat"]))
    |> Map.put("venue_longitude", get_in(place_data, ["coordinates", "lng"]))
    |> Map.put("venue_provider_data", place_data["provider_data"])
    |> Map.put("is_virtual", false)

  # For backward compatibility with Google place_id
  form_data =
    if provider == "google" do
      Map.put(form_data, "venue_place_id", external_id)
    else
      form_data
    end

  # ... rest of handler logic
  {:noreply, assign(socket, form_data: form_data, ...)}
end
```

**Update Venue Creation:**

```elixir
# In event save handler (new.ex and edit.ex)
venue_attrs = %{
  name: form_data["venue_name"],
  address: form_data["venue_address"],
  latitude: form_data["venue_latitude"],
  longitude: form_data["venue_longitude"],
  city_id: city_id,
  geocoding_provider: form_data["venue_geocoding_provider"],
  source: if(form_data["venue_geocoding_provider"] == "google", do: "google", else: "user"),
  metadata: build_venue_metadata(
    form_data["venue_geocoding_provider"],
    form_data["venue_provider_data"],
    form_data["venue_external_id"]
  )
}

# For Google compatibility
venue_attrs =
  if form_data["venue_geocoding_provider"] == "google" do
    Map.put(venue_attrs, :place_id, form_data["venue_external_id"])
  else
    venue_attrs
  end

case VenueStore.find_or_create_venue(venue_attrs) do
  {:ok, venue} -> # continue
  {:error, reason} -> # handle error
end
```

**Helper Function:**

```elixir
defp build_venue_metadata(provider, provider_data, external_id) do
  %{
    "provider" => provider,
    provider => Map.merge(
      provider_data[provider] || %{},
      %{"external_id" => external_id}
    )
  }
end
```

### 4. UI Changes

**Simplified Venue Display (No Rich Metadata for Mapbox):**

Update venue selection display to conditionally show rich metadata only for Google:

```javascript
// In geocoding-search.js
createSelectionHTML(place) {
  const hasRichData = place.provider === 'google' &&
                      place.provider_data?.google;

  let html = `
    <div class="place-info bg-gray-50 rounded-lg p-3 mt-2">
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <h4 class="font-medium text-gray-900">${this.escapeHtml(place.name)}</h4>
          <p class="text-sm text-gray-600">${this.escapeHtml(place.formatted_address)}</p>

          <!-- Provider attribution -->
          <p class="text-xs text-gray-500 mt-1">
            📍 Powered by ${place.provider === 'google' ? 'Google Places' : 'Mapbox'}
          </p>
  `;

  // Show rich metadata only for Google
  if (hasRichData) {
    const googleData = place.provider_data.google;

    if (googleData.rating) {
      html += `
        <div class="flex items-center mt-2">
          <div class="flex text-yellow-400">
            ${'★'.repeat(Math.floor(googleData.rating))}${'☆'.repeat(5 - Math.floor(googleData.rating))}
          </div>
          <span class="ml-1 text-sm text-gray-600">${googleData.rating}</span>
        </div>
      `;
    }

    if (googleData.phone || googleData.website) {
      html += '<div class="mt-2 text-sm">';
      if (googleData.phone) {
        html += `<div class="text-gray-600">📞 ${this.escapeHtml(googleData.phone)}</div>`;
      }
      if (googleData.website) {
        html += `<div class="text-gray-600">🌐 <a href="${this.escapeHtml(googleData.website)}" target="_blank" class="text-blue-600 hover:underline">Website</a></div>`;
      }
      html += '</div>';
    }
  }

  html += `
          </div>
          <button type="button" class="place-clear-btn">
            <!-- X icon -->
          </button>
        </div>
      </div>
  `;

  return html;
}
```

### 5. Configuration

**Runtime Config:**

```elixir
# config/runtime.exs
config :eventasaurus, :geocoding,
  default_provider: System.get_env("GEOCODING_PROVIDER", "mapbox"),
  mapbox_token: System.get_env("MAPBOX_PUBLIC_TOKEN"),
  google_api_key: System.get_env("GOOGLE_MAPS_API_KEY")
```

**LiveView Template:**

```heex
<!-- lib/eventasaurus_web/live/event_live/form.html.heex -->
<input
  type="text"
  name="location_search"
  phx-hook="UnifiedGeocodingSearch"
  data-geocoding-provider={Application.get_env(:eventasaurus, :geocoding)[:default_provider]}
  data-mapbox-token={Application.get_env(:eventasaurus, :geocoding)[:mapbox_token]}
  data-google-api-key={Application.get_env(:eventasaurus, :geocoding)[:google_api_key]}
  data-mode="event"
  placeholder="Search for venue..."
/>
```

**Feature Flag:**

```elixir
# config/runtime.exs
config :eventasaurus, :features,
  use_mapbox_geocoding: System.get_env("USE_MAPBOX_GEOCODING", "false") == "true"
```

## Implementation Plan

### Phase 1: Database Preparation (1 day)
- [ ] Create migration for `geocoding_provider` field
- [ ] Backfill existing Google venues
- [ ] Update Venue model with new field validation
- [ ] Test venue creation with new field

**Files to modify:**
- `priv/repo/migrations/YYYYMMDD_add_geocoding_provider_to_venues.exs` (new)
- `lib/eventasaurus_app/venues/venue.ex`

### Phase 2: Frontend Abstraction (3-5 days)
- [ ] Create provider abstraction structure
- [ ] Implement `BaseGeocodingProvider` interface
- [ ] Implement `MapboxProvider` class
- [ ] Refactor existing code into `GoogleProvider` class
- [ ] Create `ProviderFactory`
- [ ] Update main hook to use provider abstraction
- [ ] Test autocomplete with both providers locally

**Files to create:**
- `assets/js/hooks/geocoding-providers/base-provider.js`
- `assets/js/hooks/geocoding-providers/mapbox-provider.js`
- `assets/js/hooks/geocoding-providers/google-provider.js`
- `assets/js/hooks/geocoding-providers/provider-factory.js`

**Files to modify:**
- Rename `assets/js/hooks/places-search.js` → `geocoding-search.js`
- Update `assets/js/app.js` to import new hook

### Phase 3: Backend Integration (2 days)
- [ ] Update `location_selected` handler in new.ex
- [ ] Update `location_selected` handler in edit.ex
- [ ] Add `build_venue_metadata/3` helper
- [ ] Update venue creation logic to handle provider data
- [ ] Test venue creation flow end-to-end

**Files to modify:**
- `lib/eventasaurus_web/live/event_live/new.ex`
- `lib/eventasaurus_web/live/event_live/edit.ex`

### Phase 4: UI Updates (1-2 days)
- [ ] Update venue display to conditionally show rich metadata
- [ ] Add provider attribution ("Powered by Mapbox/Google")
- [ ] Update CSS if needed for simplified cards
- [ ] Test responsive design
- [ ] Cross-browser testing

**Files to modify:**
- `assets/js/hooks/geocoding-search.js` (display methods)
- CSS files if needed

### Phase 5: Configuration & Testing (2-3 days)
- [ ] Add runtime configuration
- [ ] Implement feature flags
- [ ] Add environment variables to deployment
- [ ] Write unit tests for provider normalization
- [ ] Write integration tests for venue creation
- [ ] Manual QA testing

**Files to modify:**
- `config/runtime.exs`
- `.env.example`

**Files to create:**
- `test/eventasaurus_web/live/event_live/geocoding_test.exs`
- `test/eventasaurus_app/venues/multi_provider_test.exs`

### Phase 6: Gradual Rollout (1-2 weeks)
- [ ] Deploy to staging with Mapbox at 100%
- [ ] Test manually and run automated tests
- [ ] Deploy to production with feature flag OFF (Google still default)
- [ ] Enable Mapbox for 10% of users
- [ ] Monitor error rates, venue creation success, response times
- [ ] Increase to 50% if metrics good (3-5 days)
- [ ] Monitor for 1 week
- [ ] Increase to 100% if no issues
- [ ] Keep Google code for 3 months as fallback
- [ ] Remove Google fallback code after monitoring period

**Monitoring Metrics:**
- Venue autocomplete error rate (target: <5%)
- Venue creation success rate (target: >90%)
- Response time p95 (target: <500ms)
- API fallback frequency (should be 0% after rollout)
- User-reported issues

**Rollback Criteria:**
- Error rate >10% increase
- Venue success rate <85%
- Response time >1s p95
- Multiple user complaints

## Testing Strategy

### Unit Tests

```elixir
# test/eventasaurus_app/venues/multi_provider_test.exs
defmodule EventasaurusApp.Venues.MultiProviderTest do
  use EventasaurusApp.DataCase

  describe "multi-provider venue creation" do
    test "creates venue with Mapbox data" do
      attrs = %{
        name: "Test Venue",
        latitude: 40.7128,
        longitude: -74.0060,
        city_id: insert(:city).id,
        geocoding_provider: "mapbox",
        metadata: %{
          "provider" => "mapbox",
          "mapbox" => %{
            "mapbox_id" => "test123",
            "categories" => ["restaurant"]
          }
        }
      }

      assert {:ok, venue} = Venues.create_venue(attrs)
      assert venue.geocoding_provider == "mapbox"
      assert venue.metadata["provider"] == "mapbox"
      assert venue.metadata["mapbox"]["mapbox_id"] == "test123"
    end

    test "backward compatible with Google place_id" do
      attrs = %{
        name: "Google Venue",
        latitude: 40.7128,
        longitude: -74.0060,
        city_id: insert(:city).id,
        place_id: "ChIJ123",
        geocoding_provider: "google",
        metadata: %{
          "provider" => "google",
          "google" => %{
            "place_id" => "ChIJ123",
            "rating" => 4.5
          }
        }
      }

      assert {:ok, venue} = Venues.create_venue(attrs)
      assert venue.place_id == "ChIJ123"
      assert venue.geocoding_provider == "google"
      assert venue.metadata["google"]["rating"] == 4.5
    end
  end
end
```

### Frontend Tests

```javascript
// test/frontend/geocoding_providers_test.js
describe('Geocoding Provider Abstraction', () => {
  test('MapboxProvider normalizes results correctly', () => {
    const provider = new MapboxProvider({accessToken: 'test'});
    const mapboxData = {
      properties: {
        mapbox_id: 'test123',
        name: 'Test Venue',
        full_address: '123 Main St, New York, NY',
        context: {
          place: { name: 'New York' },
          region: { region_code: 'NY' },
          country: { country_code: 'US' }
        }
      },
      geometry: { coordinates: [-74.006, 40.7128] }
    };

    const normalized = provider.normalizeResult(mapboxData);

    expect(normalized.provider).toBe('mapbox');
    expect(normalized.external_id).toBe('test123');
    expect(normalized.name).toBe('Test Venue');
    expect(normalized.coordinates.lat).toBe(40.7128);
    expect(normalized.coordinates.lng).toBe(-74.006);
    expect(normalized.address_components.city).toBe('New York');
  });

  test('GoogleProvider normalizes results correctly', () => {
    const provider = new GoogleProvider({apiKey: 'test'});
    const googleData = {
      place_id: 'ChIJ123',
      name: 'Test Venue',
      formatted_address: '123 Main St, New York, NY 10001',
      geometry: {
        location: {
          lat: () => 40.7128,
          lng: () => -74.006
        }
      },
      address_components: [
        { types: ['locality'], long_name: 'New York', short_name: 'NYC' },
        { types: ['administrative_area_level_1'], long_name: 'New York', short_name: 'NY' },
        { types: ['country'], long_name: 'United States', short_name: 'US' }
      ],
      rating: 4.5,
      price_level: 2
    };

    const normalized = provider.normalizeResult(googleData);

    expect(normalized.provider).toBe('google');
    expect(normalized.external_id).toBe('ChIJ123');
    expect(normalized.name).toBe('Test Venue');
    expect(normalized.provider_data.google.rating).toBe(4.5);
  });

  test('ProviderFactory creates correct provider', () => {
    const mapboxProvider = ProviderFactory.create('mapbox', {accessToken: 'test'});
    expect(mapboxProvider).toBeInstanceOf(MapboxProvider);

    const googleProvider = ProviderFactory.create('google', {apiKey: 'test'});
    expect(googleProvider).toBeInstanceOf(GoogleProvider);
  });
});
```

### Integration Tests

```elixir
# test/eventasaurus_web/live/event_live/geocoding_integration_test.exs
defmodule EventasaurusWeb.EventLive.GeocodingIntegrationTest do
  use EventasaurusWeb.ConnCase
  import Phoenix.LiveViewTest

  test "creates event with Mapbox venue data", %{conn: conn} do
    user = insert(:user)
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, "/events/new")

    # Simulate Mapbox location selection
    place_data = %{
      "provider" => "mapbox",
      "external_id" => "mapbox123",
      "name" => "Test Venue",
      "formatted_address" => "123 Main St, NYC",
      "coordinates" => %{"lat" => 40.7128, "lng" => -74.006},
      "address_components" => %{
        "city" => "New York",
        "state" => "NY",
        "country" => "US"
      },
      "provider_data" => %{
        "mapbox" => %{
          "mapbox_id" => "mapbox123",
          "categories" => ["restaurant"]
        }
      }
    }

    view
    |> element("form")
    |> render_hook("location_selected", %{"place" => place_data, "mode" => "event"})

    # Fill out rest of form and submit
    view
    |> form("#event-form", event: %{
      title: "Test Event",
      start_date: "2025-12-01",
      start_time: "19:00"
    })
    |> render_submit()

    # Verify venue was created with Mapbox data
    venue = Repo.get_by(Venue, name: "Test Venue")
    assert venue.geocoding_provider == "mapbox"
    assert venue.metadata["provider"] == "mapbox"
    assert venue.metadata["mapbox"]["mapbox_id"] == "mapbox123"
  end
end
```

## Risks & Mitigation

### Risk: Data Quality Degradation
**Impact:** High
**Likelihood:** Medium (OSM/Mapbox data varies by region)
**Mitigation:**
- Keep Google as fallback option in code
- Geographic rollout (US/Europe first where OSM/Mapbox best)
- Monitor venue creation success rates (target: >90%)
- Easy rollback via feature flag
- Compare Mapbox vs Google results side-by-side during testing

### Risk: Missing Rich Metadata
**Impact:** Medium
**Likelihood:** High (Mapbox doesn't provide ratings, photos, phone, website)
**Mitigation:**
- Clear UI messaging about limited information available
- Optional "Enhance with Google Places" button for future enhancement
- Survey users to understand if metadata is actually used
- Focus on US/Europe where Mapbox data quality is best

### Risk: User Resistance to Change
**Impact:** Low-Medium
**Likelihood:** Low (change is mostly transparent)
**Mitigation:**
- Gradual rollout with A/B testing (10% → 50% → 100%)
- Collect feedback actively during rollout
- Quick rollback capability via feature flag
- Communication about change if needed

### Risk: Development Time Overrun
**Impact:** Medium
**Likelihood:** Medium (new territory, potential unknowns)
**Mitigation:**
- Phased approach with clear milestones
- Build MVP first (Mapbox only, basic UI)
- Defer nice-to-have features to later phases
- Set hard deadline: if >15 days, reassess ROI
- Time-box each phase strictly

### Risk: Breaking Changes in External APIs
**Impact:** High
**Likelihood:** Low (Mapbox/Google are stable, well-maintained)
**Mitigation:**
- Use multiple providers in fallback chain
- Abstract API integration behind adapter layer
- Monitor provider status and announcements
- Keep Google Places as ultimate fallback
- Version pin SDKs and monitor changelogs

## Cost Analysis

### Current State (Google Places)
- Private event autocomplete: ~300 sessions/month
- Cost per session: $0.017
- **Monthly Cost: ~$5.10**
- **Annual Cost: ~$61.20**

### After Migration (Mapbox)
- Mapbox free tier: 100,000 requests/month
- Expected usage: ~300-1000 requests/month
- **Monthly Cost: $0.00**
- Occasional Google fallback (for enrichment): ~$0.50/month
- **Total Monthly Cost: ~$0.50**
- **Annual Cost: ~$6.00**
- **Savings: ~$55/year (~90% reduction)**

### Development Investment
- 10-15 days × $500/day = **$5,000-$7,500 one-time**

### ROI Analysis
- **Pure cost basis:** 55-125 years (not economically viable)
- **With strategic value** (vendor independence, privacy, scalability): **1-2 years ✅**

**Strategic Value (Non-Financial):**
- Vendor independence: ~$500-1,000/year
- Privacy/brand value: ~$200-500/year
- Team learning: ~$500-1,000 value
- Open source alignment: ~$100-200/year
- **Total Strategic Value: ~$1,300-$2,700/year**

## Success Metrics

### Technical Metrics
- **Response Time:** p50 <200ms, p95 <500ms, p99 <1s
- **Error Rate:** <5% autocomplete errors
- **Venue Creation Success:** >90% success rate
- **Cache Hit Rate:** >30%
- **Uptime:** >99.9%

### Business Metrics
- **Cost:** Monthly API costs <$1 (target: $0.50)
- **Cost Reduction:** >80% vs. Google Places
- **User Satisfaction:** Maintain current baseline
- **Support Tickets:** <10% increase

### User Experience Metrics
- **Venue Selection Time:** No increase (maintain <30 seconds)
- **User-Reported Issues:** <5% increase
- **Autocomplete Accuracy:** >85% relevant results

## Future Enhancements

### 1. Provider Enrichment Service
Create background job to enrich Mapbox venues with Google data:

```elixir
defmodule EventasaurusApp.Workers.VenueEnrichmentWorker do
  use Oban.Worker

  def perform(%{args: %{"venue_id" => venue_id}}) do
    venue = Venues.get_venue!(venue_id)

    # If Mapbox venue, optionally fetch Google data
    if venue.geocoding_provider == "mapbox" do
      google_data = GooglePlacesClient.fetch_details(venue.name, venue.coordinates)

      # Merge into metadata
      updated_metadata = deep_merge(venue.metadata, %{
        "google" => google_data
      })

      Venues.update_venue(venue, %{metadata: updated_metadata})
    end

    :ok
  end
end
```

### 2. Additional Provider Support
The abstraction layer makes adding providers straightforward:
- **Geoapify** - Good Google alternative with free tier
- **MapTiler** - Strong European coverage
- **Here Maps** - Automotive/routing focus

To add a provider:
1. Implement provider class extending `BaseGeocodingProvider`
2. Add to `ProviderFactory`
3. Update config to include new provider

### 3. Geographic Routing
Route to best provider based on user location:

```javascript
// In provider-factory.js
static createForLocation(lat, lng, config) {
  // Use Mapbox for US/Europe, Google elsewhere
  if (isWellCoveredRegion(lat, lng)) {
    return new MapboxProvider(config);
  } else {
    return new GoogleProvider(config);
  }
}
```

## References

- **Current Analysis:** `GOOGLE_PLACES_ALTERNATIVES_ANALYSIS.md`
- **Related Files:**
  - `assets/js/hooks/places-search.js` (current implementation)
  - `lib/eventasaurus_app/venues/venue.ex` (venue model)
  - `lib/eventasaurus_web/live/event_live/new.ex` (event form)
  - `lib/eventasaurus_discovery/locations/venue_store.ex` (venue creation logic)

- **External Documentation:**
  - [Mapbox Search Box API](https://docs.mapbox.com/api/search/search-box/)
  - [Mapbox Search.js](https://docs.mapbox.com/mapbox-search-js/api/web/autofill/)
  - [Google Places API](https://developers.google.com/maps/documentation/places/web-service/overview)

## Acceptance Criteria

- [ ] Mapbox Search.js integrated as default provider
- [ ] Google Places continues to work as fallback option
- [ ] Database stores provider information and metadata correctly
- [ ] Frontend abstracts provider differences
- [ ] Venue creation works with both providers
- [ ] UI displays venue information appropriately based on provider
- [ ] All tests passing (unit, integration, E2E)
- [ ] Feature flag implemented for gradual rollout
- [ ] Monitoring and alerting in place
- [ ] Documentation updated
- [ ] Successfully rolled out to 100% of users
- [ ] Cost reduced by >80%

## Timeline

**Total Estimated Time:** 10-15 days development + 1-2 weeks rollout

**Target Completion:** [Set based on priorities]

## Related Issues

- Geocoding cost tracking (#1655)
- Geocoding audit (#1653)
- Original geocoding cost concern (#1652)
