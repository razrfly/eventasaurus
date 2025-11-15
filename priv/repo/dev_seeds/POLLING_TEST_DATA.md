# Polling Test Data Quick Reference

**Purpose**: Comprehensive polling test data for mobile testing and debugging across all poll types and voting systems.

**Coverage**: 9 poll types × 4 voting systems = **36 polls total**

**URL Stability**: All URLs use fixed slugs and remain constant across re-seeds ✅

---

## 🎬 Direct Test URLs (Stable Across Re-seeds)

### 1. Movie Night - Poll Testing
**Event**: http://localhost:4000/poll-test-movies
**Poll Type**: `movie` | **Event Slug**: `poll-test-movies`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-movies/polls/1
  - *Movie Selection - Yes/No Voting*
  - Vote yes/no on: Shawshank Redemption, The Godfather, The Dark Knight, Pulp Fiction

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-movies/polls/2
  - *Movie Selection - Approval Voting*
  - Select up to 2: Inception, Forrest Gump, The Matrix, Goodfellas

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-movies/polls/3
  - *Movie Selection - Ranked Choice*
  - Rank: Parasite, Spirited Away, Interstellar, The Prestige

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-movies/polls/4
  - *Movie Selection - Star Rating*
  - Rate 1-5 stars: Whiplash, La La Land, Everything Everywhere All at Once, The Grand Budapest Hotel

---

### 2. Cocktail Happy Hour - Poll Testing
**Event**: http://localhost:4000/poll-test-cocktails
**Poll Type**: `cocktail` | **Event Slug**: `poll-test-cocktails`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-cocktails/polls/1
  - *Cocktail Selection - Yes/No Voting*
  - Vote yes/no on: Margarita, Mojito, Old Fashioned

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-cocktails/polls/2
  - *Cocktail Selection - Approval Voting*
  - Select up to 3: Cosmopolitan, Piña Colada, Mai Tai

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-cocktails/polls/3
  - *Cocktail Selection - Ranked Choice*
  - Rank: Whiskey Sour, Negroni, Manhattan

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-cocktails/polls/4
  - *Cocktail Selection - Star Rating*
  - Rate 1-5 stars: Aperol Spritz, Espresso Martini, French 75

---

### 3. Music Festival - Poll Testing
**Event**: http://localhost:4000/poll-test-music
**Poll Type**: `music_track` | **Event Slug**: `poll-test-music`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-music/polls/1
  - *Opening Set - Yes/No Voting*
  - Vote yes/no on: Billie Jean, Bohemian Rhapsody, Superstition, Don't Stop Believin'

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-music/polls/2
  - *Festival Headliner - Approval Voting*
  - Select up to 3: Blinding Lights, Rolling in the Deep, Uptown Funk, Mr. Brightside

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-music/polls/3
  - *Encore Set - Ranked Choice*
  - Rank: Sweet Child O' Mine, September, Livin' on a Prayer, I Wanna Dance with Somebody

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-music/polls/4
  - *Acoustic Set - Star Rating*
  - Rate 1-5 stars: Wonderwall, Fast Car, Hallelujah, Tears in Heaven

---

### 4. Restaurant Week - Poll Testing
**Event**: http://localhost:4000/poll-test-places
**Poll Type**: `places` | **Event Slug**: `poll-test-places`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-places/polls/1
  - *Restaurant Selection - Yes/No Voting*
  - Vote yes/no on: Mario's Italian Kitchen, Sakura Sushi Bar, The Steakhouse

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-places/polls/2
  - *Restaurant Selection - Approval Voting*
  - Select up to 2: Taco Fiesta, Green Garden Bistro, Thai Spice Kitchen

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-places/polls/3
  - *Restaurant Selection - Ranked Choice*
  - Rank: Le Petit Bistro, Seoul Kitchen, The Burger Joint

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-places/polls/4
  - *Restaurant Selection - Star Rating*
  - Rate 1-5 stars: Bella Vista, Ramen House, BBQ Brothers

---

### 5. Venue Selection - Poll Testing
**Event**: http://localhost:4000/poll-test-venues
**Poll Type**: `venue` | **Event Slug**: `poll-test-venues`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-venues/polls/1
  - *Conference Venue - Yes/No Voting*
  - Vote yes/no on: Downtown Convention Center, Riverside Hotel & Conference, Tech Hub Meeting Space

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-venues/polls/2
  - *Wedding Venue - Approval Voting*
  - Select up to 2: Garden Estate, Historic Manor, Beachside Resort

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-venues/polls/3
  - *Corporate Retreat - Ranked Choice*
  - Rank: Mountain Lodge, Urban Hotel, Lakeside Resort

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-venues/polls/4
  - *Art Exhibition - Star Rating*
  - Rate 1-5 stars: Contemporary Gallery, Historic Museum, Warehouse Loft

