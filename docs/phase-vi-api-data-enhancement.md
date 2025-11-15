# Phase VI Enhancement: API Data Integration for Poll Options

## Executive Summary

**Current State**: Phase V polling seed file (`mobile_testing_polls.exs`) uses hardcoded fallback data for all poll types (movies, cocktails, music). No real API data is being fetched, and NO images are included.

**User Belief**: User believed movie polls might use real TMDB data with actual images - this is **INCORRECT**. All poll types currently use simple hardcoded strings.

**Opportunity**: The system has a fully implemented RichDataManager with providers for TMDB, CocktailDB, Spotify, and MusicBrainz that can fetch real data with images.

**Proposed Enhancement**: Modify the Phase V seed file to use RichDataManager to fetch real API data with images for better testing experience.

---

## Current Implementation Analysis

### What We Found

#### Movies (Lines 496-644 in mobile_testing_polls.exs)
```elixir
options = [
  %{title: "The Shawshank Redemption", description: "Drama about hope and friendship"},
  %{title: "The Godfather", description: "Crime saga of a powerful family"},
  %{title: "The Dark Knight", description: "Batman faces the Joker"},
  %{title: "Pulp Fiction", description: "Tarantino's crime anthology"}
]

Enum.each(options, fn opt ->
  Events.create_poll_option(%{
    poll_id: poll.id,
    title: opt.title,
    description: opt.description,
    suggested_by_id: organizer_id
    # NO image_url field!
  })
end)
```

**Issues**:
- Hardcoded movie titles only
- Basic descriptions, no rich metadata
- **NO images** - no poster URLs
- No TMDB API calls

#### Cocktails (Lines 671-815 in mobile_testing_polls.exs)
```elixir
options = [
  %{title: "Margarita", description: "Tequila, lime, triple sec"},
  %{title: "Mojito", description: "Rum, mint, lime, soda"},
  %{title: "Old Fashioned", description: "Whiskey, bitters, sugar"}
]

Enum.each(options, fn opt ->
  Events.create_poll_option(%{
    poll_id: poll.id,
    title: opt.title,
    description: opt.description,
    suggested_by_id: organizer_id
    # NO image_url field!
  })
end)
```

**Issues**:
- Hardcoded cocktail names and basic ingredient lists
- **NO images** - no cocktail photos
- No CocktailDB API calls
- Missing rich metadata (category, glass type, instructions, etc.)

#### Music Tracks (Lines 842-990 in mobile_testing_polls.exs)
```elixir
options = [
  %{title: "Billie Jean", description: "Michael Jackson"},
  %{title: "Bohemian Rhapsody", description: "Queen"},
  %{title: "Superstition", description: "Stevie Wonder"},
  %{title: "Don't Stop Believin'", description: "Journey"}
]

Enum.each(options, fn opt ->
  Events.create_poll_option(%{
    poll_id: poll.id,
    title: opt.title,
    description: opt.description,
    suggested_by_id: organizer_id
    # NO image_url field!
  })
end)
```

**Issues**:
- Hardcoded track titles and artist names only
- **NO images** - no album artwork
- No Spotify or MusicBrainz API calls
- Missing rich metadata (album, release date, duration, etc.)

---

## Available API Infrastructure

### RichDataManager System

The system has a fully implemented RichDataManager at:
`lib/eventasaurus_web/services/rich_data_manager.ex`

**Registered Providers** (from server logs):
```
[debug] Registered provider: The Movie Database (tmdb) - supports [:movie, :tv]
[debug] Registered provider: Google Places (google_places) - supports [:venue, :restaurant, :activity]
[debug] Registered provider: MusicBrainz (musicbrainz) - supports [:track]
[debug] Registered provider: Spotify (spotify) - supports [:track]
[debug] Registered provider: The CocktailDB (cocktaildb) - supports [:cocktail]
[info] RichDataManager started with 5 default providers
```

### API Capabilities by Provider

#### 1. TMDB Provider (`tmdb_rich_data_provider.ex`)

**Search Function**:
```elixir
RichDataManager.search("The Matrix", %{content_type: :movie})
```

**Returns**:
```elixir
{:ok, [
  %{
    id: 603,
    type: :movie,
    title: "The Matrix",
    description: "Thomas Anderson, a computer programmer...",
    image_url: "https://image.tmdb.org/t/p/w500/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg",
    images: [
      %{url: "...", type: :poster, size: :w500},
      %{url: "...", type: :backdrop, size: :original}
    ],
    metadata: %{
      release_date: "1999-03-30",
      tmdb_id: 603,
      media_type: "movie",
      vote_average: 8.7,
      popularity: 89.3,
      genres: ["Action", "Science Fiction"]
    }
  }
]}
```

