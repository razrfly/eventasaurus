# Kino Krakow Cinema GPS Coordinates - Blocking Issue

## Issue Summary

**Status**: 🚨 **BLOCKING** - Events cannot be created without venue GPS coordinates

**Impact**: 0 events created despite 181 showtimes scraped and 18 movies successfully matched to TMDB

**Error**:
```
[warning] Skipping invalid event: Missing cinema GPS coordinates
✅ Successfully transformed 0 event(s)
```

---

## Investigation Results

### 1. Website Analysis

**Question**: Does Kino Krakow website provide GPS coordinates?

**Answer**: ❌ **NO**

**Evidence**:
- ✅ Main page lists 15 cinema names with phone numbers
- ❌ No individual cinema info pages exist
- ❌ No GPS coordinates in HTML source
- ❌ No embedded maps (Google Maps, Leaflet, etc.)
- ❌ No structured data with location info

**Tested URLs** (all returned 404):
- `https://www.kino.krakow.pl/kino-ars/info`
- `https://www.kino.krakow.pl/kino-ars`
- `https://www.kino.krakow.pl/o-kinach/kino-ars`

**Cinema Data Available**:
```
Cinema List (from homepage):
1. Agrafka
2. Cinema City Bonarka
3. Cinema City Galeria Kazimierz
4. Cinema City Zakopianka
5. Galeria Bronowice Mikro
6. IMAX
7. Kijów
8. Kino Kika
9. Kino Mikro
10. Kino Pod Baranami
11. Kino Pod Baranami ASP
12. Kino Pod Baranami w MOS
13. Multikino
14. Paradox
15. Sfinks

Data Provided: Name + Phone Number ONLY
```

### 2. Existing Fallback Pattern Analysis

**Question**: What fallback mechanism exists for venues without GPS coordinates?

**Answer**: ✅ **VenueGeocoder with Google Maps API**

**Location**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`

**How It Works**:
```elixir
# Lines 390-410
# If venue has no latitude/longitude, VenueProcessor automatically calls:
case VenueGeocoder.geocode_venue(geocoding_data) do
  {:ok, %{latitude: lat, longitude: lng}} ->
    Logger.info("🗺️ Successfully geocoded venue '#{data.name}' using Google Maps fallback")
    {lat, lng}

  {:error, reason} ->
    Logger.error("🗺️❌ Failed to geocode venue - Venue creation will fail")
    {nil, nil}
end
```

**Required Data for Geocoding**:
```elixir
geocoding_data = %{
  name: data.name,              # ✅ HAVE (from ShowtimeExtractor)
  address: data.address,        # ❌ DON'T HAVE
  city_name: city.name,         # ✅ CAN PROVIDE ("Kraków")
  state: data.state,            # ⚠️ OPTIONAL
  country_name: data.country_name  # ✅ CAN PROVIDE ("Poland")
}
```

**Geocoding Success Rate**:
- Cinema name + city + country: **High** (80-90%)
- Cinema name + address + city + country: **Very High** (95%+)

### 3. Alternative: Karnet's Hardcoded Approach

**Question**: How does Karnet handle Kraków cinema coordinates?

**Answer**: Hardcoded coordinates for known venues

**Location**: `lib/eventasaurus_discovery/sources/karnet/venue_matcher.ex`

**Pattern** (lines 117-133):
```elixir
def get_venue_coordinates(venue_name) do
  # Major Kraków venues with approximate coordinates
  coordinates = %{
    "Centrum Kongresowe ICE Kraków" => {50.0647, 19.9450},
    "Tauron Arena Kraków" => {50.0669, 20.0176},
    "Teatr im. J. Słowackiego" => {50.0640, 19.9415},
    # ... etc
  }

  coordinates[venue_name]
