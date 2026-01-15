# Source Metadata Reference

Complete documentation of metadata fields stored by each Eventasaurus scraper. This reference helps developers understand what data is available for debugging, future schema evolution, and feature development.

## Metadata Storage Patterns

Each source uses one of these patterns for storing scraped data:

| Pattern | Description | Pros | Cons |
|---------|-------------|------|------|
| **STRUCTURED** | Explicitly defined fields, transformed data | Clear schema, validated | May lose unexpected upstream fields |
| **RAW DUMP** | Full upstream response stored as-is | Complete data preservation | Large storage, no validation |
| **HYBRID** | Mix of structured + raw preservation | Best of both worlds | More complex |

---

## Source Metadata Details

### 1. Ticketmaster

**Pattern**: STRUCTURED
**Image Handling**: Multi-image (up to 5 prioritized images)
**Image Cache**: ✅ Full integration via `cache_event_images`

**Metadata Fields**:
```elixir
%{
  ticketmaster_id: String.t(),           # Original TM event ID
  segment: String.t(),                   # e.g., "Music", "Sports"
  genre: String.t(),                     # e.g., "Rock", "Pop"
  subgenre: String.t(),                  # More specific genre
  promoter: String.t(),                  # Event promoter name
  price_ranges: list(),                  # [{min, max, currency}, ...]
  sales_dates: map(),                    # Public/presale dates
  seatmap_url: String.t(),               # Interactive seat selection
  accessibility: map(),                  # Accessibility info
  parking: map(),                        # Parking details
  age_restrictions: String.t(),          # e.g., "18+", "All Ages"
  attractions: list()                    # Performers/attractions
}
```

**Multi-Image Extraction**:
- Uses `TmTransformer.extract_prioritized_images/2`
- Prioritizes by ratio: 16:9 > 4:3 > 3:2 > 1:1
- Image types: hero, poster, gallery

---

### 2. Bandsintown

**Pattern**: RAW DUMP
**Image Handling**: Single image
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  raw_data: map()   # Complete upstream response stored as-is
}
```

**Raw Data Contains**:
- Artist info, lineup details
- Ticket links, RSVP counts
- Venue details, offers
- All original Bandsintown fields

**Note**: Good for debugging but should consider extracting key fields.

---

### 3. Resident Advisor

**Pattern**: HYBRID
**Image Handling**: Multi-image (up to 5 images)
**Image Cache**: ✅ Full integration via `cache_event_images`

**Metadata Fields**:
```elixir
%{
  ra_id: String.t(),                     # RA event ID
  content_url: String.t(),               # Original RA URL
  event_type: String.t(),                # "club", "festival", etc.
  promoter: map(),                       # Promoter details
  attending_count: integer(),            # RSVP count
  lineup: list(),                        # Artist lineup
  sound_system: String.t(),              # Audio equipment
  # Plus selective raw data preservation
}
```

**Multi-Image Extraction**:
- Uses `RaTransformer.extract_all_images/2`
- Extracts from event images, flyer, venue images
- Image types: hero, poster, gallery

---

### 4. Cinema City

**Pattern**: STRUCTURED
**Image Handling**: Single image (from TMDB)
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  cinema_city_id: String.t(),            # CC showtime ID
  movie_id: String.t(),                  # CC movie ID
  format: String.t(),                    # "2D", "3D", "IMAX"
  language: String.t(),                  # Audio language
  subtitles: String.t(),                 # Subtitle language
  screen: String.t(),                    # Screen/hall name
  duration_minutes: integer(),           # Runtime
  rating: String.t(),                    # Age rating
  genres: list(String.t())               # Movie genres
}
```

**Image Source**: TMDB poster/backdrop (enriched from movie matching)

---

### 5. Sortiraparis

**Pattern**: HYBRID
**Image Handling**: Single image
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  sortiraparis_id: String.t(),           # Original SP ID
  category_path: list(String.t()),       # Category hierarchy
  practical_info: String.t(),            # Hours, access, etc.
  prices_text: String.t(),               # Pricing description
  dates_text: String.t(),                # Date range text
  # Plus some raw fields
}
```

---

### 6. Karnet

**Pattern**: RAW DUMP
**Image Handling**: Single image
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  raw_data: map()   # Complete upstream response
}
```