**Key Features**:
- ✅ Real movie posters from TMDB
- ✅ Comprehensive metadata (genres, ratings, release dates)
- ✅ Multiple image sizes available
- ✅ Caching support via `get_cached_details/3`

#### 2. CocktailDB Provider (`cocktail_db_rich_data_provider.ex`)

**Search Function**:
```elixir
RichDataManager.search("Margarita", %{providers: [:cocktaildb]})
```

**Returns**:
```elixir
{:ok, [
  %{
    id: "11007",
    type: :cocktail,
    title: "Margarita",
    description: "Ordinary Drink • Alcoholic • Served in Cocktail glass",
    image_url: "https://www.thecocktaildb.com/images/media/drink/5noda61589575158.jpg",
    images: [
      %{url: "...", type: :thumbnail, size: :medium}
    ],
    metadata: %{
      category: "Ordinary Drink",
      alcoholic: "Alcoholic",
      glass: "Cocktail glass",
      ingredients: [
        %{name: "Tequila", measure: "1 1/2 oz"},
        %{name: "Triple sec", measure: "1/2 oz"},
        %{name: "Lime juice", measure: "1 oz"}
      ]
    }
  }
]}
```

**Key Features**:
- ✅ Real cocktail photos from CocktailDB
- ✅ Detailed ingredient lists with measurements
- ✅ Glass type, category, instructions
- ✅ Caching support via `get_cached_details/3`

#### 3. Spotify/MusicBrainz Providers

**Search Function**:
```elixir
RichDataManager.search("Billie Jean", %{providers: [:spotify]})
```

**Expected Returns** (based on provider pattern):
```elixir
{:ok, [
  %{
    id: "5ChkMS8OtdzJeqyybCc9R5",
    type: :track,
    title: "Billie Jean",
    description: "Michael Jackson • Thriller (1982)",
    image_url: "https://i.scdn.co/image/ab67616d0000b273de3c04b5...",
    images: [...],
    metadata: %{
      artist: "Michael Jackson",
      album: "Thriller",
      release_date: "1982-11-30",
      duration_ms: 294053
    }
  }
]}
```

**Key Features**:
- ✅ Real album artwork
- ✅ Accurate metadata (artist, album, duration)
- ✅ Spotify/MusicBrainz integration

---

## Phase VI Enhancement Proposal

### Goals

1. **Enhance Testing Experience**: Use real data with images for more realistic testing
2. **Demonstrate API Integration**: Show how RichDataManager works in production
3. **Improve Visual Quality**: Display actual movie posters, cocktail photos, album artwork
4. **Maintain Simplicity**: Keep seed file easy to run and understand

### Implementation Approach

#### Option A: Direct API Integration (Recommended)

Modify the seed file to call RichDataManager for each poll type:

**Example for Movies**:
```elixir
# Before (hardcoded):
options = [
  %{title: "The Shawshank Redemption", description: "Drama about hope and friendship"}
]

# After (API-fetched):
search_queries = ["The Shawshank Redemption", "The Godfather", "The Dark Knight", "Pulp Fiction"]

options =
  Enum.map(search_queries, fn query ->
    case RichDataManager.search(query, %{providers: [:tmdb], content_type: :movie, limit: 1}) do
      {:ok, %{tmdb: {:ok, [result | _]}}} ->
        %{
          title: result.title,
          description: result.description,
          image_url: result.image_url,
          metadata: result.metadata
        }

      _ ->
        # Fallback to hardcoded if API fails
        %{title: query, description: "Classic film"}
    end
  end)

Enum.each(options, fn opt ->
  Events.create_poll_option(%{
    poll_id: poll.id,
    title: opt.title,
    description: opt.description,
    image_url: opt[:image_url],  # NEW: Add image URL
    metadata: opt[:metadata],     # NEW: Add rich metadata
    suggested_by_id: organizer_id
  })
end)
```

**Benefits**:
- ✅ Real images from TMDB
- ✅ Rich metadata (release dates, ratings, genres)
- ✅ Graceful fallback if API unavailable
- ✅ Demonstrates RichDataManager usage
- ✅ More realistic testing data

**Cocktails Enhancement**:
```elixir
search_queries = ["Margarita", "Mojito", "Old Fashioned"]

options =
  Enum.map(search_queries, fn query ->
    case RichDataManager.search(query, %{providers: [:cocktaildb], limit: 1}) do
      {:ok, %{cocktaildb: {:ok, [result | _]}}} ->
        %{
          title: result.title,
          description: result.description,
          image_url: result.image_url,
          metadata: result.metadata
        }

      _ ->
        %{title: query, description: "Classic cocktail"}
    end
  end)
```

