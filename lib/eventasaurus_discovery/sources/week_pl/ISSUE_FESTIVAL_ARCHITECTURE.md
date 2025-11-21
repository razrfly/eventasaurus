# Issue: Implement Festival-Scoped Architecture for week.pl (Similar to Resident Advisor)

## Problem Summary

The week.pl scraper needs to be restructured to follow a festival-scoped aggregation pattern similar to the Resident Advisor scraper. Currently, restaurant reservations are treated as individual events without a unifying festival/campaign container.

## User Requirements

From user feedback:
> "When we set them up as a scraper, also set them up in the context of a scope of a festival. So it's like the Resident Advisor one, essentially like we have these individual activities that are in the context of being in a festival, or these individual restaurants are in the context of being in a festival."

## Desired Architecture

### Festival Container (Parent Entity)
- **Festival Event**: RestaurantWeek Kraków Winter 2025
  - Represents the overall campaign/festival
  - Aggregates all participating restaurants
  - Has date range (e.g., Winter 2025: specific start and end dates)
  - Has pricing information (e.g., 63 PLN menu)
  - Has location (Kraków, Poland)
  - Provides festival-level browsing and filtering

### Individual Restaurant Events (Child Entities)
- **Restaurant Reservation Activities**: Individual events for each restaurant
  - La Forchetta RestaurantWeek reservation
  - Wola Verde RestaurantWeek reservation
  - Molto RestaurantWeek reservation
  - etc.
- Each restaurant is a separate bookable activity
- Each has its own time slots and availability
- Each is associated with the parent festival event

### User Experience Benefits
1. **Festival Discovery**: Users can browse RestaurantWeek as a festival
2. **Restaurant Selection**: Within the festival, users can see all participating restaurants
3. **Individual Booking**: Each restaurant is independently bookable
4. **Contextual Information**: Clear that this is part of RestaurantWeek campaign
5. **Temporal Grouping**: All restaurants grouped by festival edition (Winter 2025, Summer 2025, etc.)

## Reference Architecture: Resident Advisor

The Resident Advisor scraper already implements this pattern:

```
Festival Event: "Movement Festival 2025"
├── Individual Event: "Carl Craig at Movement"
├── Individual Event: "Jeff Mills at Movement"
├── Individual Event: "Derrick May at Movement"
└── Individual Event: "Juan Atkins at Movement"
```

For week.pl, it should be:

```
Festival Event: "RestaurantWeek Kraków Winter 2025"
├── Restaurant Event: "La Forchetta RestaurantWeek"
├── Restaurant Event: "Wola Verde RestaurantWeek"
├── Restaurant Event: "Molto RestaurantWeek"
└── Restaurant Event: "Pod Różą RestaurantWeek"
```

## Current Implementation Issues

### 1. No Festival Parent Entity
Currently, each restaurant is scraped independently without a unifying festival container:
- Users can't browse RestaurantWeek as a festival
- No aggregated view of all participating restaurants
- Missing context about the campaign/festival
- No temporal grouping by festival edition

### 2. Missing Festival Metadata
The scraper has festival information in job arguments but doesn't create a festival entity:
- `festival_code`: "RWT25W" (RestaurantWeek Test Winter 2025)
- `festival_name`: "RestaurantWeek Test Winter"
- `festival_price`: 63.0 PLN
- This data is logged but not used to create a festival event

### 3. No Relationship Between Restaurants
- Restaurants are independent events with no connection
- Can't filter or browse by festival edition
- Can't see "all RestaurantWeek restaurants in Kraków"
- Missing the "festival experience" for users

## Implementation Requirements

### 1. Create Festival Event
For each RestaurantWeek edition, create a parent festival event:
- **Title**: "RestaurantWeek Kraków Winter 2025"
- **Type**: Festival/Campaign container
- **Date Range**: Festival start and end dates
- **Location**: Kraków, Poland
- **Description**: Information about RestaurantWeek campaign
- **Pricing**: Standard menu price (63 PLN)
- **Metadata**: Festival code, edition, participating restaurant count

### 2. Create Individual Restaurant Events
For each restaurant, create a child event:
- **Title**: "{Restaurant Name} RestaurantWeek"
- **Type**: Restaurant reservation activity
- **Parent**: Link to festival event
- **Time Slots**: Individual booking times (18:00, 18:30, etc.)
- **Location**: Restaurant address
- **Description**: Restaurant details + festival menu information
- **Pricing**: Festival menu price (inherited from festival)

### 3. Update Event Processor
Modify `EventProcessor` to handle:
- Festival event creation and updates
- Restaurant event creation with parent relationship
- Consolidation at both festival and restaurant levels
- Proper `last_seen_at` tracking for both levels

### 4. Update Jobs Structure

