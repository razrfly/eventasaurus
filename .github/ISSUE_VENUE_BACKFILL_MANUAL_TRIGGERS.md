# 💡 Feature Request: Manual Venue Image Enrichment Triggers with Cooldown Override

## Summary

Add manual trigger capabilities to the venue backfill interface at `/admin/discovery/stats/city/{slug}` to allow administrators to:
1. Trigger image enrichment for individual venues (not just bulk)
2. Override the 7-day cooldown period for urgent/missed cases
3. Force re-enrichment for venues with incomplete data

## Current Limitations

### 1. Geocoding Doesn't Fix Missing Addresses

**Question:** Does the geocoding process automatically fix missing addresses?

**Answer:** **No**, the current geocoding implementation does NOT update venue addresses. Here's why:

**What Geocoding Currently Does:**
```elixir
# lib/eventasaurus_discovery/venue_images/enrichment_job.ex:481-522
defp reverse_geocode_venue(venue, providers) do
  # Uses nearby search to find Google Places business ID
  # Updates ONLY provider_ids field, NOT address
  case search_nearby_business(venue) do
    {:ok, place_id} ->
      Repo.update_all(
        from(v in Venue, where: v.id == ^venue.id),
        set: [
          provider_ids: updated_provider_ids,  # ✅ Updates this
          updated_at: NaiveDateTime.utc_now()
          # ❌ Does NOT update address field
        ]
      )
  end
end
```

**What Gets Updated:**
- ✅ `provider_ids` - Gets Google Places place_id (or other provider IDs)
- ✅ `geocoding_performance` - Metadata about geocoding attempt
- ❌ `address` - **NOT updated**

**Why Addresses Stay Incomplete:**
1. Geocoding uses the **existing address** as input to find provider IDs
2. It doesn't fetch back address details from the providers
3. If the original address is incomplete ("Wawel 5" without city), it stays incomplete
4. If there's no address ("Warsztat"), geocoding still works via coordinates but doesn't populate the address

### 2. No Manual Control Per Venue

**Current State:**
- Only bulk backfill available (select city + limit + providers)
- No way to target specific venues that need attention
- No UI to trigger enrichment for individual venues

**Examples from Production:**

From https://wombie.com/admin/discovery/stats/city/krakow:

```
Venues with Incomplete Addresses:
- "Zamek Królewski na Wawelu" → "Wawel 5" (missing city/country)
- "Centrum Kongresowe ICE Kraków" → "ul. Konopnickiej 17" (missing postal code)
- "Mikołaja Kopernika 15" → "" (missing everything except street)
- "Warsztat" → "" (no address at all)
```

These venues have coordinates and provider IDs, but the address field is incomplete or empty.

### 3. 7-Day Cooldown Can't Be Overridden

**Current Behavior:**
- After any enrichment attempt, venues enter a 7-day cooldown
- Even if the attempt failed or produced incomplete results
- No way to manually override for urgent cases
- Administrators must wait 7 days to retry

**Code Reference:**
```elixir
# lib/eventasaurus_discovery/venue_images/backfill_orchestrator_job.ex:189-208
defp find_venues_without_images(city_id, limit, providers) do
  cooldown_days = Application.get_env(:eventasaurus, :venue_images, [])[:no_images_cooldown_days] || 7

  # SQL query filters out venues checked within cooldown period
  where: fragment(
    """
    ? IS NULL OR
    ?->>'last_checked_at' IS NULL OR
    (?->>'last_checked_at')::timestamp < (NOW() AT TIME ZONE 'UTC') - make_interval(days => ?)
    """,
    v.image_enrichment_metadata,
    v.image_enrichment_metadata,
    v.image_enrichment_metadata,
    ^cooldown_days
  )
end
```

## Proposed Solution

### Feature 1: Per-Venue Manual Triggers

Add action buttons to the venue backfill table:

**UI Changes:**
```
Venue Name | Address | Status | Actions
-----------+---------+--------+-------------------
Warsztat   | (empty) | High   | [Enrich Now 🚀] [View Details 👁️]
```

**Implementation:**
1. Add action column to venue table in admin interface
2. "Enrich Now" button triggers immediate enrichment job
3. Optional modal with enrichment options:
   - ☑️ Force refresh (ignore staleness)
   - ☑️ Enable geocoding
   - ☑️ Select specific providers
   - ☑️ Override cooldown period

**Example Flow:**
```elixir
# New function in admin live view
def handle_event("enrich_venue", %{"venue_id" => venue_id}, socket) do
  # Create single enrichment job with force and geocode options
  EventasaurusDiscovery.VenueImages.EnrichmentJob.new(%{
    venue_id: venue_id,
    providers: ["google_places"],
    geocode: true,
    force: true  # Override cooldown
  })
  |> Oban.insert()

  {:noreply, put_flash(socket, :info, "Enrichment job queued for venue #{venue_id}")}
end
```

### Feature 2: Bulk Actions with Override

Add checkbox selection + bulk action dropdown:

