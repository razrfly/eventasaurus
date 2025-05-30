defmodule EventasaurusApp.Factory do
  @moduledoc """
  Factory for generating test data using ExMachina.

  This module provides factories for all major schemas in the application
  to support robust integration testing.
  """

  use ExMachina.Ecto, repo: EventasaurusApp.Repo

  alias EventasaurusApp.Events.{Event, EventUser, EventParticipant}
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Accounts.User

  @doc """
  Factory for User schema
  """
  def user_factory do
    %User{
      name: sequence(:name, &"Test User #{&1}"),
      email: sequence(:email, &"test#{&1}@example.com"),
      supabase_id: sequence(:supabase_id, &"supabase_user_#{&1}")
    }
  end

  @doc """
  Factory for Venue schema
  """
  def venue_factory do
    %Venue{
      name: sequence(:venue_name, &"Test Venue #{&1}"),
      address: sequence(:address, &"#{&1} Test Street"),
      city: "Test City",
      state: "CA",
      country: "USA",
      latitude: 37.7749,
      longitude: -122.4194
    }
  end

  @doc """
  Factory for Event schema
  """
  def event_factory do
    %Event{
      title: sequence(:title, &"Test Event #{&1}"),
      tagline: "An awesome test event",
      description: "This is a comprehensive test event with all the details.",
      start_at: DateTime.utc_now() |> DateTime.add(7, :day),
      ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
      timezone: "America/Los_Angeles",
      visibility: :public,
      slug: sequence(:slug, &"test-event-#{&1}"),
      theme: :minimal,
      theme_customizations: %{},
      venue: build(:venue)
    }
  end

  @doc """
  Factory for EventUser (organizer relationship)
  """
  def event_user_factory do
    %EventUser{
      role: "organizer",
      event: build(:event),
      user: build(:user)
    }
  end

  @doc """
  Factory for EventParticipant (attendee relationship)
  """
  def event_participant_factory do
    %EventParticipant{
      role: :ticket_holder,
      status: :accepted,
      source: "direct_registration",
      metadata: %{},
      event: build(:event),
      user: build(:user)
    }
  end

  # Trait factories for common variations

  @doc """
  Creates an event that has already happened (past event)
  """
  def past_event_factory do
    build(:event, %{
      start_at: DateTime.utc_now() |> DateTime.add(-7, :day),
      ends_at: DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.add(2, :hour)
    })
  end

  @doc """
  Creates a private event
  """
  def private_event_factory do
    build(:event, %{
      visibility: :private
    })
  end

  @doc """
  Creates an event with no venue
  """
  def online_event_factory do
    build(:event, %{
      venue: nil,
      venue_id: nil
    })
  end

  @doc """
  Creates an event with specific theme
  """
  def themed_event_factory do
    build(:event, %{
      theme: :cosmic,
      theme_customizations: %{
        "colors" => %{
          "primary" => "#6366f1",
          "secondary" => "#8b5cf6"
        }
      }
    })
  end

  # Helper functions for building complete scenarios

  @doc """
  Creates an event with organizers
  """
  def event_with_organizers_factory do
    event = build(:event)
    organizer1 = build(:user)
    organizer2 = build(:user)

    %{event | users: [organizer1, organizer2]}
  end

  @doc """
  Creates an event with participants
  """
  def event_with_participants_factory do
    event = build(:event)
    participants = build_list(3, :user)

    %{event | users: participants}
  end

  @doc """
  Creates a complete event scenario with venue, organizers, and participants
  """
  def complete_event_factory do
    venue = build(:venue)
    event = build(:event, %{venue: venue})
    organizer = build(:user)
    participants = build_list(5, :user)

    %{event | users: [organizer | participants]}
  end
end
