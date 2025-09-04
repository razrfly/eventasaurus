# Test Matrix: Dropdown Combinations for Event Creation

This document maps all 60 possible combinations of the three dropdown questions and their expected outcomes.

## Dropdown Options

### 1. Date Certainty (3 options)
- `confirmed` → status: :confirmed
- `polling` → status: :polling  
- `planning` → status: :draft

### 2. Venue Certainty (4 options)
- `confirmed` → Standard venue selection
- `virtual` → is_virtual: true, venue_id: nil
- `polling` → Creates venue poll, may set status: :polling
- `tbd` → venue_id: nil, is_virtual: false

### 3. Participation Type (5 options)
- `free` → is_ticketed: false, taxation_type: "ticketless"
- `ticketed` → is_ticketed: true, taxation_type: "ticketed_event"
- `contribution` → is_ticketed: false, taxation_type: "contribution_collection"
- `crowdfunding` → status: :threshold, is_ticketed: true, threshold_type: "revenue"
- `interest` → status: :threshold, threshold_type: "attendee_count"

## Status Resolution Priority

Per `resolve_status_conflicts/1`: **threshold > polling > draft > confirmed**

## Complete Test Matrix (60 combinations)

| # | Date | Venue | Participation | Final Status | Key Attributes | Notes |
|---|------|-------|---------------|--------------|----------------|-------|
| 1 | confirmed | confirmed | free | :confirmed | is_ticketed: false, taxation_type: "ticketless", is_virtual: false | ✅ Standard free event |
| 2 | confirmed | confirmed | ticketed | :confirmed | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false | ✅ Standard ticketed event |
| 3 | confirmed | confirmed | contribution | :confirmed | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false | ✅ Standard contribution event |
| 4 | confirmed | confirmed | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue" | ✅ Threshold overrides confirmed |
| 5 | confirmed | confirmed | interest | :threshold | threshold_type: "attendee_count", is_virtual: false | ✅ Threshold overrides confirmed |
| 6 | confirmed | virtual | free | :confirmed | is_ticketed: false, taxation_type: "ticketless", is_virtual: true, venue_id: nil | ✅ Virtual free event |
| 7 | confirmed | virtual | ticketed | :confirmed | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: true, venue_id: nil | ✅ Virtual ticketed event |
| 8 | confirmed | virtual | contribution | :confirmed | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: true, venue_id: nil | ✅ Virtual contribution event |
| 9 | confirmed | virtual | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue", is_virtual: true | ✅ Virtual crowdfunding |
| 10 | confirmed | virtual | interest | :threshold | threshold_type: "attendee_count", is_virtual: true, venue_id: nil | ✅ Virtual interest validation |
| 11 | confirmed | polling | free | :polling | is_ticketed: false, taxation_type: "ticketless", is_virtual: false | ✅ Venue polling overrides confirmed date |
| 12 | confirmed | polling | ticketed | :polling | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false | ✅ Venue polling overrides confirmed date |
| 13 | confirmed | polling | contribution | :polling | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false | ✅ Venue polling overrides confirmed date |
| 14 | confirmed | polling | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue" | ✅ Threshold overrides polling |
| 15 | confirmed | polling | interest | :threshold | threshold_type: "attendee_count", is_virtual: false | ✅ Threshold overrides polling |
| 16 | confirmed | tbd | free | :confirmed | is_ticketed: false, taxation_type: "ticketless", is_virtual: false, venue_id: nil | ✅ TBD venue, confirmed date |
| 17 | confirmed | tbd | ticketed | :confirmed | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false, venue_id: nil | ✅ TBD venue, confirmed date |
| 18 | confirmed | tbd | contribution | :confirmed | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false, venue_id: nil | ✅ TBD venue, confirmed date |
| 19 | confirmed | tbd | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue", venue_id: nil | ✅ TBD venue, threshold from crowdfunding |
| 20 | confirmed | tbd | interest | :threshold | threshold_type: "attendee_count", is_virtual: false, venue_id: nil | ✅ TBD venue, threshold from interest |
| 21 | polling | confirmed | free | :polling | is_ticketed: false, taxation_type: "ticketless", is_virtual: false | ✅ Date polling event |
| 22 | polling | confirmed | ticketed | :polling | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false | ✅ Date polling ticketed |
| 23 | polling | confirmed | contribution | :polling | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false | ✅ Date polling contribution |
| 24 | polling | confirmed | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue" | ✅ Threshold overrides polling |
| 25 | polling | confirmed | interest | :threshold | threshold_type: "attendee_count", is_virtual: false | ✅ Threshold overrides polling |
| 26 | polling | virtual | free | :polling | is_ticketed: false, taxation_type: "ticketless", is_virtual: true, venue_id: nil | ✅ Virtual date polling |
| 27 | polling | virtual | ticketed | :polling | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: true, venue_id: nil | ✅ Virtual date polling ticketed |
| 28 | polling | virtual | contribution | :polling | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: true, venue_id: nil | ✅ Virtual date polling contribution |
| 29 | polling | virtual | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue", is_virtual: true | ✅ Virtual threshold crowdfunding |
| 30 | polling | virtual | interest | :threshold | threshold_type: "attendee_count", is_virtual: true, venue_id: nil | ✅ Virtual threshold interest |
| 31 | polling | polling | free | :polling | is_ticketed: false, taxation_type: "ticketless", is_virtual: false | ⚠️ **EDGE CASE**: Both date and venue polling |
| 32 | polling | polling | ticketed | :polling | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false | ⚠️ **EDGE CASE**: Both date and venue polling |
| 33 | polling | polling | contribution | :polling | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false | ⚠️ **EDGE CASE**: Both date and venue polling |
| 34 | polling | polling | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue" | ✅ Threshold overrides double polling |
| 35 | polling | polling | interest | :threshold | threshold_type: "attendee_count", is_virtual: false | ✅ Threshold overrides double polling |
| 36 | polling | tbd | free | :polling | is_ticketed: false, taxation_type: "ticketless", is_virtual: false, venue_id: nil | ✅ Date polling with TBD venue |
| 37 | polling | tbd | ticketed | :polling | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false, venue_id: nil | ✅ Date polling with TBD venue |
| 38 | polling | tbd | contribution | :polling | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false, venue_id: nil | ✅ Date polling with TBD venue |
| 39 | polling | tbd | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue", venue_id: nil | ✅ Threshold with TBD venue |
| 40 | polling | tbd | interest | :threshold | threshold_type: "attendee_count", is_virtual: false, venue_id: nil | ✅ Threshold with TBD venue |
| 41 | planning | confirmed | free | :draft | is_ticketed: false, taxation_type: "ticketless", is_virtual: false | ✅ Draft free event |
| 42 | planning | confirmed | ticketed | :draft | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false | ✅ Draft ticketed event |
| 43 | planning | confirmed | contribution | :draft | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false | ✅ Draft contribution event |
| 44 | planning | confirmed | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue" | ✅ Threshold overrides draft |
| 45 | planning | confirmed | interest | :threshold | threshold_type: "attendee_count", is_virtual: false | ✅ Threshold overrides draft |
| 46 | planning | virtual | free | :draft | is_ticketed: false, taxation_type: "ticketless", is_virtual: true, venue_id: nil | ✅ Virtual draft event |
| 47 | planning | virtual | ticketed | :draft | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: true, venue_id: nil | ✅ Virtual draft ticketed |
| 48 | planning | virtual | contribution | :draft | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: true, venue_id: nil | ✅ Virtual draft contribution |
| 49 | planning | virtual | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue", is_virtual: true | ✅ Virtual threshold crowdfunding |
| 50 | planning | virtual | interest | :threshold | threshold_type: "attendee_count", is_virtual: true, venue_id: nil | ✅ Virtual threshold interest |
| 51 | planning | polling | free | :polling | is_ticketed: false, taxation_type: "ticketless", is_virtual: false | ✅ Polling overrides draft |
| 52 | planning | polling | ticketed | :polling | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false | ✅ Polling overrides draft |
| 53 | planning | polling | contribution | :polling | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false | ✅ Polling overrides draft |
| 54 | planning | polling | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue" | ✅ Threshold overrides polling and draft |
| 55 | planning | polling | interest | :threshold | threshold_type: "attendee_count", is_virtual: false | ✅ Threshold overrides polling and draft |
| 56 | planning | tbd | free | :draft | is_ticketed: false, taxation_type: "ticketless", is_virtual: false, venue_id: nil | ✅ Draft with TBD venue |
| 57 | planning | tbd | ticketed | :draft | is_ticketed: true, taxation_type: "ticketed_event", is_virtual: false, venue_id: nil | ✅ Draft with TBD venue |
| 58 | planning | tbd | contribution | :draft | is_ticketed: false, taxation_type: "contribution_collection", is_virtual: false, venue_id: nil | ✅ Draft with TBD venue |
| 59 | planning | tbd | crowdfunding | :threshold | is_ticketed: true, taxation_type: "ticketed_event", threshold_type: "revenue", venue_id: nil | ✅ Threshold with TBD venue |
| 60 | planning | tbd | interest | :threshold | threshold_type: "attendee_count", is_virtual: false, venue_id: nil | ✅ Threshold with TBD venue |

