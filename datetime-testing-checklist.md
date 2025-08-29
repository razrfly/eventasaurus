# DateTime Testing Checklist

## Testing Prerequisites
- Have events in different timezones (e.g., "America/New_York", "Europe/London", "Asia/Tokyo")
- Test during both standard time and daylight saving time if possible
- Check both logged-in and guest views where applicable

## 1. Event Management Page (`/events/:slug`)
**File**: `event_manage_live.ex`

### Test Cases:
- [ ] Event date/time displays correctly in event's timezone (not UTC)
- [ ] Should show proper timezone abbreviation (e.g., "EST", "PST", "JST")
- [ ] Verify format shows: "Day, Month Date, Year at H:MM AM/PM TIMEZONE"

**Test URL**: `/events/[slug]` (where slug is your event's URL slug)

---

## 2. Event Creation (`/events/new`)
**File**: `event_live/new.ex`

### Test Cases:
- [ ] Date and time inputs save correctly with selected timezone
- [ ] Creating event at 5:00 PM EST should display as 5:00 PM EST (not 10:00 PM UTC)
- [ ] Ticket modal datetime inputs:
  - [ ] Sale start date/time respects event timezone
  - [ ] Sale end date/time respects event timezone
- [ ] After creation, verify times display correctly on event page

**Test URL**: `/events/new`

---

## 3. Event Editing (`/events/:slug/edit`)
**File**: `event_live/edit.ex`

### Test Cases:
- [ ] Existing event times display correctly in form fields
- [ ] Date field shows correct date in event timezone
- [ ] Time field shows correct time in event timezone
- [ ] Changing timezone updates display times appropriately
- [ ] Ticket editing:
  - [ ] Existing ticket dates show in event timezone
  - [ ] New ticket dates save with event timezone

**Test URL**: `/events/[slug]/edit`

---

## 4. Activity Creation Component
**File**: `activity_creation_component.ex`

### Test Cases:
- [ ] Activity date/time validation works (shows error for invalid dates)
- [ ] Activity date/time saves in event timezone
- [ ] Error message appears when date or time is missing
- [ ] Error message appears for invalid date/time format
- [ ] Saved activities display with correct timezone

**Test URLs**: 
- Event history section where activities are created
- Look for "Record Activity" or similar button

---

## 5. Poll Components
**Files**: `poll_creation_component.ex`, `poll_details_component.ex`

### Poll Creation Tests:
- [ ] List building deadline datetime-local input works
- [ ] Voting deadline datetime-local input works
- [ ] Deadlines save with event timezone
- [ ] Created polls show deadlines in event timezone

### Poll Details Tests:
- [ ] Poll creation time shows correctly (relative time for recent, date for old)
- [ ] Deadline displays show correct timezone for dates
- [ ] "Last updated" shows correct relative time
- [ ] Phase deadlines display properly (e.g., "in 2 days" or specific date)

**Test URLs**: 
- Create poll from event management page
- View existing polls on event page

---

## 6. Admin Orders Page (`/events/:slug/orders`)
**File**: `admin_order_live.ex`

### Test Cases:
- [ ] Order timestamps display in event timezone
- [ ] Format should be: "MM/DD/YYYY at HH:MM AM/PM TZ"
- [ ] All orders show consistent timezone (not UTC)

**Test URL**: `/events/[slug]/orders` (admin only)

---

## 7. Ticketing & Checkout
**File**: `ticketing.ex`

### Test Cases:
- [ ] Stripe checkout description shows event date in correct timezone
- [ ] Email confirmations show event date/time in event timezone
- [ ] Ticket sale period displays correctly on event page

**Test Flow**:
1. Go to event with tickets
2. Start checkout process
3. Check Stripe checkout page for event date
4. Complete purchase and check confirmation email

---

## 8. Event Components (Ticket Display)
**File**: `event_components.ex`

### Test Cases:
- [ ] Ticket sale start times display with timezone abbreviation
- [ ] Format: "MM/DD HH:MM AM/PM TZ"
- [ ] Ticket list shows correct timezone for all time-based restrictions

**Test Location**: Any event page with tickets that have sale start/end times

---

## 9. Event Cards (Dashboard/Listings)
**File**: `event_card.ex`

### Test Cases:
- [ ] Event time displays correctly on dashboard
- [ ] Event time displays correctly in group event lists
- [ ] Time format is consistent and includes correct timezone

**Test URLs**:
- `/dashboard` - User dashboard
- `/groups/[group-slug]` - Group pages with events

---

## 10. Edge Cases to Test

### DST Transitions:
- [ ] Create event during DST, view after DST ends (or vice versa)
- [ ] Create event for a date during different DST period

### Timezone Changes:
- [ ] Create event in one timezone, edit to change timezone, verify display
- [ ] Create ticket in one timezone, change event timezone, verify ticket times

### International Testing:
- [ ] Test with various international timezones (Europe/London, Asia/Tokyo, Australia/Sydney)
- [ ] Verify timezone abbreviations display correctly for each region

### Invalid Input:
- [ ] Enter invalid date/time in forms - should show validation error
- [ ] Leave date or time fields empty - should show appropriate error

---

## Testing Procedure

1. **Create Test Events**:
   - Event 1: New York timezone (EST/EDT)
   - Event 2: London timezone (GMT/BST)  
   - Event 3: Tokyo timezone (JST)
   - Event 4: Your local timezone

2. **For Each Event**:
   - Set start date/time to 5:00 PM in that timezone
   - Add at least one ticket with sale start/end times
   - Create a poll with deadlines
   - Add some activities with specific times

3. **Verify Display**:
   - Each event should show 5:00 PM in its own timezone
   - Not converted to your browser's local time
   - Not showing UTC time

4. **Cross-Browser Testing**:
   - Test in Chrome, Firefox, Safari if possible
   - Test on mobile devices

---

## Expected Results

✅ **Correct**: Event in New York at "5:00 PM EST" displays as "5:00 PM EST"
❌ **Wrong**: Event in New York at "5:00 PM EST" displays as "10:00 PM UTC" or "2:00 PM PST"

✅ **Correct**: Validation error when invalid date/time entered
❌ **Wrong**: System silently uses current time when invalid input provided

✅ **Correct**: All times on a page use the same timezone (the event's timezone)
❌ **Wrong**: Mixed timezones on the same page

---

## Notes for Testing

- Use browser DevTools to check network requests and ensure dates are being sent correctly
- Check browser console for any JavaScript errors related to datetime handling
- If you have access to the database, verify times are stored in UTC
- Test both as an admin/organizer and as a regular attendee where applicable

## Rollback Plan

If critical issues are found:
1. The changes are contained in specific files listed above
2. Git history shows all modifications
3. Can selectively revert problem areas while keeping improvements