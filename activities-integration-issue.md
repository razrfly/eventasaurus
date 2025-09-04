# Add Real API-Driven Activities to Events Following Polling Patterns

## Background

Issue #816 established excellent patterns for using real API data in polling (TMDB for movies, Google Places for restaurants). However, we haven't implemented the same API integration for Activities. Activities currently exist as a schema but have no seed data.

## Current Status Audit

### ✅ What's Working (Polling)
- **TMDB Integration**: Movie polls use real TMDB API data with posters (`fetch_tmdb_movies()`)
- **Fallback Pattern**: Graceful fallback to curated data when API unavailable
- **Real Data**: Movies include title, year, genre, description, posters, TMDB IDs
- **Voting System**: RCV movie polls working perfectly

### ❌ What's Missing

1. **Google Places in Polling**: Restaurant polls use hardcoded fake data instead of Google Places API
2. **Activities Seeding**: No activities are being seeded for events (activities schema exists but is empty)
3. **API Integration**: Activities don't use TMDB or Google Places APIs

## Requirements

### 1. Upgrade Restaurant Polling to Use Google Places
Follow the TMDB pattern established for movies:
- Create `fetch_google_places_restaurants()` function similar to `fetch_tmdb_movies()`
- Replace hardcoded restaurant data (lines 790-797 in `poll_seed.exs`) with real Google Places data
- Include place photos, ratings, price levels, and proper metadata
- Maintain fallback to curated restaurant data

### 2. Implement Activity Seeding Following Polling Patterns

**Movie Activities:**
- Use TMDB API (same as movie polling)
- Activity type: `"movie_watched"`
- One movie per event (not multiple like polling)
- Include full TMDB metadata: poster, cast, crew, ratings, etc.

**Restaurant Activities:**  
- Use Google Places API (same pattern as restaurant polling upgrade)
- Activity type: `"restaurant_visited"`
- One restaurant per event
- Include place photos, ratings, reviews, location data

## Implementation Pattern

### Established Pattern from Movie Polling (to replicate):

```elixir
# 1. API fetch with error handling
defp fetch_tmdb_movies do
  case TmdbService.search_movies("popular") do
    {:ok, movies} when length(movies) > 0 -> movies
    _ -> []
  end
end

# 2. Real data integration with fallback
movies = case fetch_tmdb_movies() do
  [] ->
    Logger.info("No TMDB movies available, using curated data")
    DevSeeds.CuratedData.movies() |> Enum.take_random(7)
  tmdb_movies ->
    Logger.info("Using real TMDB movies for poll options")
    Enum.take_random(tmdb_movies, 7)
end

# 3. Rich metadata preservation
%{
  title: movie.title,
  description: movie.overview,
  metadata: %{
    "tmdb_id" => movie.id,
    "year" => movie.year,
    "poster_path" => movie.poster_path,
    # ... etc
  }
}
```

## Files to Create/Modify

### New Activity Seeding Module
- `priv/repo/dev_seeds/activity_seed.exs` (new file)
- Follow same structure as `poll_seed.exs`
- Import into `runner.exs`

### Upgrade Restaurant Polling  
- Modify `poll_seed.exs` lines 790-797
- Add Google Places API integration
- Keep same voting system, just upgrade data source

### Integration Points
- Add to `runner.exs` seeding sequence
- Ensure activity seeding runs after events are created
- Create realistic distribution: movie activities for movie events, restaurant activities for dinner events

## Expected Outcomes

1. **Restaurant polls use real Google Places data** instead of hardcoded fake restaurants
2. **Movie activities and restaurant activities** automatically created for relevant events  
3. **Rich metadata** preserved in activities (same as polling)
4. **Consistent API patterns** across polling and activities
5. **Zero fake data** - everything uses real APIs with curated fallbacks

## Success Criteria

- [ ] Google Places integrated in restaurant polling (replacing hardcoded data)
- [ ] Activities seeding module created following polling patterns  
- [ ] Movie activities use TMDB API (same service as movie polling)
- [ ] Restaurant activities use Google Places API
- [ ] Graceful fallbacks to curated data when APIs unavailable
- [ ] Rich metadata preserved in activity records
- [ ] Activities distributed appropriately by event type

## Notes

This follows the established patterns from #816 and ensures we have comprehensive real API data across both polling and activities. The polling system proves the pattern works - we just need to replicate it for activities and upgrade restaurant polling to complete the vision.