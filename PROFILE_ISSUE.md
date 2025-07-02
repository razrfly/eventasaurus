# User Profile Pages Enhancement

## Summary
Implement comprehensive user profile pages similar to Luma's profile system, including public profile pages, enhanced settings, social links, and username/slug system.

## Current State Analysis
- **Framework**: Phoenix LiveView (Elixir) with PostgreSQL/Ecto
- **Authentication**: Supabase with local user sync
- **Current User Model**: Basic fields (id, email, name, supabase_id, timestamps)
- **Existing Settings**: Account tab (name/email/password) and Payments tab (Stripe Connect)
- **Avatar System**: DiceBear API integration

## Required Features

### 1. Database Schema Extensions
**New User Model Fields:**
```elixir
# Add to existing users table
add :username, :string, null: true                    # Unique username for profile URLs
add :bio, :text, null: true                          # Short bio/description
add :default_currency, :string, default: "USD"       # Default currency preference
add :instagram_handle, :string, null: true           # Social media handles
add :twitter_handle, :string, null: true
add :youtube_handle, :string, null: true
add :tiktok_handle, :string, null: true
add :linkedin_handle, :string, null: true
add :website_url, :string, null: true                # Personal website
add :profile_public, :boolean, default: true         # Profile visibility
add :timezone, :string, null: true                   # User timezone
```

**Database Considerations:**
- Add unique index on `username` field
- Add validation for social media handle formats
- Consider URL validation for website_url
- Add migration for existing users with null values

### 2. Public Profile Pages
**New Routes:**
- `GET /user/:username` - Public profile page
- `GET /u/:username` - Short URL alternative
- `GET /@:username` - Social media style URL

**Profile Page Features:**
- Display name, username, bio, avatar
- Join date, event statistics (hosted/attended)
- Social media links (only show if provided)
- List of public events hosted by user
- Responsive design matching existing app aesthetics

### 3. Enhanced Settings Page
**New Settings Sections:**

**Account Tab Additions:**
- Username field with availability checker
- Bio textarea (character limit ~160)
- Timezone selector
- Profile visibility toggle

**New "Profile" Tab:**
- Social media handle inputs with validation
- Website URL input with validation
- Default currency selector
- Profile preview component

**New "Privacy" Tab (Future Enhancement):**
- Profile visibility settings
- Event privacy defaults
- Communication preferences

### 4. Username/Slug System
**Requirements:**
- Unique username validation
- Auto-suggest available usernames
- Real-time availability checking
- Username format validation (alphanumeric, underscores, hyphens)
- Reserved username protection (admin, api, www, etc.)
- Migration path for existing users

**Implementation Strategy:**
```elixir
# Username validation changeset
def changeset(user, attrs) do
  user
  |> cast(attrs, [:username, :bio, :default_currency, ...])
  |> validate_username()
  |> unique_constraint(:username)
end

defp validate_username(changeset) do
  changeset
  |> validate_format(:username, ~r/^[a-zA-Z0-9_-]+$/)
  |> validate_length(:username, min: 3, max: 30)
  |> validate_exclusion(:username, reserved_usernames())
end
```

### 5. Social Links Storage Strategy

**Recommended Approach: Individual Columns**
- Simpler queries and validation
- Better indexing for search features
- Easier form handling in LiveView
- More straightforward data migration

**Alternative: JSON Field**
```elixir
add :social_links, :map, default: %{}
```

**Pros of Individual Columns:**
- Type safety and validation per platform
- Database-level constraints
- Easier to query/filter users by platform
- Better performance for common operations

### 6. Technical Implementation Tasks

**Backend (Elixir/Phoenix):**
- [ ] Create database migration for new user fields
- [ ] Update User schema and changeset validations
- [ ] Add username availability checker (LiveView)
- [ ] Create ProfileController for public pages
- [ ] Extend SettingsController for new fields
- [ ] Add social media handle validation functions
- [ ] Implement profile slug resolver
- [ ] Add timezone support utilities

**Frontend (LiveView/Tailwind):**
- [ ] Design public profile page layout
- [ ] Create profile settings form components
- [ ] Add username availability indicator
- [ ] Implement social media link components
- [ ] Add currency selector component
- [ ] Create profile preview component
- [ ] Ensure mobile responsiveness

**Testing:**
- [ ] Unit tests for username validation
- [ ] Integration tests for profile pages
- [ ] Social media handle validation tests
- [ ] Profile privacy setting tests

### 7. Default Currency Integration
**Use Cases:**
- Default currency for new events
- Display preferences for event pricing
- Stripe Connect account currency matching

**Implementation:**
- Dropdown with major currencies (USD, EUR, GBP, CAD, AUD, etc.)
- Store as 3-letter currency codes
- Integrate with existing Stripe Connect setup

### 8. Migration Strategy for Existing Users
**Considerations:**
- Generate default usernames for existing users
- Provide username selection flow for active users
- Handle username conflicts gracefully
- Maintain backward compatibility during transition

**Migration Steps:**
1. Add new columns with null values
2. Generate suggested usernames for existing users
3. Prompt users to set username on next login
4. Implement profile completion prompts

### 9. SEO and Performance Considerations
- Add meta tags for profile pages
- Implement caching for public profiles
- Optimize database queries for profile statistics
- Add structured data for profile pages

### 10. Future Enhancements
- Profile picture upload (beyond DiceBear)
- Custom profile themes/colors
- Profile analytics for hosts
- Social media integration (auto-sync)
- Profile verification badges
- Custom domain support for profiles

## Acceptance Criteria
- [ ] User can set unique username and access profile via /user/:username
- [ ] User can add social media handles in settings
- [ ] User can set default currency preference
- [ ] Public profile page displays user info and events
- [ ] Username availability is checked in real-time
- [ ] Social media links are validated and properly formatted
- [ ] Profile pages are mobile responsive
- [ ] Existing users can set usernames without losing data
- [ ] SEO meta tags are properly implemented

## Priority Level: High
This feature significantly enhances user engagement and provides professional event host profiles similar to established platforms.

## Estimated Effort: 2-3 weeks
- Week 1: Database schema, backend logic, username system
- Week 2: Frontend components, settings enhancements
- Week 3: Public profile pages, testing, polish

## Dependencies
- Existing Supabase authentication system
- Current settings page implementation
- Stripe Connect integration (for currency defaults)