## High-Risk Combinations Requiring Special Attention

### 🔴 Critical Edge Cases
1. **Rows 31-33**: Both date and venue polling - Need to ensure proper deadline handling
2. **Rows 14, 15, 24, 25**: Threshold overriding polling - Verify polling fields are cleared
3. **Rows 9, 10, 29, 30**: Virtual threshold events - Verify venue validation logic

### 🟡 Medium Risk
4. **All crowdfunding combinations**: Revenue threshold validation with various statuses
5. **All virtual combinations**: Venue validation with is_virtual flag
6. **All polling combinations**: Deadline requirements and UI field visibility

### ⚪ Low Risk
7. **Standard confirmed combinations**: Basic happy path scenarios
8. **Draft combinations**: Simple planning scenarios

## Field Requirements by Status

### :confirmed Status (requires start_at)
- Rows: 1-3, 6-8, 16-18

### :polling Status (requires polling_deadline) 
- Rows: 11-13, 21-23, 26-28, 31-33, 36-38, 51-53

### :threshold Status (requires threshold_count OR threshold_revenue_cents)
- **Revenue thresholds**: Rows 4, 9, 14, 19, 24, 29, 34, 39, 44, 49, 54, 59
- **Attendee thresholds**: Rows 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60

### :draft Status (no additional requirements)
- Rows: 41-43, 46-48, 56-58

## Validation Scenarios to Test

### ✅ Valid Combinations (should pass)
- All 60 combinations should create valid events when proper additional fields are provided
- Revenue thresholds with ticketed events (crowdfunding)
- Attendee thresholds with any taxation type (interest validation)
- Virtual events without venue_id

### ❌ Invalid Combinations (should fail validation)
- Free events (ticketless) with revenue thresholds 
- Virtual events with venue_id set
- Polling events without polling_deadline
- Threshold events without count or revenue values

## Test Implementation Strategy

1. **Property-based testing**: Generate all 60 combinations automatically
2. **Explicit edge case tests**: Focus on high-risk combinations
3. **Validation integration**: Test with actual Event changeset validations
4. **UI integration**: Test dropdown behavior and field visibility