#### SyncJob (Coordinator Level)
- Create or update festival event first
- Then queue regional restaurant sync jobs
- Pass festival event ID to child jobs

#### RegionSyncJob (Region Level)
- Receive festival event ID from parent
- Find all restaurants in region
- Queue restaurant detail jobs with festival context

#### RestaurantDetailJob (Restaurant Level)
- Receive festival event ID from parent
- Create/update restaurant event with parent reference
- Extract time slots and create as activities within restaurant event

### 5. Database Schema Considerations

Consider adding fields to support festival relationships:
- `parent_event_id` - Link to festival event
- `event_type` - Distinguish between "festival" and "activity"
- `festival_metadata` - Store festival-specific data (code, edition, etc.)

Or use existing relationship patterns from Resident Advisor implementation.

## Benefits of Festival Architecture

### For Users
1. **Discovery**: Browse RestaurantWeek as a curated festival experience
2. **Context**: Understand that restaurants are part of special campaign
3. **Filtering**: Filter by festival edition, city, price tier
4. **Planning**: See all participating restaurants in one place

### For System
1. **Organization**: Clear hierarchical structure
2. **Scalability**: Easy to add new festival editions
3. **Maintenance**: Update festival info centrally
4. **Analytics**: Track festival-level metrics and popularity

### For Data Quality
1. **Consistency**: All restaurants share festival metadata
2. **Completeness**: Festival dates and pricing centrally managed
3. **Accuracy**: Single source of truth for festival information

## Example Data Structure

### Festival Event
```elixir
%Event{
  title: "RestaurantWeek Kraków Winter 2025",
  external_id: "week_pl:festival:krakow:RWT25W",
  event_type: "festival",
  starts_at: ~U[2025-01-15 00:00:00Z],
  ends_at: ~U[2025-01-28 23:59:59Z],
  location: "Kraków, Poland",
  description: "RestaurantWeek Winter 2025 - 63 PLN special menu at participating restaurants",
  metadata: %{
    festival_code: "RWT25W",
    festival_price: 63.0,
    edition: "Winter 2025",
    participating_restaurants: 85
  }
}
```

### Restaurant Event (Child)
```elixir
%Event{
  title: "La Forchetta RestaurantWeek",
  external_id: "week_pl:restaurant:la-forchetta:RWT25W",
  event_type: "restaurant_reservation",
  parent_event_id: 123,  # Links to festival event
  starts_at: ~U[2025-01-15 18:00:00Z],
  ends_at: ~U[2025-01-15 22:00:00Z],
  location: "ul. Przykładowa 10, Kraków",
  description: "Italian restaurant participating in RestaurantWeek...",
  metadata: %{
    restaurant_slug: "la-forchetta",
    restaurant_id: "1373",
    festival_code: "RWT25W",
    festival_price: 63.0,
    time_slots: [1080, 1110, 1140, 1170, 1200]  # 18:00, 18:30, 19:00, etc.
  }
}
```

## Implementation Phases

### Phase 1: Festival Event Creation
- Modify SyncJob to create festival event
- Extract festival metadata from job arguments
- Store festival event ID for child jobs

### Phase 2: Restaurant Event Linking
- Modify RestaurantDetailJob to receive festival_event_id
- Create restaurant events with parent relationship
- Update event processor to handle parent-child relationships

### Phase 3: Festival-Level Aggregation
- Update event queries to support parent-child filtering
- Add festival browsing UI
- Implement festival-level statistics and metrics

### Phase 4: Multi-City and Multi-Edition Support
- Support multiple cities in same festival edition
- Support multiple festival editions (Winter, Summer, etc.)
- Handle festival lifecycle (upcoming, active, completed)

## Related Files

- `lib/eventasaurus_discovery/sources/week_pl/jobs/sync_job.ex` - Coordinator job
- `lib/eventasaurus_discovery/sources/week_pl/jobs/region_sync_job.ex` - Region-level job
- `lib/eventasaurus_discovery/sources/week_pl/jobs/restaurant_detail_job.ex` - Restaurant-level job
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex` - Event consolidation logic

## Reference Implementation

Review Resident Advisor scraper for festival architecture patterns:
- How festival events are created
- How child events are linked to parents
- How consolidation works at both levels
- How UI displays festival hierarchies

## Success Criteria

1. ✅ Festival event created for each RestaurantWeek edition
2. ✅ All restaurants linked to festival event
3. ✅ Users can browse RestaurantWeek as a festival
4. ✅ Individual restaurants remain independently bookable
5. ✅ Festival metadata (dates, pricing, code) centrally managed
6. ✅ Support for multiple cities and editions
7. ✅ Clear parent-child relationship in database and UI

## Notes

- This architectural change requires coordination with event processor and UI
- Should maintain backward compatibility with existing events
- Consider migration strategy for existing week.pl events
- Follow established patterns from Resident Advisor implementation
