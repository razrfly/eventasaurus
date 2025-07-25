# Eventasaurus Payment Features Mockups

## Overview
This directory contains HTML mockups for the new payment features described in [GitHub Issue #678](https://github.com/razrfly/eventasaurus/issues/678).

## Viewing the Mockups
Open `mockup-showcase.html` in your browser for an organized view of all mockups with descriptions.

## Payment Type Mockups

### 1. Contribution Collection (`contribution-mockup.html`)
- Free events with optional contributions
- Progress bar showing total raised
- Recent contributors display
- Suggested donation amounts

### 2. Crowdfunding Campaign (`crowdfunding-mockup.html`)
- Kickstarter-style goal-based funding
- Reward tiers for different contribution levels
- Campaign progress and countdown
- Event only happens if funded

### 3. Donation Drive (`donation-mockup.html`)
- Simple donation interface for charitable causes
- Transparency metrics
- Tax deductible notices
- Donor honor roll

## Event Creation Flow Mockups

### Recommended: Dropdown Version (`intent-dropdown-version.html`)
- Single-page flow (no wizards)
- Intent-based selection via dropdown
- Progressive disclosure of settings
- Mobile-friendly design

### Alternative: Modal Version (`intent-modal-version.html`)
- Single-page flow with modal selection
- Visual card-based intent selection
- Separate date configuration modal
- More visual space for options

## Key Design Decisions

1. **No Wizards**: All flows are single-page as requested
2. **Intent-Based**: Users select goals ("I want to sell tickets") rather than technical options
3. **Progressive Disclosure**: Configuration options appear based on selection
4. **Mobile First**: All mockups are responsive
5. **Flexibility**: Multiple payment types can be mixed on a single event

## Integration with Existing System
- Mockups show how payment features integrate into current event pages
- Event creation flow fits within existing form structure
- Visual design matches current Eventasaurus style

## Next Steps
1. Review mockups and provide feedback
2. Choose between dropdown vs modal approach for event creation
3. Implement backend support for new payment types
4. Create API endpoints for contribution tracking
5. Build React components based on approved designs