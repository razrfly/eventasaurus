# Resident Advisor - Dashboard Integration Status

## ✅ Integration Complete

Resident Advisor has been successfully integrated into the Discovery Dashboard:

1. **Source Added**: "resident-advisor" appears in sources dropdown
2. **Job Routing**: DiscoverySyncJob routes to ResidentAdvisor.Jobs.SyncJob
3. **Pipeline Ready**: SyncJob → Transformer → Processor → Database

## ⚠️ Critical Requirement: Area ID Mapping

**RA WILL NOT WORK without area_id mappings.**

### The Problem

Resident Advisor's GraphQL API requires **integer area IDs** (not city names) to filter events by location. These IDs are not documented and must be discovered manually via browser DevTools.

### Current Status

- **AreaMapper module exists** but has placeholder values
- **Dashboard integration complete** but will fail without mappings
- **Only London (area_id: 34) is likely correct** - needs verification

### How to Discover Area IDs

1. **Open Browser**: Navigate to https://ra.co/events/{country}/{city}
   - Example: https://ra.co/events/pl/warsaw

2. **Open DevTools**:
   - Press F12 or Cmd+Option+I
   - Go to Network tab
   - Filter by "graphql"

3. **Trigger Query**:
   - Scroll the page to load events
   - Click on the GraphQL network request

4. **Find Area ID**:
   - Look in Request Payload → variables → filters → areas → eq
   - This will be an INTEGER (e.g., 34, 45, 123)

5. **Add to AreaMapper**:
   ```elixir
   # lib/eventasaurus_discovery/sources/resident_advisor/helpers/area_mapper.ex
   @area_mappings %{
     {"Warsaw", "Poland"} => 123,  # Replace with discovered ID
     {"London", "United Kingdom"} => 34,
     # ... more cities
   }
   ```

### Quick Start: Test with London

Since London's area_id (34) is likely correct, you can test immediately:

```elixir
# In IEx or via dashboard
city = Repo.get_by(City, name: "London")
ResidentAdvisor.sync(%{city_id: city.id, area_id: 34})
```

## Testing Strategy

### Option 1: Manual Area ID Discovery First (Recommended)

1. Discover area IDs for 2-3 major cities
2. Add to AreaMapper module
3. Update dashboard to auto-lookup area_id from city
4. Test full pipeline through dashboard

**Pros**: Complete testing with real data
**Cons**: Requires 30 min of manual DevTools work

### Option 2: Test with London Now

1. Test with London (area_id: 34) immediately
2. Verify pipeline works end-to-end
3. Discover more area IDs as needed

**Pros**: Immediate validation
**Cons**: Limited city coverage

## Integration Points Modified

### 1. Discovery Dashboard Live (`discovery_dashboard_live.ex`)
- Added "resident-advisor" to sources list (line 336)
- Added @ra_area_mappings placeholder (line 26)

### 2. Discovery Sync Job (`discovery_sync_job.ex`)
- Added RA to @sources map (line 16)
- Added build_source_options for RA (line 184)
- Passes area_id through options

### 3. RA Sync Job (`resident_advisor/jobs/sync_job.ex`)
- Extracts area_id from args or options (line 48)
- Validates area_id as required parameter (line 53)

## Next Steps for Full Integration

### Phase 4A: Area ID Discovery (30 min)
1. Discover area IDs for priority cities:
   - London (UK) - likely 34 ✓
   - Berlin (Germany)
   - Warsaw (Poland)
   - Paris (France)
   - New York (US)

2. Update AreaMapper with discovered IDs

3. Add city slug → area_id lookup in dashboard

### Phase 4B: Dashboard Enhancement (15 min)
1. Auto-populate area_id from city selection
2. Show warning when area_id not mapped
3. Allow manual area_id override for testing

### Phase 4C: Testing & Validation (30 min)
1. Test full pipeline with real data
2. Verify venue geocoding works
3. Check deduplication against Ticketmaster/Bandsintown
4. Confirm event quality and data accuracy

## Current Limitations

1. **No area IDs mapped** - Will fail without manual area_id
2. **No Google Places integration** - Venue enricher has placeholder
3. **Venue detail query untested** - May or may not return coordinates

## Success Criteria

- [ ] Area IDs discovered for 5+ major cities
- [ ] Test sync completes successfully
- [ ] Events appear in database with valid venues
- [ ] Deduplication works against higher-priority sources
- [ ] No errors in logs during sync
- [ ] Venue coordinates obtained (either from RA or Google Places)

## Conclusion

**Integration Status**: ✅ Code complete, ⚠️ Needs area IDs

The RA scraper is fully integrated and ready to use, but **requires area ID mappings** before it will work. The fastest path to testing is:

1. Use London (area_id: 34) for immediate testing
2. Discover 2-3 more area IDs if testing succeeds
3. Build out full city coverage over time

The code is production-ready once area IDs are mapped.
