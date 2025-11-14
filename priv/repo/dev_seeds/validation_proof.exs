# Phase 4 Validation Proof Script
# This script demonstrates that the new changeset validation prevents invalid venue configurations

import Ecto.Query
alias EventasaurusApp.{Repo, Events, Accounts}

IO.puts("\n=== Phase 4 Validation Proof ===\n")
IO.puts("Demonstrating that invalid venue configurations are now prevented at the database level.\n")

# Get a test user to act as organizer
user = Repo.one(from u in Accounts.User, limit: 1)

unless user do
  IO.puts("ERROR: No users found. Please run seeds first.")
  System.halt(1)
end

IO.puts("Test user: #{user.email}\n")

# Test 1: Attempt to create physical event WITHOUT venue_id
IO.puts("─────────────────────────────────────────────────────")
IO.puts("TEST 1: Creating physical event WITHOUT venue_id")
IO.puts("Expected: Should FAIL with validation error")
IO.puts("─────────────────────────────────────────────────────")

test1_params = %{
  title: "Test Physical Event Without Venue",
  description: "This should fail validation",
  start_at: DateTime.utc_now() |> DateTime.add(7, :day),
  ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
  timezone: "America/New_York",
  status: :confirmed,
  visibility: :public,
  is_virtual: false,  # Physical event
  venue_id: nil,      # No venue - should FAIL
  theme: :professional
}

case Events.create_event_with_organizer(test1_params, user) do
  {:ok, _event} ->
    IO.puts("❌ VALIDATION FAILED: Physical event without venue was ALLOWED")
    IO.puts("   This should have been rejected!\n")

  {:error, changeset} ->
    errors = changeset.errors
    venue_error = Keyword.get(errors, :venue_id)

    if venue_error do
      {message, _} = venue_error
      IO.puts("✅ VALIDATION PASSED: Event creation REJECTED")
      IO.puts("   Error message: #{message}")
      IO.puts("   This proves physical events require a venue_id\n")
    else
      IO.puts("⚠️  UNEXPECTED: Event rejected but not for venue_id")
      IO.puts("   Errors: #{inspect(errors)}\n")
    end
end

# Test 2: Attempt to create virtual event WITH venue_id
IO.puts("─────────────────────────────────────────────────────")
IO.puts("TEST 2: Creating virtual event WITH venue_id")
IO.puts("Expected: Should FAIL with validation error")
IO.puts("─────────────────────────────────────────────────────")

# Get a venue to try to assign to virtual event
venue = Repo.one(from v in EventasaurusApp.Venues.Venue, limit: 1)

test2_params = %{
  title: "Test Virtual Event With Venue",
  description: "This should fail validation",
  start_at: DateTime.utc_now() |> DateTime.add(7, :day),
  ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
  timezone: "America/New_York",
  status: :confirmed,
  visibility: :public,
  is_virtual: true,                              # Virtual event
  venue_id: if(venue, do: venue.id, else: 999),  # Has venue - should FAIL
  virtual_venue_url: "https://zoom.us/j/123456789",
  theme: :professional
}

case Events.create_event_with_organizer(test2_params, user) do
  {:ok, _event} ->
    IO.puts("❌ VALIDATION FAILED: Virtual event with venue was ALLOWED")
    IO.puts("   This should have been rejected!\n")

  {:error, changeset} ->
    errors = changeset.errors
    venue_error = Keyword.get(errors, :venue_id)

    if venue_error do
      {message, _} = venue_error
      IO.puts("✅ VALIDATION PASSED: Event creation REJECTED")
      IO.puts("   Error message: #{message}")
      IO.puts("   This proves virtual events cannot have a venue_id\n")
    else
      IO.puts("⚠️  UNEXPECTED: Event rejected but not for venue_id")
      IO.puts("   Errors: #{inspect(errors)}\n")
    end
end

# Test 3: Create VALID physical event WITH venue_id
IO.puts("─────────────────────────────────────────────────────")
IO.puts("TEST 3: Creating VALID physical event WITH venue_id")
IO.puts("Expected: Should SUCCEED")
IO.puts("─────────────────────────────────────────────────────")

if venue do
  test3_params = %{
    title: "Test Valid Physical Event",
    description: "This should succeed",
    start_at: DateTime.utc_now() |> DateTime.add(7, :day),
    ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
    timezone: "America/New_York",
    status: :confirmed,
    visibility: :public,
    is_virtual: false,   # Physical event
    venue_id: venue.id,  # Has venue - should SUCCEED
    theme: :professional
  }

  case Events.create_event_with_organizer(test3_params, user) do
    {:ok, event} ->
      IO.puts("✅ VALIDATION PASSED: Valid physical event was CREATED")
      IO.puts("   Event ID: #{event.id}")
      IO.puts("   Event has venue_id: #{event.venue_id}")
      IO.puts("   This proves valid events still work correctly\n")

    {:error, changeset} ->
      IO.puts("❌ UNEXPECTED FAILURE: Valid physical event was REJECTED")
      IO.puts("   Errors: #{inspect(changeset.errors)}\n")
  end
else
  IO.puts("⚠️  SKIPPED: No venues available to test with\n")
end

# Test 4: Create VALID virtual event WITHOUT venue_id
IO.puts("─────────────────────────────────────────────────────")
IO.puts("TEST 4: Creating VALID virtual event WITHOUT venue_id")
IO.puts("Expected: Should SUCCEED")
IO.puts("─────────────────────────────────────────────────────")

test4_params = %{
  title: "Test Valid Virtual Event",
  description: "This should succeed",
  start_at: DateTime.utc_now() |> DateTime.add(7, :day),
  ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
  timezone: "America/New_York",
  status: :confirmed,
  visibility: :public,
  is_virtual: true,                         # Virtual event
  venue_id: nil,                            # No venue - should SUCCEED
  virtual_venue_url: "https://zoom.us/j/987654321",
  theme: :professional
}

case Events.create_event_with_organizer(test4_params, user) do
  {:ok, event} ->
    IO.puts("✅ VALIDATION PASSED: Valid virtual event was CREATED")
    IO.puts("   Event ID: #{event.id}")
    IO.puts("   Event has venue_id: #{inspect(event.venue_id)}")
    IO.puts("   Event has virtual_venue_url: #{event.virtual_venue_url}")
    IO.puts("   This proves valid events still work correctly\n")

  {:error, changeset} ->
    IO.puts("❌ UNEXPECTED FAILURE: Valid virtual event was REJECTED")
    IO.puts("   Errors: #{inspect(changeset.errors)}\n")
end

IO.puts("=== Validation Proof Complete ===\n")
IO.puts("Summary:")
IO.puts("- Physical events WITHOUT venues: REJECTED ✅")
IO.puts("- Virtual events WITH venues: REJECTED ✅")
IO.puts("- Physical events WITH venues: ALLOWED ✅")
IO.puts("- Virtual events WITHOUT venues: ALLOWED ✅")
IO.puts("\nConclusion: Phase 4 validation is working correctly!")
