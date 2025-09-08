# Music Search Implementation - Phase 2: Song Titles Only

## Background
Previous work on music search integration is in branch `09-07-music-brain1`. This branch contains valuable implementation patterns but also revealed areas for improvement.

## What Worked Well (Keep)
- ✅ **RichDataManager Integration Pattern**: The provider architecture works well for plugging in different search services
- ✅ **UI Template Consistency**: Music search results following the same format as movie results provides good UX
- ✅ **Component Architecture**: `OptionSuggestionComponent` and `PublicMusicTrackPollComponent` provide clean separation
- ✅ **Debounced Search**: 300ms debounce prevents excessive API calls during typing
- ✅ **Error Handling**: Graceful fallback when search fails or rate limits hit
- ✅ **Result Deduplication Logic**: The concept of deduplicating multiple releases of the same song

## What Didn't Work (Don't Repeat)
- ❌ **Rate Limiting Issues**: Direct MusicBrainz API calls hit 1 req/sec limit too easily
- ❌ **Poor Search Relevance**: Searching "don't stop me" returned obscure tracks instead of Queen's "Don't Stop Me Now"
- ❌ **Complex Provider Implementation**: Too much custom HTTP client code and response parsing
- ❌ **Multiple Entity Types**: Supporting artists, albums, playlists added complexity without immediate value
- ❌ **Multiple Background Servers**: Created rate limiting conflicts

## Phase 2 Scope (Focused Approach)
**Goal**: Simple, reliable song title search only

### Requirements
1. **Single Entity Type**: Songs/tracks only (no artists, albums, playlists for now)
2. **Better Search Library**: Use NPM `musicbrainz-api` package for better relevance and built-in rate limiting
3. **Frontend Integration**: Integrate the NPM library into existing frontend JS rather than separate service
4. **UI/UX Consistency**: Replicate the exact UI/UX experience from movie search (TMDB) for music search
5. **Simple Provider**: Minimal MusicBrainzRichDataProvider that delegates to frontend JS

### Implementation Plan
1. Add `musicbrainz-api` to `package.json` and frontend asset pipeline
2. Create frontend JavaScript module for MusicBrainz search with better query construction
3. Simplify `MusicBrainzRichDataProvider` to proxy requests to frontend JS
4. Remove support for artist/album/playlist search (tracks only)
5. Port the working deduplication logic to the new implementation
6. Keep the improved UI templates and component structure

### Technical Approach
- Use existing asset pipeline (same as Google Places integration)
- Frontend JS handles search logic and rate limiting
- Phoenix backend receives processed results through existing provider interface
- Maintain compatibility with existing `RichDataManager` architecture

## References
- Previous branch: `09-07-music-brain1`
- NPM Package: https://www.npmjs.com/package/musicbrainz-api
- Related to poll types: `music_track` only

## Acceptance Criteria
- [ ] Song search returns relevant results for common queries (e.g., "Don't Stop Me Now" finds Queen)
- [ ] No rate limiting issues under normal usage
- [ ] Search results display identically to movie search format (same layout, styling, interaction patterns)
- [ ] Search behavior matches TMDB: debounced input, loading states, error handling
- [ ] Deduplication prevents multiple releases of same song
- [ ] Integration follows same pattern as Google Places (frontend JS + backend provider)
- [ ] No support needed for artist/album/playlist search (scope creep prevention)
- [ ] Music poll UI matches movie poll UI exactly (same components, same styling)