---

### 6. Workshop Scheduling - Poll Testing
**Event**: http://localhost:4000/poll-test-times
**Poll Type**: `time` | **Event Slug**: `poll-test-times`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-times/polls/1
  - *Workshop Time - Yes/No Voting*
  - Vote yes/no on: Morning Session (9-12 AM), Afternoon (2-5 PM), Evening (6-9 PM)

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-times/polls/2
  - *Meeting Time - Approval Voting*
  - Select up to 2: Monday 10 AM, Wednesday 2 PM, Friday 4 PM

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-times/polls/3
  - *Class Schedule - Ranked Choice*
  - Rank: Tue/Thu 9 AM, Mon/Wed/Fri 1 PM, Saturday 10 AM-2 PM

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-times/polls/4
  - *Practice Time - Star Rating*
  - Rate 1-5 stars: Early Bird (6-7:30 AM), Lunch Break (12-1 PM), Evening (7-8:30 PM)

---

### 7. Event Date Planning - Poll Testing
**Event**: http://localhost:4000/poll-test-dates
**Poll Type**: `date_selection` | **Event Slug**: `poll-test-dates`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-dates/polls/1
  - *Event Date - Yes/No Voting*
  - Vote yes/no on: March 15, March 21, March 30 (2025)

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-dates/polls/2
  - *Meetup Date - Approval Voting*
  - Select up to 2: April 10, April 12, April 15 (2025)

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-dates/polls/3
  - *Retreat Date - Ranked Choice*
  - Rank: June 5-7, June 12-14, June 19-21 (2025)

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-dates/polls/4
  - *Launch Date - Star Rating*
  - Rate 1-5 stars: May 5, May 14, May 23 (2025)

---

### 8. General Decisions - Poll Testing
**Event**: http://localhost:4000/poll-test-general
**Poll Type**: `general` | **Event Slug**: `poll-test-general`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-general/polls/1
  - *Event Activities - Yes/No Voting*
  - Vote yes/no on: Team Building Games, Networking Session, Guest Speaker

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-general/polls/2
  - *Event Format - Approval Voting*
  - Select up to 2: In-Person Only, Hybrid Event, Fully Virtual

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-general/polls/3
  - *Event Theme - Ranked Choice*
  - Rank: Tropical Paradise, Masquerade Ball, Casino Night

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-general/polls/4
  - *Event Features - Star Rating*
  - Rate 1-5 stars: Live Entertainment, Photo Booth, Premium Catering

---

### 9. Custom Options - Poll Testing
**Event**: http://localhost:4000/poll-test-custom
**Poll Type**: `custom` | **Event Slug**: `poll-test-custom`

- 🗳️ **[Binary Voting]** Poll #1: http://localhost:4000/poll-test-custom/polls/1
  - *Project Priorities - Yes/No Voting*
  - Vote yes/no on: Feature Development, Bug Fixes, Performance Optimization

- ✅ **[Approval Voting]** Poll #2: http://localhost:4000/poll-test-custom/polls/2
  - *Team Initiatives - Approval Voting*
  - Select up to 3: Mentorship Program, Learning Budget, Flex Time Policy

- 🔢 **[Ranked Choice]** Poll #3: http://localhost:4000/poll-test-custom/polls/3
  - *Office Perks - Ranked Choice*
  - Rank: Remote Work, Gym Membership, Free Lunch

- ⭐ **[Star Rating]** Poll #4: http://localhost:4000/poll-test-custom/polls/4
  - *Tool Preferences - Star Rating*
  - Rate 1-5 stars: Project Management Software, Communication Platform, Design Tools

---

## 📱 Mobile Testing Quick Access

Copy-paste ready URLs for mobile device testing:

### iPhone SE (375px width)
- **Star Rating Tests**:
  - Movies: http://localhost:4000/poll-test-movies/polls/4
  - Cocktails: http://localhost:4000/poll-test-cocktails/polls/4
  - Music: http://localhost:4000/poll-test-music/polls/4
  - Places: http://localhost:4000/poll-test-places/polls/4

