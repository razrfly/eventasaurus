defmodule DevSeeds.ExtendedTicketScenarios do
  @moduledoc """
  Extended ticket sales test scenarios for comprehensive Stripe integration testing.
  Organized by phases as defined in issue #2233.

  Phase 1: Core Ticket Sales - Testing various price points and capacities
  """

  alias EventasaurusApp.{Repo, Events}
  alias EventasaurusApp.Auth.SeedUserManager

  # Load helpers
  Code.require_file("helpers.exs", __DIR__)
  alias DevSeeds.Helpers

  def seed_phase_1 do
    Helpers.section("Phase 1: Core Ticket Sales Test Scenarios")

    # Get or create test organizer for Phase 1 events
    organizer = get_or_create_phase1_organizer()

    if organizer do
      create_low_price_event(organizer)
      create_high_price_event(organizer)
      create_multi_tier_festival(organizer)
      create_small_capacity_event(organizer)
      create_large_capacity_event(organizer)

      Helpers.success("Phase 1 test scenarios created successfully")
    else
      Helpers.error("Failed to create Phase 1 organizer")
    end
  end

  defp get_or_create_phase1_organizer do
    Helpers.log("Getting or creating Phase 1 test organizer...")

    persona_attrs = %{
      name: "Event Tester",
      email: "event_tester@example.com",
      username: "event_tester",
      password: "testpass123",
      bio: "Professional event organizer focused on diverse ticketing scenarios. Testing various price points and event capacities.",
      profile_public: true,
      website_url: "https://example.com/testing",
      timezone: "America/Los_Angeles"
    }

    case SeedUserManager.get_or_create_user(persona_attrs) do
      {:ok, user} ->
        Helpers.log("Created/Retrieved organizer: #{user.name}", :green)
        user
      {:error, reason} ->
        Helpers.error("Failed to create Event Tester: #{inspect(reason)}")
        nil
    end
  end

  # Phase 1, Scenario 1: Low-Price Event
  defp create_low_price_event(organizer) do
    Helpers.log("Creating low-price event ($5-10)...", :blue)

    event_data = %{
      title: "Community Coffee Meetup",
      description: """
      Join us for a casual morning coffee and networking!

      ☕ What's Included:
      - Coffee or tea of your choice
      - Light pastries and snacks
      - Casual networking opportunity
      - Meet local professionals and entrepreneurs

      🎯 Perfect for:
      - Remote workers looking to connect
      - Entrepreneurs and freelancers
      - Anyone wanting to expand their network

      Location: Local Coffee Shop
      Duration: 2 hours
      """,
      tagline: "Network Over Coffee",
      is_ticketed: true,
      ticket_types: [
        %{
          name: "General Admission",
          price: 8.00,
          quantity: 100,
          description: "Includes coffee/tea and light refreshments"
        }
      ]
    }

    create_event_with_tickets(organizer, event_data, :minimal)
  end

  # Phase 1, Scenario 2: High-Price Event
  defp create_high_price_event(organizer) do
    Helpers.log("Creating high-price event ($200-500)...", :blue)

    event_data = %{
      title: "Premium Tech Conference 2025",
      description: """
      The premier technology conference for industry leaders and innovators!

      🚀 Conference Highlights:
      - 20+ world-class speakers
      - Full-day workshops on AI, Cloud, and Web3
      - Networking dinner with executives
      - Expo hall with cutting-edge demos
      - Certificate of completion
      - 1-year access to recorded sessions

      🎯 Who Should Attend:
      - CTOs and Engineering Managers
      - Senior Developers and Architects
      - Tech Entrepreneurs
      - Product Leaders

      📍 Venue: Convention Center Grand Hall
      ⏰ Duration: 2 full days
      """,
      tagline: "Where Innovation Meets Excellence",
      is_ticketed: true,
      ticket_types: [
        %{
          name: "Standard Pass",
          price: 299.00,
          quantity: 200,
          description: "Access to all sessions, expo hall, and networking events"
        },
        %{
          name: "VIP Pass",
          price: 499.00,
          quantity: 50,
          description: "Standard Pass benefits PLUS: Front-row seating, private speaker Q&A, executive dinner, and premium swag bag"
        }
      ]
    }

    create_event_with_tickets(organizer, event_data, :professional)
  end

  # Phase 1, Scenario 3: Multi-Tier Festival
  defp create_multi_tier_festival(organizer) do
    Helpers.log("Creating multi-tier festival (5+ ticket types)...", :blue)

    event_data = %{
      title: "Summer Music Festival 2025",
      description: """
      Three days of incredible live music featuring 30+ bands across 4 stages!

      🎸 Festival Features:
      - Headline acts and emerging artists
      - Multiple genre stages (Rock, Electronic, Indie, Hip-Hop)
      - Food truck village with 20+ vendors
      - Art installations and interactive experiences
      - Camping options available
      - Free water stations and charging areas

      📅 Schedule:
      - Friday: 4 PM - Midnight (Opening Night)
      - Saturday: Noon - 2 AM (Main Event)
      - Sunday: Noon - 10 PM (Closing Day)

      🎟️ Choose your experience level!
      """,
      tagline: "Three Days of Music, Art, and Community",
      is_ticketed: true,
      ticket_types: [
        %{
          name: "Early Bird General",
          price: 89.00,
          quantity: 300,
          description: "3-day festival pass - Limited time offer! Access to all stages and general camping area."
        },
        %{
          name: "General Admission",
          price: 129.00,
          quantity: 800,
          description: "3-day festival pass with access to all stages and general camping area"
        },
        %{
          name: "VIP Weekend Pass",
          price: 249.00,
          quantity: 150,
          description: "VIP viewing areas, dedicated bathrooms, complimentary drinks, air-conditioned lounge, express entry"
        },
        %{
          name: "Backstage Pass",
          price: 449.00,
          quantity: 50,
          description: "All VIP benefits PLUS: Meet & greet with select artists, side-stage viewing, artist lounge access, exclusive merch"
        },
        %{
          name: "Premium Parking",
          price: 40.00,
          quantity: 200,
          description: "Reserved parking spot close to main entrance (separate from festival admission)"
        }
      ]
    }

    create_event_with_tickets(organizer, event_data, :celebration)
  end

  # Phase 1, Scenario 4: Small Capacity Event
  defp create_small_capacity_event(organizer) do
    Helpers.log("Creating small capacity event (10-20 tickets)...", :blue)

    event_data = %{
      title: "Intimate Chef's Table Dinner",
      description: """
      An exclusive dining experience with renowned Chef Martinez.

      🍽️ Experience Includes:
      - 7-course tasting menu
      - Wine pairings for each course
      - Meet the chef and tour the kitchen
      - Recipes and cooking tips
      - Intimate setting with only 15 guests

      🌟 This Season's Menu:
      - Amuse-bouche: Oyster with champagne foam
      - Course 1: Heirloom tomato gazpacho
      - Course 2: Pan-seared scallops
      - Course 3: Wild mushroom risotto
      - Course 4: Duck confit with cherry reduction
      - Course 5: Artisanal cheese selection
      - Course 6: Chocolate soufflé

      ⏰ Seating at 7:00 PM sharp
      📍 Private dining room
      """,
      tagline: "An Unforgettable Culinary Journey",
      is_ticketed: true,
      ticket_types: [
        %{
          name: "Dinner Seat",
          price: 185.00,
          quantity: 15,
          description: "One seat at the exclusive chef's table with full tasting menu and wine pairings"
        }
      ]
    }

    create_event_with_tickets(organizer, event_data, :nature)
  end

  # Phase 1, Scenario 5: Large Capacity Event
  defp create_large_capacity_event(organizer) do
    Helpers.log("Creating large capacity event (500+ tickets)...", :blue)

    event_data = %{
      title: "Tech Careers Expo 2025",
      description: """
      The largest technology career fair in the region!

      💼 Event Features:
      - 100+ Companies recruiting
      - On-site interviews and job offers
      - Resume review stations
      - Career coaching sessions
      - Tech workshops and demos
      - Startup showcase
      - Networking lounges

      🎯 Companies Attending:
      - Major tech companies (Google, Amazon, Microsoft)
      - Fast-growing startups
      - Local tech firms
      - Consulting companies
      - Government agencies

      📋 What to Bring:
      - Multiple copies of your resume
      - Portfolio (if applicable)
      - Business cards
      - Laptop for technical assessments

      ⏰ Hours: 9 AM - 5 PM
      📍 Convention Center - All 3 halls
      """,
      tagline: "Launch Your Tech Career",
      is_ticketed: true,
      ticket_types: [
        %{
          name: "Job Seeker Pass",
          price: 15.00,
          quantity: 800,
          description: "Access to all career fair areas, workshops, and networking events"
        },
        %{
          name: "Student Pass",
          price: 5.00,
          quantity: 300,
          description: "Discounted rate for students (ID required at check-in)"
        },
        %{
          name: "Premium Career Package",
          price: 49.00,
          quantity: 100,
          description: "Job Seeker Pass PLUS: Priority resume review, 1-on-1 career coaching session, front-row workshop seating"
        }
      ]
    }

    create_event_with_tickets(organizer, event_data, :professional)
  end

  # Helper function to create event with tickets
  defp create_event_with_tickets(organizer, event_data, theme) do
    ticket_types = Map.get(event_data, :ticket_types, [])

    event_params = Map.merge(%{
      title: unique_title(event_data.title),
      description: event_data.description,
      tagline: event_data.tagline,
      status: :confirmed,
      visibility: :public,
      theme: theme,
      is_virtual: false,
      is_ticketed: event_data.is_ticketed,
      taxation_type: if(event_data.is_ticketed, do: "ticketed_event", else: "ticketless"),
      start_at: Faker.DateTime.forward(Enum.random(7..60)),
      ends_at: Faker.DateTime.forward(Enum.random(61..65)),
      timezone: organizer.timezone || "America/Los_Angeles"
    }, Helpers.get_random_image_attrs())

    case Events.create_event_with_organizer(event_params, organizer) do
      {:ok, event} ->
        # Create tickets for ticketed events
        if event_data.is_ticketed && ticket_types != [] do
          create_tickets_for_event(event, ticket_types)
        end

        Helpers.log("Created event: #{event.title} (ticketed: #{event.is_ticketed})", :green)
        event

      {:error, changeset} ->
        Helpers.error("Failed to create event: #{inspect(changeset.errors)}")
        nil
    end
  end

  defp create_tickets_for_event(event, ticket_types) do
    Enum.each(ticket_types, fn ticket_data ->
      ticket_attrs = %{
        event_id: event.id,
        title: ticket_data.name,
        description: ticket_data.description,
        base_price_cents: round(ticket_data.price * 100),
        pricing_model: "fixed",
        currency: "usd",
        quantity: ticket_data.quantity,
        starts_at: event.start_at |> DateTime.add(-30, :day),
        ends_at: event.start_at,
        tippable: false
      }

      case Repo.insert(%EventasaurusApp.Events.Ticket{} |> Ecto.Changeset.change(ticket_attrs)) do
        {:ok, ticket} ->
          Helpers.log("  → Created ticket: #{ticket.title} ($#{ticket_data.price}) - #{ticket_data.quantity} available", :blue)
        {:error, changeset} ->
          Helpers.error("  → Failed to create ticket: #{inspect(changeset.errors)}")
      end
    end)
  end

  defp event_exists?(title) do
    import Ecto.Query
    Repo.exists?(from e in EventasaurusApp.Events.Event, where: e.title == ^title and is_nil(e.deleted_at))
  end

  defp unique_title(base, attempt \\ 0) do
    max_attempts = 100

    if attempt >= max_attempts do
      "#{base} #{System.unique_integer([:positive])}"
    else
      candidate = if attempt == 0, do: base, else: "#{base} (#{attempt})"
      if event_exists?(candidate), do: unique_title(base, attempt + 1), else: candidate
    end
  end
end

# Allow direct execution of this script
if __ENV__.file == Path.absname(__ENV__.file) do
  DevSeeds.ExtendedTicketScenarios.seed_phase_1()
end