**Raw Data Contains**:
- Event details, ticket info
- Venue data, categories
- All original Karnet fields

---

### 7. Week.pl

**Pattern**: STRUCTURED
**Image Handling**: Single image (⚠️ WASTED POTENTIAL)
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  week_pl_id: String.t(),                # Original Week.pl ID
  category: String.t(),                  # Event category
  subcategory: String.t(),               # Subcategory
  ticket_url: String.t(),                # Purchase link
  organizer: String.t(),                 # Event organizer
  tags: list(String.t())                 # Event tags
}
```

**⚠️ MULTI-IMAGE OPPORTUNITY**:
The Week.pl API provides an `imageFiles` array with multiple images, but currently only the first image is extracted. This is a prime candidate for multi-image enhancement.

---

### 8. Geeks Who Drink

**Pattern**: STRUCTURED
**Image Handling**: Single image (venue logo only)
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  time_text: String.t(),                 # Original schedule text
  fee_text: String.t(),                  # Entry fee description
  venue_id: String.t(),                  # GWD venue ID
  recurring: true,                       # Always recurring
  frequency: "weekly",                   # Always weekly
  brand: "geeks_who_drink",              # Brand identifier
  start_time: String.t(),                # e.g., "19:00"
  facebook: String.t() | nil,            # FB page URL
  instagram: String.t() | nil,           # IG handle
  quizmaster: String.t() | nil           # Host name
}
```

**Image Source**: Venue logo only (`logo_url`)

---

### 9. Question One

**Pattern**: STRUCTURED
**Image Handling**: Single image (hero image)
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  time_text: String.t(),                 # Original schedule text
  fee_text: String.t(),                  # Entry fee description
  day_of_week: String.t(),               # e.g., "wednesday"
  recurring: true,                       # Always recurring
  frequency: "weekly"                    # Always weekly
}
```

**Image Source**: Venue hero image (`hero_image_url`)

---

### 10. Inquizition

**Pattern**: STRUCTURED
**Image Handling**: ❌ None (source provides no images)
**Image Cache**: N/A

**Metadata Fields**:
```elixir
%{
  schedule_text: String.t(),             # Original schedule text
  venue_id: String.t(),                  # Inquizition venue ID
  recurring: true,                       # Always recurring
  frequency: "weekly",                   # Always weekly
  day_of_week: String.t(),               # e.g., "tuesday"
  start_time: String.t(),                # e.g., "19:30"
  timezone: "Europe/London",             # UK timezone
  schedule_inferred: boolean(),          # If schedule was parsed
  website: String.t() | nil,             # Venue website
  email: String.t() | nil                # Contact email
}
```

---

### 11. Kupbilecik

**Pattern**: RAW-ish (source_data)
**Image Handling**: Single image
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  source_data: map()   # Raw event data with key: raw_event
}
```

**Source Data Contains**:
- Event details from Kupbilecik API
- Venue info, pricing, dates
- Category/tag information

---

### 12. Repertuary

**Pattern**: STRUCTURED
**Image Handling**: Single image (TMDB poster/backdrop)
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  source: "repertuary",                  # Source identifier
  city: String.t(),                      # e.g., "krakow"
  cinema_slug: String.t(),               # Cinema identifier
  movie_slug: String.t(),                # Movie identifier
  confidence_score: float(),             # Match confidence (0-1)
  movie_url: String.t()                  # Original movie page URL
}
```

**Image Source**: TMDB (via movie matching) - poster_url or backdrop_url

---

### 13. Speed Quizzing

**Pattern**: STRUCTURED
**Image Handling**: ❌ None (source provides no images)
**Image Cache**: N/A

**Metadata Fields**:
```elixir
%{
  time_text: String.t(),                 # Original schedule text
  event_id: String.t(),                  # Speed Quizzing event ID
  recurring: true,                       # Always recurring
  frequency: "weekly",                   # Always weekly
  start_time: String.t(),                # e.g., "20:00"
  day_of_week: String.t(),               # e.g., "thursday"
  performer: String.t() | nil,           # Host name
  source_id: String.t()                  # Original source ID
}
```

---

### 14. Waw4Free

**Pattern**: RAW DUMP
**Image Handling**: Single image
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  raw_data: map()   # Complete upstream response
}
```

