defmodule EventasaurusApp.Factory do
  @moduledoc """
  Factory for generating test data using ExMachina and Faker.

  This module provides factories for all major schemas in the application
  to support robust integration testing and development seeding.
  """

  use ExMachina.Ecto, repo: EventasaurusApp.Repo

  alias EventasaurusApp.Events.{Event, EventUser, EventParticipant, Ticket, Order}
  alias EventasaurusApp.Events.{Poll, PollOption, PollVote, EventActivity}
  alias EventasaurusApp.Groups.{Group, GroupUser}
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Accounts.User
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias Nanoid

  @doc """
  Factory for User schema with realistic data
  """
  def user_factory do
    %User{
      name: Faker.Person.name(),
      email:
        sequence(:email, fn n ->
          "#{Faker.Internet.user_name()}#{n}@#{Faker.Internet.domain_name()}"
        end),
      # Use proper UUID instead of fake prefix
      supabase_id: Ecto.UUID.generate(),
      username: sequence(:username, fn n -> "#{Faker.Internet.user_name()}#{n}" end),
      bio: Faker.Lorem.paragraph(2),
      website_url: if(Enum.random([true, false]), do: Faker.Internet.url(), else: nil),
      profile_public: Enum.random([true, false]),
      instagram_handle: if(Enum.random([true, false]), do: Faker.Internet.user_name(), else: nil),
      x_handle: if(Enum.random([true, false]), do: Faker.Internet.user_name(), else: nil),
      timezone:
        Enum.random([
          "America/New_York",
          "America/Chicago",
          "America/Denver",
          "America/Los_Angeles",
          "Europe/London",
          "Asia/Tokyo"
        ]),
      default_currency: Enum.random(["USD", "EUR", "GBP", "CAD"])
    }
  end

  @doc """
  Factory for Venue schema
  """
  def venue_factory do
    # Create a normalized city for the venue
    city = insert(:city, %{name: "Test City"})

    %Venue{
      name: sequence(:venue_name, &"Test Venue #{&1}"),
      address: sequence(:address, &"#{&1} Test Street"),
      city_id: city.id,
      latitude: 37.7749,
      longitude: -122.4194,
      venue_type: "venue"
    }
  end

  @doc """
  Factory for Country schema
  """
  def country_factory do
    # Generate 2-character codes using letters A-Z
    # This gives us 26*26 = 676 possible combinations
    code_num = sequence(:country_code_num, & &1)
    first_letter = rem(code_num, 26) + 65  # 65 is 'A' in ASCII
    second_letter = rem(div(code_num, 26), 26) + 65
    code = <<first_letter, second_letter>>

    %Country{
      name: sequence(:country_name, &"Country #{&1}"),
      code: code,
      slug: sequence(:country_slug, &"country-#{&1}")
    }
  end

  @doc """
  Factory for City schema
  """
  def city_factory do
    %City{
      name: sequence(:city_name, &"City #{&1}"),
      slug: sequence(:city_slug, &"city-#{&1}"),
      country: build(:country)
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
      # Remove explicit slug to allow automatic generation
      status: :confirmed,
      theme: :minimal,
      theme_customizations: %{},
      # Set as free event (no ticketing) for now
      is_ticketed: false,
      taxation_type: "ticketless",
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
      event:
        build(:event, %{
          status: :polling,
          polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day)
        }),
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
      base_price_cents: 2500,
      minimum_price_cents: 2500,
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
      base_price_cents: 500,
      minimum_price_cents: 500,
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
      base_price_cents: 10000,
      minimum_price_cents: 10000,
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

  @doc """
  Factory for StripeConnectAccount schema
  """
  def stripe_connect_account_factory do
    %EventasaurusApp.Stripe.StripeConnectAccount{
      stripe_user_id: sequence(:stripe_user_id, &"acct_test_#{&1}"),
      connected_at: DateTime.utc_now(),
      user: build(:user)
    }
  end

  # ===== New Dev Seed Factories with Faker =====

  @doc """
  Factory for Group schema with realistic data
  """
  def group_factory do
    %Group{
      name: sequence(:group_name, fn n -> "#{Faker.Team.name()} #{n}" end),
      description: Faker.Lorem.paragraph(3),
      slug: sequence(:group_slug, &"group-#{&1}"),
      avatar_url: "https://picsum.photos/200/200?random=#{System.unique_integer([:positive])}",
      cover_image_url:
        "https://picsum.photos/800/400?random=#{System.unique_integer([:positive])}",
      created_by: build(:user)
    }
  end

  @doc """
  Factory for GroupUser schema
  """
  def group_user_factory do
    %GroupUser{
      user: build(:user),
      group: build(:group),
      role: Enum.random(["admin", "member"])
    }
  end

  @doc """
  Factory for Poll schema
  """
  def poll_factory do
    %Poll{
      title: sequence(:poll_title, fn n -> "#{Faker.Lorem.sentence(3)} Poll #{n}" end),
      description: Faker.Lorem.paragraph(2),
      poll_type: Enum.random(["date", "movie", "restaurant", "activity", "generic"]),
      voting_system: Enum.random(["single_choice", "multiple_choice", "ranked"]),
      phase: Enum.random(["list_building", "voting", "closed"]),
      list_building_deadline: Faker.DateTime.forward(7),
      voting_deadline: Faker.DateTime.forward(14),
      max_options_per_user: Enum.random([1, 3, 5, nil]),
      auto_finalize: Enum.random([true, false]),
      privacy_settings: %{
        "anonymous_voting" => Enum.random([true, false]),
        "show_results_during_voting" => Enum.random([true, false])
      },
      settings: %{
        "location_scope" => Enum.random(["place", "city", "region", "country"]),
        "allow_write_ins" => Enum.random([true, false])
      },
      event: build(:event),
      created_by: build(:user)
    }
  end

  @doc """
  Factory for PollOption schema
  """
  def poll_option_factory do
    %PollOption{
      title: Faker.Lorem.sentence(Enum.random(2..5)),
      description: Faker.Lorem.paragraph(Enum.random(1..3)),
      poll: build(:poll),
      suggested_by: build(:user),
      image_url: "https://picsum.photos/400/300?random=#{System.unique_integer([:positive])}",
      external_id: "ext_#{System.unique_integer([:positive])}",
      metadata: %{
        "rating" => :rand.uniform() * 5
      },
      order_index: sequence(:order_index, & &1)
    }
  end

  @doc """
  Factory for PollVote schema
  """
  def poll_vote_factory do
    poll_option = build(:poll_option)

    %PollVote{
      poll_option: poll_option,
      poll: poll_option.poll,
      voter: build(:user),
      vote_rank: Enum.random([1, 2, 3, nil]),
      voted_at: DateTime.utc_now()
    }
  end

  @doc """
  Factory for EventActivity schema
  """
  def event_activity_factory do
    %EventActivity{
      activity_type:
        Enum.random([
          "movie_watched",
          "tv_watched",
          "game_played",
          "book_read",
          "restaurant_visited",
          "place_visited",
          "activity_completed",
          "custom"
        ]),
      metadata: %{
        "title" => Faker.Lorem.sentence(Enum.random(2..5)),
        "rating" => Enum.random([1, 2, 3, 4, 5]),
        "review" => Faker.Lorem.paragraph(Enum.random(2..4)),
        "image_url" => Faker.Avatar.image_url(),
        "location" => Faker.Address.city()
      },
      occurred_at: Faker.DateTime.backward(30),
      source: Enum.random(["manual", "integration", "import"]),
      event: build(:event),
      created_by: build(:user)
    }
  end

  # Enhanced factories with real data (no Lorem ipsum!)
  def realistic_event_factory do
    themes = [:minimal, :cosmic, :velocity, :retro, :celebration, :nature, :professional]

    # Try to load curated data if available, otherwise use defaults
    {base_title, tagline, description} =
      if Code.ensure_loaded?(DevSeeds.CuratedData) do
        # Module already loaded, use it
        title = apply(DevSeeds.CuratedData, :generate_realistic_event_title, [])
        tag = apply(DevSeeds.CuratedData, :random_tagline, [])
        desc = apply(DevSeeds.CuratedData, :generate_event_description, [title])
        {title, tag, desc}
      else
        try do
          Code.require_file("priv/repo/dev_seeds/curated_data.exs")

          if Code.ensure_loaded?(DevSeeds.CuratedData) do
            title = apply(DevSeeds.CuratedData, :generate_realistic_event_title, [])
            tag = apply(DevSeeds.CuratedData, :random_tagline, [])
            desc = apply(DevSeeds.CuratedData, :generate_event_description, [title])
            {title, tag, desc}
          else
            raise "Module not loaded"
          end
        rescue
          _ ->
            # Fallback to realistic titles without Lorem ipsum
            title =
              Enum.random([
                "Movie Night: The Dark Knight",
                "Dinner at Italian Kitchen",
                "Board Game Night",
                "Concert at the Arena",
                "Hiking Adventure",
                "Wine Tasting Evening"
              ])

            tag = Enum.random(["Join us!", "Don't miss out!", "Limited spots!", "RSVP now!"])

            desc =
              "Join us for this exciting event! It's going to be a great time with friends and fun activities. Please RSVP to secure your spot."

            {title, tag, desc}
        end
      end

    %Event{
      title: sequence(:title, fn n -> "#{base_title} ##{n}" end),
      tagline: tagline,
      description: description,
      start_at: Faker.DateTime.forward(60),
      ends_at: Faker.DateTime.forward(90),
      timezone:
        Enum.random([
          "America/New_York",
          "America/Chicago",
          "America/Denver",
          "America/Los_Angeles"
        ]),
      visibility: Enum.random([:public, :private]),
      # Remove explicit slug to allow automatic generation
      status: Enum.random([:draft, :polling, :confirmed, :canceled]),
      theme: Enum.random(themes),
      # Favor non-virtual
      is_virtual: Enum.random([true, false, false]),
      # Set all events as free (no ticketing) for now
      is_ticketed: false,
      taxation_type: "ticketless",
      threshold_count: Enum.random([nil, 5, 10, 20]),
      polling_deadline: Faker.DateTime.forward(7),
      venue: if(Enum.random([true, false]), do: build(:realistic_venue), else: nil),
      cover_image_url:
        "https://picsum.photos/800/400?random=#{System.unique_integer([:positive])}",
      theme_customizations: %{},
      rich_external_data: %{}
    }
  end

  def realistic_venue_factory do
    # Create a realistic normalized city for the venue
    country =
      insert(:country, %{
        name: Faker.Address.country(),
        code: Faker.Address.country_code()
      })

    city =
      insert(:city, %{
        name: Faker.Address.city(),
        country_id: country.id
      })

    %Venue{
      name: Faker.Company.name(),
      address: Faker.Address.street_address(),
      city_id: city.id,
      latitude: Faker.Address.latitude(),
      longitude: Faker.Address.longitude(),
      venue_type: Enum.random(["venue", "city", "region", "online", "tbd"])
    }
  end

  @doc """
  Factory for Source schema (event discovery sources)
  """
  def public_event_source_type_factory do
    alias EventasaurusDiscovery.Sources.Source

    %Source{
      name: sequence(:source_name, &"Source #{&1}"),
      slug: sequence(:source_slug, &"source-#{&1}"),
      website_url: Faker.Internet.url(),
      priority: Enum.random(1..100),
      is_active: true,
      metadata: %{}
    }
  end

  @doc """
  Factory for PublicEventSource schema (links public events to sources)
  """
  def public_event_source_factory do
    alias EventasaurusDiscovery.PublicEvents.{PublicEventSource, PublicEvent}

    # Create a public event and source
    public_event = insert(:public_event)
    source = insert(:public_event_source_type)

    %PublicEventSource{
      event_id: public_event.id,
      source_id: source.id,
      source_url: Faker.Internet.url(),
      external_id: sequence(:external_id, &"external_#{&1}"),
      last_seen_at: DateTime.utc_now(),
      metadata: %{},
      description_translations: %{},
      image_url: nil,
      min_price: nil,
      max_price: nil,
      currency: "USD",
      is_free: true
    }
  end

  @doc """
  Factory for PublicEvent schema (events from discovery sources)
  """
  def public_event_factory do
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    # Create a venue (which includes city association)
    venue = insert(:venue)

    %PublicEvent{
      title: sequence(:public_event_title, &"Public Event #{&1}"),
      starts_at: DateTime.utc_now() |> DateTime.add(7, :day),
      ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
      venue_id: venue.id,
      title_translations: %{},
      occurrences: %{}
    }
  end
end