**Music Enhancement**:
```elixir
search_queries = [
  "Billie Jean Michael Jackson",
  "Bohemian Rhapsody Queen",
  "Superstition Stevie Wonder"
]

options =
  Enum.map(search_queries, fn query ->
    case RichDataManager.search(query, %{providers: [:spotify], limit: 1}) do
      {:ok, %{spotify: {:ok, [result | _]}}} ->
        %{
          title: result.title,
          description: result.description,
          image_url: result.image_url,
          metadata: result.metadata
        }

      _ ->
        %{title: query, description: "Popular track"}
    end
  end)
```

#### Option B: Cached/Pre-fetched Data

Create a separate module that pre-fetches and caches API data:

```elixir
defmodule Eventasaurus.Seeds.RichPollData do
  @moduledoc """
  Pre-fetched rich data for poll options using RichDataManager.
  Data is cached to avoid API rate limits during seed runs.
  """

  def movie_options do
    [
      # Pre-fetched from TMDB with caching
      %{
        title: "The Shawshank Redemption",
        image_url: "https://image.tmdb.org/t/p/w500/...",
        metadata: %{tmdb_id: 278, release_date: "1994-09-23"}
      }
    ]
  end

  def cocktail_options do
    # Similar structure for cocktails
  end

  def music_options do
    # Similar structure for music
  end
end
```

**Benefits**:
- ✅ Faster seed execution (no API calls during seeding)
- ✅ No API rate limit concerns
- ✅ Deterministic seed data
- ✅ Can be regenerated periodically

**Drawbacks**:
- ❌ Requires maintenance to refresh cached data
- ❌ Doesn't demonstrate live API integration

---

## Database Schema Considerations

### Current PollOption Schema

Check if `poll_options` table supports `image_url` and `metadata` fields:

```sql
-- Need to verify if these columns exist:
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'poll_options';
```

**If missing**, would need migration:
```elixir
alter table(:poll_options) do
  add :image_url, :string
  add :metadata, :map
end
```

---

## Implementation Checklist

### Phase VI - Part 1: Schema Verification
- [ ] Verify `poll_options` table has `image_url` column
- [ ] Verify `poll_options` table has `metadata` column
- [ ] Create migration if needed

### Phase VI - Part 2: Seed File Enhancement
- [ ] Add RichDataManager integration for movie polls
- [ ] Add RichDataManager integration for cocktail polls
- [ ] Add RichDataManager integration for music polls
- [ ] Add error handling and fallbacks
- [ ] Test seed file with API integration

### Phase VI - Part 3: Verification
- [ ] Run seeds with API integration
- [ ] Verify images load in UI
- [ ] Verify metadata displays correctly
- [ ] Test fallback behavior when APIs unavailable
- [ ] Document API requirements in README

---

## Benefits Analysis

### For Testing
- **Visual Verification**: Can see actual movie posters, cocktail photos, album artwork
- **Realistic Data**: More representative of production usage
- **Better UX Testing**: Test image loading, lazy loading, error states

### For Development
- **API Integration Demo**: Shows how RichDataManager works
- **Error Handling**: Forces proper error handling and fallbacks
- **Caching Testing**: Can test caching behavior with real data

### For User Experience
- **Professional Look**: Real images make polls look polished
- **Better Decision Making**: Users can recognize options by images
- **Engagement**: Visual polls are more engaging than text-only

---

## Risks and Mitigations

### Risk 1: API Rate Limits
**Mitigation**: Use `get_cached_details` instead of `get_details` for frequently accessed data

### Risk 2: API Availability
**Mitigation**: Include fallback to hardcoded data if API calls fail

### Risk 3: Seed Performance
**Mitigation**: Implement Option B (pre-fetched cached data) for faster seeding

### Risk 4: Missing API Keys
**Mitigation**: Document required API keys in README, provide setup instructions

---

## Recommendation

**Recommended Approach**: **Option A (Direct API Integration)** for Phase VI

**Rationale**:
1. Demonstrates full RichDataManager capabilities
2. Forces proper error handling implementation
3. Provides most realistic testing environment
4. Can be optimized later with caching if needed

**Next Steps**:
1. Verify database schema supports `image_url` and `metadata`
2. Create migration if needed
3. Update seed file with RichDataManager integration
4. Test thoroughly with API integration
5. Document API key requirements
6. Consider Option B as Phase VII optimization

---

## Conclusion

**User's Initial Belief**: Movies use real TMDB data
**Reality**: All poll types use hardcoded fallback data with NO images

**Phase VI Opportunity**: Leverage the fully implemented RichDataManager system to fetch real API data with images for a significantly enhanced testing and user experience.

**Impact**: This enhancement would transform the polling feature from basic text-only options to visually rich, engaging polls with professional-quality images and metadata.

**Effort**: Low to medium - the infrastructure exists, just needs integration in seed file and potential schema updates.

**Value**: High - significantly improves testing quality, demonstrates API capabilities, and provides better user experience.
