defmodule EventasaurusApp.Factory do
  @moduledoc """
  Factory for generating test data using ExMachina.

  This module provides factories for all major schemas in the application
  to support robust integration testing.
  """

  use ExMachina.Ecto, repo: EventasaurusApp.Repo

  alias EventasaurusApp.Events.{Event, EventUser, EventParticipant, Ticket, Order}
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
      status: :confirmed,
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

  @doc """
  Creates an event in polling state for date collection
  """
  def polling_event_factory do
    build(:event, %{
      status: :polling,
      polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day)
    })
  end

  @doc """
  Factory for EventDatePoll schema
  """
  def event_date_poll_factory do
    %EventasaurusApp.Events.EventDatePoll{
      voting_deadline: DateTime.utc_now() |> DateTime.add(7, :day),
      event: build(:event, %{status: :polling, polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day)}),
      created_by: build(:user)
    }
  end

  @doc """
  Creates a finalized event date poll
  """
  def finalized_event_date_poll_factory do
    build(:event_date_poll, %{
      finalized_date: Date.utc_today() |> Date.add(14)
    })
  end

  @doc """
  Factory for EventDateOption schema
  """
  def event_date_option_factory do
    %EventasaurusApp.Events.EventDateOption{
      date: Date.utc_today() |> Date.add(Enum.random(1..30)),
      event_date_poll: build(:event_date_poll)
    }
  end

  @doc """
  Creates a date option for today
  """
  def today_date_option_factory do
    build(:event_date_option, %{
      date: Date.utc_today()
    })
  end

  @doc """
  Creates a date option for tomorrow
  """
  def tomorrow_date_option_factory do
    build(:event_date_option, %{
      date: Date.utc_today() |> Date.add(1)
    })
  end

  @doc """
  Creates multiple date options for a range
  """
  def date_option_range_factory do
    poll = build(:event_date_poll)
    start_date = Date.utc_today() |> Date.add(1)
    end_date = Date.utc_today() |> Date.add(7)

    Date.range(start_date, end_date)
    |> Enum.map(fn date ->
      build(:event_date_option, %{
        date: date,
        event_date_poll: poll
      })
    end)
  end

  @doc """
  Factory for EventDateVote schema
  """
  def event_date_vote_factory do
    %EventasaurusApp.Events.EventDateVote{
      vote_type: :yes,
      event_date_option: build(:event_date_option),
      user: build(:user)
    }
  end

  @doc """
  Creates a vote with 'if_need_be' type
  """
  def if_need_be_vote_factory do
    build(:event_date_vote, %{
      vote_type: :if_need_be
    })
  end

  @doc """
  Creates a vote with 'no' type
  """
  def no_vote_factory do
    build(:event_date_vote, %{
      vote_type: :no
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

  @doc """
  Factory for Ticket schema
  """
  def ticket_factory do
    %Ticket{
      title: sequence(:ticket_title, &"General Admission #{&1}"),
      description: "Standard event ticket",
      price_cents: 2500,
      currency: "usd",
      quantity: 100,
      starts_at: DateTime.utc_now() |> DateTime.add(1, :day),
      ends_at: DateTime.utc_now() |> DateTime.add(30, :day),
      tippable: false,
      event: build(:event)
    }
  end

  @doc """
  Factory for Order schema
  """
  def order_factory do
    %Order{
      quantity: 1,
      subtotal_cents: 2500,
      tax_cents: 250,
      total_cents: 2750,
      currency: "usd",
      status: "pending",
      stripe_session_id: sequence(:stripe_session_id, &"cs_test_#{&1}"),
      payment_reference: nil,
      confirmed_at: nil,
      user: build(:user),
      event: build(:event),
      ticket: build(:ticket)
    }
  end

  @doc """
  Creates a low-cost ticket
  """
  def low_cost_ticket_factory do
    build(:ticket, %{
      title: "Early Bird Special",
      price_cents: 500,
      tippable: true
    })
  end

  @doc """
  Creates a VIP ticket
  """
  def vip_ticket_factory do
    build(:ticket, %{
      title: "VIP Access",
      description: "Premium access with exclusive benefits",
      price_cents: 10000,
      quantity: 20
    })
  end

  @doc """
  Creates a confirmed order
  """
  def confirmed_order_factory do
    build(:order, %{
      status: "confirmed",
      payment_reference: "pi_test_payment_intent",
      confirmed_at: DateTime.utc_now()
    })
  end

  @doc """
  Creates a refunded order
  """
  def refunded_order_factory do
    build(:order, %{
      status: "refunded",
      payment_reference: "pi_test_payment_intent",
      confirmed_at: DateTime.utc_now() |> DateTime.add(-1, :day)
    })
  end
end