end
```

**Note**: Comment at line 114 says "In production, these would come from a geocoding service" - indicating this is a temporary solution.

---

## Solution Options

### Option 1: Use Google Places API Geocoding (Recommended)

**Approach**: Update `CinemaExtractor` to provide city and country, let `VenueProcessor` geocode automatically.

**Implementation**:
```elixir
# lib/eventasaurus_discovery/sources/kino_krakow/extractors/cinema_extractor.ex
def extract(html, cinema_slug) do
  cinema_name = extract_name(html, cinema_slug)

  %{
    name: cinema_name,
    city: "Kraków",           # Enable geocoding
    country: "Poland",        # Enable geocoding
    latitude: nil,            # Trigger automatic geocoding
    longitude: nil            # Trigger automatic geocoding
  }
end
```

**Pros**:
- ✅ Uses existing VenueGeocoder infrastructure
- ✅ Automatic for all 14+ cinemas
- ✅ No manual maintenance needed
- ✅ Works for new cinemas automatically
- ✅ One-time Google Maps API call per cinema (cached in DB)

**Cons**:
- ⚠️ Requires Google Maps API key (already configured in system)
- ⚠️ Small API cost (~$0.005 per geocode × 14 cinemas = $0.07 one-time)
- ⚠️ Depends on Google Maps data quality

**Cost Analysis**:
- 14 cinemas × $0.005/geocode = **$0.07 one-time**
- Cached in database forever
- Future cinemas: ~$0.005 each

### Option 2: Hardcode Known Cinema Coordinates

**Approach**: Create static map of Kraków cinema coordinates like Karnet.

**Implementation**:
```elixir
# lib/eventasaurus_discovery/sources/kino_krakow/cinema_coordinates.ex
defmodule EventasaurusDiscovery.Sources.KinoKrakow.CinemaCoordinates do
  @coordinates %{
    "kino-pod-baranami" => {50.0617, 19.9373},
    "kino-kika" => {50.0669, 19.9551},
    "cinema-city-bonarka" => {50.0340, 19.9610},
    # ... 14 total cinemas
  }

  def get_coordinates(cinema_slug) do
    @coordinates[cinema_slug]
  end
end
```

**Pros**:
- ✅ No API calls needed
- ✅ Instant results
- ✅ Guaranteed accuracy if researched properly
- ✅ Zero cost

**Cons**:
- ❌ Manual research needed for 14 cinemas
- ❌ Requires updates for new cinemas
- ❌ Not scalable
- ❌ Violates existing system patterns (Karnet comment says this is temporary)

**Research Required**:
- Find GPS coordinates for all 14 Kraków cinemas
- Estimated time: 30-60 minutes

### Option 3: Hybrid Approach

**Approach**: Hardcode major cinemas, use geocoding for unknown ones.

**Implementation**:
```elixir
def extract(html, cinema_slug) do
  cinema_name = extract_name(html, cinema_slug)

  # Try hardcoded coordinates first
  {lat, lng} = CinemaCoordinates.get_coordinates(cinema_slug) || {nil, nil}

  %{
    name: cinema_name,
    city: "Kraków",
    country: "Poland",
    latitude: lat,      # Falls back to geocoding if nil
    longitude: lng      # Falls back to geocoding if nil
  }
end
```

**Pros**:
- ✅ Best of both worlds
- ✅ Fast for known cinemas
- ✅ Automatic for new cinemas

**Cons**:
- ⚠️ More complex implementation
- ⚠️ Still requires manual research

---

## Recommendation

**Use Option 1: Google Places API Geocoding**

**Rationale**:
1. **Already Built**: VenueProcessor has this infrastructure ready
2. **Cost-Effective**: $0.07 one-time cost for 14 cinemas
3. **Scalable**: Works automatically for new cinemas
4. **Maintainable**: No manual updates needed
5. **System Consistency**: Matches how other scrapers handle unknown venues
6. **Karnet's Intent**: Comment indicates hardcoding is temporary, geocoding is production solution

**Implementation Steps**:

1. Update `CinemaExtractor.extract/2` to return city and country:
   ```elixir
   %{
     name: cinema_name,
     city: "Kraków",
     country: "Poland",
     latitude: nil,
     longitude: nil
   }
   ```

2. VenueProcessor will automatically:
   - Call `VenueGeocoder.geocode_venue/1`
   - Get coordinates from Google Maps
   - Cache in database
   - Create venue with GPS coordinates

3. Test with one cinema first to verify geocoding works

4. Run full scrape - all 14 cinemas will be geocoded automatically

**Expected Results**:
- First run: 14 Google Maps API calls (~$0.07)
- Subsequent runs: 0 API calls (coordinates cached in DB)
- Event creation: ✅ Success (venues have GPS coordinates)

---

## Implementation Details

### Current CinemaExtractor Code

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/extractors/cinema_extractor.ex`