**Raw Data Contains**:
- Full event details from Waw4Free
- Venue info, dates, descriptions
- All original fields preserved

---

### 15. PubQuiz

**Pattern**: STRUCTURED (via source_metadata)
**Image Handling**: ❌ None (trivia source, no images)
**Image Cache**: N/A

**Metadata Fields**:
```elixir
%{
  source_metadata: %{
    venue_name: String.t(),              # Venue name
    host: String.t() | nil,              # Quiz host
    phone: String.t() | nil,             # Contact phone
    description: String.t() | nil,       # Event description
    schedule_text: String.t()            # Original schedule
  }
}
```

---

### 16. Quizmeisters

**Pattern**: STRUCTURED
**Image Handling**: Single image (validated hero)
**Image Cache**: ✅ Via `cache_single_image`

**Metadata Fields**:
```elixir
%{
  time_text: String.t(),                 # Original schedule text
  venue_id: String.t(),                  # Quizmeisters venue ID
  recurring: true,                       # Always recurring
  frequency: "weekly",                   # Always weekly
  start_time: String.t(),                # e.g., "19:30"
  quizmaster: String.t() | nil           # Host name
}
```

**Image Handling**: Uses `validate_image_url/1` to filter placeholder images

---

## Summary Tables

### Metadata Pattern Distribution

| Pattern | Sources | Count |
|---------|---------|-------|
| STRUCTURED | Ticketmaster, Cinema City, Week.pl, Geeks Who Drink, Question One, Inquizition, Repertuary, Speed Quizzing, PubQuiz, Quizmeisters | 10 |
| RAW DUMP | Bandsintown, Karnet, Waw4Free | 3 |
| HYBRID | Resident Advisor, Sortiraparis | 2 |
| RAW-ish | Kupbilecik | 1 |

### Image Handling Summary

| Status | Sources | Count |
|--------|---------|-------|
| Multi-Image | Ticketmaster, Resident Advisor | 2 |
| Single Image | Cinema City, Sortiraparis, Karnet, Week.pl, Geeks Who Drink, Question One, Kupbilecik, Repertuary, Waw4Free, Quizmeisters, Bandsintown | 11 |
| No Images Available | Inquizition, Speed Quizzing, PubQuiz | 3 |

### Multi-Image Opportunities

| Source | Opportunity | Effort |
|--------|-------------|--------|
| **Week.pl** | API provides `imageFiles` array | Low - data available |
| Bandsintown | May have artist images | Medium - needs investigation |
| Sortiraparis | May have gallery images | Medium - needs investigation |

---

## Usage Examples

### Accessing Metadata in Code

```elixir
# Get metadata from event source
event_source = Repo.get(PublicEventSource, id)
metadata = event_source.metadata

# Access specific fields
case metadata do
  %{"ticketmaster_id" => tm_id} ->
    # Ticketmaster event
    IO.puts("TM Event: #{tm_id}")

  %{"raw_data" => raw} ->
    # Raw dump source (Bandsintown, Karnet, Waw4Free)
    IO.inspect(raw, label: "Full upstream data")

  %{"recurring" => true, "frequency" => freq} ->
    # Trivia/recurring event
    IO.puts("Recurring #{freq} event")
end
```

### Debugging with Raw Data

For RAW DUMP sources, you can access any upstream field:

```elixir
# Bandsintown example
raw = event_source.metadata["raw_data"]
artist_name = raw["artist"]["name"]
lineup = raw["lineup"]
offers = raw["offers"]
```

---

## Recommendations

1. **Standardize on HYBRID Pattern**: Best of both worlds - structured for common queries, raw for debugging
2. **Enable Multi-Image for Week.pl**: Low-hanging fruit, data already available
3. **Extract Key Fields from RAW DUMP Sources**: Aid querying while preserving full data
4. **Document Upstream Schema Changes**: Track when sources change their API responses

---

*Last updated: 2025-01-15*
*Generated by scraper metadata audit*