- **Ranked Choice Tests**:
  - Movies: http://localhost:4000/poll-test-movies/polls/3
  - Venues: http://localhost:4000/poll-test-venues/polls/3
  - Times: http://localhost:4000/poll-test-times/polls/3

### iPad (768px width)
- **All Poll Types**:
  - General: http://localhost:4000/poll-test-general
  - Custom: http://localhost:4000/poll-test-custom
  - Dates: http://localhost:4000/poll-test-dates

### Android (360px width)
- **Binary Voting Tests**:
  - Movies: http://localhost:4000/poll-test-movies/polls/1
  - Cocktails: http://localhost:4000/poll-test-cocktails/polls/1
  - Music: http://localhost:4000/poll-test-music/polls/1

---

## 🔧 Testing Commands

```bash
# Clean and reseed with fixed slugs
mix seed.clean && mix seed.dev

# URLs remain stable after re-seeding
open http://localhost:4000/poll-test-movies

# Quick test all poll types (opens 9 tabs)
open http://localhost:4000/poll-test-movies && \
open http://localhost:4000/poll-test-cocktails && \
open http://localhost:4000/poll-test-music && \
open http://localhost:4000/poll-test-places && \
open http://localhost:4000/poll-test-venues && \
open http://localhost:4000/poll-test-times && \
open http://localhost:4000/poll-test-dates && \
open http://localhost:4000/poll-test-general && \
open http://localhost:4000/poll-test-custom
```

---

## 📊 Coverage Matrix

| Poll Type       | Binary | Approval | Ranked | Star | Status |
|-----------------|--------|----------|--------|------|--------|
| movie           | ✅     | ✅       | ✅     | ✅   | ✅     |
| cocktail        | ✅     | ✅       | ✅     | ✅   | ✅     |
| music_track     | ✅     | ✅       | ✅     | ✅   | ✅     |
| places          | ✅     | ✅       | ✅     | ✅   | ✅     |
| venue           | ✅     | ✅       | ✅     | ✅   | ✅     |
| time            | ✅     | ✅       | ✅     | ✅   | ✅     |
| date_selection  | ✅     | ✅       | ✅     | ✅   | ✅     |
| general         | ✅     | ✅       | ✅     | ✅   | ✅     |
| custom          | ✅     | ✅       | ✅     | ✅   | ✅     |

**Total**: 36/36 combinations covered (100% ✅)

---

## 🎯 Use Cases

### Mobile Debugging
1. **Problem**: Star rating not displaying correctly on iPhone SE
2. **Solution**: Test at http://localhost:4000/poll-test-movies/polls/4
3. **Verify**: Check all star rating polls (4 total) for consistency

### Feature Testing
1. **Test binary voting**: Visit all `/polls/1` URLs
2. **Test approval voting**: Visit all `/polls/2` URLs
3. **Test ranked choice**: Visit all `/polls/3` URLs
4. **Test star rating**: Visit all `/polls/4` URLs

### Regression Testing
1. Seed database with stable URLs
2. Run automated tests against known endpoints
3. Compare results across browser/device combinations

---

## 📝 Notes

- **Slug Stability**: All event slugs use explicit `poll-test-*` format that never changes
- **Poll Numbers**: Polls are created in order (1=binary, 2=approval, 3=ranked, 4=star)
- **Data Freshness**: Re-seeding maintains same URLs but refreshes all poll data
- **Participants**: Each event has 12 random participants for realistic voting scenarios
- **Image Data**: Cocktail polls include real CocktailDB images and descriptions

---

## 🐛 Debugging Tips

### Poll Not Showing
1. Check event exists: `curl http://localhost:4000/poll-test-movies`
2. Check database: `SELECT * FROM polls WHERE event_id IN (SELECT id FROM events WHERE slug = 'poll-test-movies')`
3. Verify Phase V ran: Look for "Phase V: Mobile Testing" in seed output

### Slug Conflicts
- All test slugs use `poll-test-*` prefix to avoid conflicts
- If conflict occurs, check for manually created events with same slug

### Mobile Issues
- Test at exact dimensions: Chrome DevTools > Device Mode
- Common breakpoints: 375px (iPhone SE), 768px (iPad), 360px (Android)
- Check CSS media queries and responsive layouts

---

**Last Updated**: January 2025
**Issue**: #2244
**Seed File**: `priv/repo/dev_seeds/features/polls/mobile_testing_polls.exs`