**UI:**
```
[Select All] [ 5 selected ]

Bulk Actions: [▼ Enrich Selected (Force)]
              [▼ Enrich Selected (Respect Cooldown)]
              [▼ Export Selection]
```

**Implementation:**
```elixir
def handle_event("bulk_enrich", %{"venue_ids" => ids, "force" => force}, socket) do
  jobs =
    Enum.map(ids, fn id ->
      EventasaurusDiscovery.VenueImages.EnrichmentJob.new(%{
        venue_id: id,
        geocode: true,
        force: force  # User-controlled override
      })
    end)

  Oban.insert_all(jobs)

  {:noreply, put_flash(socket, :info, "#{length(ids)} enrichment jobs queued")}
end
```

### Feature 3: Advanced Filters

Add filters to find problem venues:

**Filter Options:**
- ☑️ Missing addresses
- ☑️ Incomplete addresses (no city/postal code)
- ☑️ Failed last enrichment
- ☑️ In cooldown period (show even though can't bulk enrich)
- ☑️ Never attempted

**SQL Query Helper:**
```elixir
defp filter_venues(query, :missing_address) do
  from v in query,
    where: is_nil(v.address) or v.address == ""
end

defp filter_venues(query, :incomplete_address) do
  from v in query,
    where: not is_nil(v.address) and
           (not like(v.address, "%,%") or  # No comma = probably incomplete
            fragment("LENGTH(?)", v.address) < 20)
end

defp filter_venues(query, :in_cooldown) do
  cooldown_days = 7
  from v in query,
    where: fragment(
      "(?->>'last_checked_at')::timestamp >= (NOW() - make_interval(days => ?))",
      v.image_enrichment_metadata,
      ^cooldown_days
    )
end
```

### Feature 4: Enrichment Status Dashboard

Add status indicators for each venue:

**Status Badges:**
- 🟢 **Success** - Has images, recently enriched
- 🟡 **Partial** - Some images, missing providers
- 🔴 **Failed** - Last attempt failed with error
- ⚪ **No Images** - Providers returned ZERO_RESULTS
- 🕐 **Cooldown** - In 7-day waiting period (X days remaining)
- ⭕ **Never Tried** - Never attempted enrichment

**Implementation:**
```elixir
defp get_enrichment_status(venue) do
  metadata = venue.image_enrichment_metadata || %{}
  images_count = length(venue.venue_images || [])

  cond do
    images_count > 0 -> {:success, "Has #{images_count} images"}

    in_cooldown?(metadata) ->
      days_left = cooldown_days_remaining(metadata)
      {:cooldown, "#{days_left} days until retry"}

    metadata["last_attempt_result"] == "no_images" ->
      {:no_images, "Providers have no images"}

    metadata["last_attempt_result"] == "error" ->
      {:failed, metadata["error_details"]}

    is_nil(metadata["last_checked_at"]) ->
      {:never_tried, "Never attempted"}

    true ->
      {:unknown, "Status unclear"}
  end
end
```

## Technical Implementation Details

### 1. Add Per-Venue Enrichment Controller Action

**File:** `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex`

```elixir
@impl true
def handle_event("enrich_single_venue", params, socket) do
  %{
    "venue_id" => venue_id,
    "force" => force,
    "geocode" => geocode,
    "providers" => providers
  } = params

  # Validate permissions
  unless can_manage_backfill?(socket.assigns.current_user) do
    {:noreply, put_flash(socket, :error, "Unauthorized")}
  else
    # Parse and validate venue_id
    case Integer.parse(venue_id) do
      {venue_id_int, ""} ->
        # Create enrichment job
        case EventasaurusDiscovery.VenueImages.EnrichmentJob.new(%{
          venue_id: venue_id_int,
          providers: providers,
          geocode: geocode,
          force: force
        })
        |> Oban.insert() do
          {:ok, job} ->
            {:noreply,
              socket
              |> put_flash(:info, "Enrichment job #{job.id} queued for venue #{venue_id}")
              |> assign(:selected_venues, [])}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to queue job: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid venue ID")}
    end
  end
end
```

### 2. Add UI Components

**File:** `lib/eventasaurus_web/live/admin/discovery_dashboard_live.html.heex`

```heex
<!-- Per-venue action button -->
<button
  phx-click="enrich_single_venue"
  phx-value-venue_id={venue.id}
  phx-value-force="true"
  phx-value-geocode="true"
  phx-value-providers={Jason.encode!(["google_places"])}
  class="inline-flex items-center px-2 py-1 text-xs font-medium text-white bg-blue-600 rounded hover:bg-blue-700"
  title="Force enrichment now (override cooldown)"
>
  🚀 Enrich Now
</button>

<!-- Show cooldown status if applicable -->
<%= if in_cooldown?(venue) do %>
  <span class="text-xs text-gray-500">
    ⏳ Cooldown: <%= cooldown_days_remaining(venue) %> days
  </span>
<% end %>
```

### 3. Add Cooldown Helper Functions

```elixir
defp in_cooldown?(venue) do
  cooldown_days = Application.get_env(:eventasaurus, :venue_images, [])[:no_images_cooldown_days] || 7
  metadata = venue.image_enrichment_metadata || %{}

  case metadata["last_checked_at"] do
    nil -> false
    last_checked ->
      case DateTime.from_iso8601(last_checked) do
        {:ok, dt, _} ->
          cutoff = DateTime.add(DateTime.utc_now(), -cooldown_days, :day)
          DateTime.compare(dt, cutoff) == :gt
        _ -> false
      end
  end
end

defp cooldown_days_remaining(venue) do
  cooldown_days = Application.get_env(:eventasaurus, :venue_images, [])[:no_images_cooldown_days] || 7
  metadata = venue.image_enrichment_metadata || %{}

  case metadata["last_checked_at"] do
    nil -> 0
    last_checked ->
      case DateTime.from_iso8601(last_checked) do
        {:ok, dt, _} ->
          next_attempt = DateTime.add(dt, cooldown_days, :day)
          diff_seconds = DateTime.diff(next_attempt, DateTime.utc_now())
          max(0, ceil(diff_seconds / 86400))
        _ -> 0
      end
  end
end
```

## User Stories

### Story 1: Fix Incomplete Address Venue

**As an:** Administrator
**I want to:** Manually trigger enrichment for "Warsztat" venue with no address
**So that:** I can get images even though the address is incomplete

**Acceptance Criteria:**
- ✅ See "Enrich Now" button next to "Warsztat" in venue list
- ✅ Click button triggers immediate enrichment job
- ✅ Job uses geocoding (coordinates) to find venue despite missing address
- ✅ Job completes and fetches images from Google Places
- ✅ Venue updated with images and Google Places provider ID

### Story 2: Override Cooldown for Urgent Venue

**As an:** Administrator
**I want to:** Retry enrichment for a high-priority venue even though it's in cooldown
**So that:** I can fix issues without waiting 7 days

**Acceptance Criteria:**
- ✅ See cooldown status ("⏳ 5 days remaining")
- ✅ "Enrich Now" button is still available (not disabled)
- ✅ Clicking button shows confirmation modal explaining cooldown override
- ✅ Job runs immediately despite cooldown
- ✅ Cooldown timer resets after new attempt

### Story 3: Bulk Fix Problem Venues

**As an:** Administrator
**I want to:** Select multiple venues with incomplete addresses and enrich them all
**So that:** I can efficiently fix data gaps

**Acceptance Criteria:**
- ✅ Filter venues by "Missing/Incomplete Address"
- ✅ Select checkboxes for multiple venues
- ✅ Choose "Bulk Enrich (Force)" from dropdown
- ✅ All selected venues get enrichment jobs queued
- ✅ Success message shows count of jobs queued

## Benefits

### 1. Improved Data Quality
- Fix incomplete addresses by manually targeting problem venues
- Override cooldown for urgent/high-priority venues
- Retry failed enrichments without waiting

### 2. Better Admin Control
- Granular control over which venues to enrich
- Transparency into cooldown status
- Ability to respond quickly to data issues

### 3. Reduced Manual Work
- Bulk actions for common scenarios
- Filters to find problem venues quickly
- No need to wait for scheduled jobs or cooldown periods

### 4. Better User Experience
- Venues get images faster when manually triggered
- Admin can proactively fix data gaps
- Clear visibility into enrichment status

## Open Questions

### 1. Should Manual Triggers Always Override Cooldown?

**Option A:** Always override (force=true)
- ✅ Gives admins full control
- ❌ Could waste API credits on repeated failures

**Option B:** Require explicit confirmation
- ✅ Prevents accidental overrides
- ✅ Forces admin to acknowledge cooldown
- ❌ Extra click required

**Recommendation:** Option B - Show confirmation modal when overriding cooldown

### 2. Should We Add Rate Limiting for Manual Triggers?

**Concern:** Admin could accidentally trigger hundreds of enrichments

**Options:**
- Add per-admin rate limit (e.g., 100 venues per hour)
- Add confirmation for bulk actions >10 venues
- Add cost estimate before triggering

**Recommendation:** Add confirmation for bulk actions >10 with estimated cost

### 3. Should We Show Enrichment Job Status in Real-Time?

**Options:**
- Add "View Job Status" link that opens Oban UI
- Show real-time progress in admin interface
- Just show "Job queued" message

**Recommendation:** Start with Oban UI link, add real-time progress in future

## Related Issues

- #2040 - Fixed geocoding functionality (prerequisite)
- This builds on the geocoding fix to add manual control

## Priority

**Medium-High** - Would significantly improve admin workflow and data quality

## Estimated Effort

- **Backend:** 4-6 hours
  - Add per-venue enrichment function
  - Add cooldown helpers
  - Add permission checks

- **Frontend:** 4-6 hours
  - Add action buttons
  - Add bulk selection
  - Add filters
  - Add confirmation modals

- **Testing:** 2-3 hours
  - Test manual triggers
  - Test cooldown override
  - Test bulk actions

**Total:** 10-15 hours

---

**Created:** 2025-10-28
**Related to:** Venue image enrichment, geocoding, admin tools
**Addresses:** Missing addresses, cooldown limitations, manual control gaps
