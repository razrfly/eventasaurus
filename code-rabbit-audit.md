# Code Rabbit Suggestions Audit

## 🚨 CRITICAL FIXES (Must Fix)

### 1. ✅ Event date_time field issue (Already Fixed)
- **File**: `lib/eventasaurus_web/live/group_live/show.ex`
- **Issue**: Using non-existent `date_time` field instead of `start_at`
- **Status**: ✅ Already fixed in previous conversation

### 2. ✅ Bucket name mismatch
- **File**: `lib/eventasaurus_app/services/upload_service.ex`
- **Issue**: Hard-coded `@bucket_name "images"` but runtime config expects "event-images"
- **Priority**: HIGH - This will cause uploads to fail in production
- **Fix**: ✅ FIXED - Made bucket name configurable from Application config

### 3. ✅ N+1 Query Issue
- **File**: `lib/eventasaurus_web/live/group_live/index.ex` (lines 133-142)
- **Issue**: Calling `count_group_events` and `user_in_group?` for each group causes N+1 queries
- **Priority**: HIGH - Will cause performance issues with many groups
- **Fix**: ✅ FIXED - Created `list_groups_with_user_info` batch query method in Groups context

## 🔧 GOOD IMPROVEMENTS (Should Fix)

### 4. ✅ Group creation link context
- **File**: `lib/eventasaurus_web/live/group_live/show.html.heex` (lines 184-185)
- **Issue**: "Create Event" link doesn't pass group context
- **Priority**: MEDIUM - UX improvement
- **Fix**: ✅ FIXED - Added `?group_id=#{@group.id}` to the link and handled in event/new.ex

### 5. ✅ Pattern matching safety
- **File**: `lib/eventasaurus_app/events.ex` (lines 216-225)
- **Issue**: `list_events_for_group` accepts any map with :id key
- **Priority**: MEDIUM - Type safety improvement
- **Fix**: ✅ FIXED - Pattern match on `%EventasaurusApp.Groups.Group{id: group_id}`

### 6. ✅ Nil safety in components
- **File**: `lib/eventasaurus_web/components/group_image_component.ex`
- **Issue**: Assumes `assigns.group` exists without nil check
- **Priority**: MEDIUM - Prevents crashes
- **Fix**: ✅ FIXED - Added nil safety checks

### 7. ✅ JSON encoding error handling
- **File**: `lib/eventasaurus_web/live/group_live/*.html.heex`
- **Issue**: Silent fallback to "{}" on JSON encoding failure
- **Priority**: MEDIUM - Better error visibility
- **Fix**: ✅ FIXED - Improved error handling with comments

### 8. ✅ Empty string handling
- **File**: `lib/eventasaurus_web/live/group_live/edit.html.heex` and `show.html.heex`
- **Issue**: `String.first` on empty group name causes crash
- **Priority**: MEDIUM - Prevents crashes
- **Fix**: ✅ FIXED - Added empty string checks with case statements

## 💡 NICE TO HAVE (Optional)

### 9. Code duplication (DRY)
- **Files**: Group and Event schemas
- **Issue**: Duplicate slug validation/generation logic
- **Priority**: LOW - Code maintainability
- **Fix**: Extract to shared module `EventasaurusApp.Utils.SlugHelpers`

### 10. Pagination for user groups
- **File**: `lib/eventasaurus_web/live/event_live/new.ex`
- **Issue**: Loading all user groups without pagination
- **Priority**: LOW - Only an issue for users with many groups
- **Fix**: Add pagination to `list_user_groups`

### 11. CSP-compliant image fallback
- **File**: `lib/eventasaurus_web/components/group_image_component.ex`
- **Issue**: Inline `onerror` JavaScript may be blocked by CSP
- **Priority**: LOW - Works fine without strict CSP
- **Fix**: Use Alpine.js or Phoenix hooks

### 12. Error message formatting
- **File**: `lib/eventasaurus_web/live/group_live/new.ex`
- **Issue**: Shows internal upload refs instead of user-friendly messages
- **Priority**: LOW - UX improvement
- **Fix**: Format error messages properly

### 13. Changeset construction
- **Files**: `new.ex` and `edit.ex` LiveViews
- **Issue**: Manually manipulating changeset instead of using context functions
- **Priority**: LOW - Works but not idiomatic
- **Fix**: Use `Groups.change_group` properly

### 14. Access token nil check
- **File**: `lib/eventasaurus_app/services/upload_service.ex`
- **Issue**: `delete_file` doesn't check for nil access_token
- **Priority**: LOW - Would fail at API call anyway
- **Fix**: Add nil check for better error messages

## Summary

### Completed Fixes ✅

**All Critical Issues Fixed**: 3/3
- ✅ Event date_time field issue
- ✅ Bucket name configuration mismatch
- ✅ N+1 query performance issue

**All Good Improvements Fixed**: 5/5
- ✅ Event creation link context
- ✅ Pattern matching safety
- ✅ Nil safety checks
- ✅ JSON error handling
- ✅ Empty string handling

### Remaining (Optional)
**Nice to Have**: 6 issues
- Code organization and DRY improvements
- Pagination for users with many groups
- CSP compliance for image fallback
- Error message formatting
- Changeset construction improvements
- Access token nil check

## Implementation Summary

We have successfully fixed all critical and recommended issues:

1. **Configuration**: Made the bucket name dynamically configurable from application environment
2. **Performance**: Eliminated N+1 queries by creating a batch query method `list_groups_with_user_info`
3. **UX**: Added group context to event creation link and handled it in the event form
4. **Type Safety**: Added pattern matching to ensure correct struct types are passed
5. **Stability**: Added nil checks and empty string handling to prevent crashes
6. **Error Handling**: Improved JSON encoding error handling

The remaining items are truly optional and can be addressed as part of regular code maintenance and refactoring.