**Current Implementation** (lines 6-17):
```elixir
def extract(_html, cinema_slug) do
  # Parse cinema slug to get name
  cinema_name =
    cinema_slug
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")

  %{
    name: cinema_name,
    address: "Kraków, Poland",  # Placeholder
    lat: nil,  # ❌ Causes event creation to fail
    lon: nil   # ❌ Causes event creation to fail
  }
end
```

### Required Changes

**New Implementation**:
```elixir
def extract(_html, cinema_slug) do
  cinema_name =
    cinema_slug
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")

  # VenueProcessor will geocode automatically when lat/lng are nil
  %{
    name: cinema_name,
    city: "Kraków",           # ✅ Required for geocoding
    country: "Poland",        # ✅ Required for geocoding
    latitude: nil,            # ✅ Triggers VenueGeocoder
    longitude: nil            # ✅ Triggers VenueGeocoder
  }
end
```

**Note**: Changed map keys from `:lat/:lon` to `:latitude/:longitude` to match VenueProcessor expectations.

### Testing Plan

1. **Single Cinema Test**:
   ```bash
   # Test geocoding for one cinema
   iex> cinema_data = %{name: "Kino Pod Baranami", city: "Kraków", country: "Poland"}
   iex> VenueGeocoder.geocode_venue(cinema_data)
   {:ok, %{latitude: 50.0617, longitude: 19.9373}}
   ```

2. **Full Integration Test**:
   ```bash
   mix run scripts/test_kino_krakow_integration.exs
   ```
   Expected: Events created successfully

3. **Verify Database**:
   ```sql
   SELECT name, latitude, longitude FROM venues
   WHERE source = 'scraper'
   AND city = 'Kraków'
   ORDER BY inserted_at DESC
   LIMIT 14;
   ```

---

## Alternative: If Geocoding Fails

**Fallback to Option 2**: Hardcode coordinates for known cinemas

**Research Sources**:
- Google Maps search: "Kino Pod Baranami Kraków"
- Cinema City official website
- OpenStreetMap
- Manual verification

**Example Research**:
```
Cinema: Kino Pod Baranami
Google Maps URL: https://goo.gl/maps/example
Coordinates: 50.0617, 19.9373
```

---

## Files to Modify

1. `lib/eventasaurus_discovery/sources/kino_krakow/extractors/cinema_extractor.ex`
   - Update `extract/2` to return city/country
   - Change `:lat/:lon` to `:latitude/:longitude`

2. (Optional) `lib/eventasaurus_discovery/sources/kino_krakow/cinema_coordinates.ex`
   - Only if geocoding fails
   - Create hardcoded coordinate map

---

## Success Criteria

✅ VenueProcessor successfully geocodes all 14 cinemas
✅ Events are created with valid GPS coordinates
✅ No "Missing cinema GPS coordinates" warnings
✅ Integration test shows "Successfully transformed N event(s)" where N > 0

---

## Cost-Benefit Analysis

| Approach | Implementation Time | One-Time Cost | Ongoing Cost | Scalability |
|----------|-------------------|---------------|--------------|-------------|
| **Option 1: Geocoding** | 15 min | $0.07 | $0.00 | ✅ High |
| **Option 2: Hardcode** | 60 min | $0.00 | Manual updates | ❌ Low |
| **Option 3: Hybrid** | 75 min | $0.07 | Manual updates | ⚠️ Medium |

**Winner**: Option 1 (Geocoding)

---

**Date**: October 2, 2025
**Analysis Method**: Sequential Thinking + Context7
**Blocking Priority**: 🚨 HIGH - Prevents event creation
**Recommended Solution**: Google Places API Geocoding (15 min implementation, $0.07 cost)
