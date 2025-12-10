defmodule DevSeeds.ExtendedTicketScenarios do
  @moduledoc """
  Extended ticket sales test scenarios for comprehensive Stripe integration testing.
  Organized by phases as defined in issue #2233.

  Phase 1: Core Ticket Sales - Testing various price points and capacities
  Phase 2: Fundraising / Kickstarter Events - Testing threshold-based events
  """

  alias EventasaurusApp.{Repo, Events}
  alias EventasaurusApp.Auth.SeedUserManager

  # Load helpers
  Code.require_file("../../support/helpers.exs", __DIR__)
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
      duration_hours: 2,
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
      duration_hours: 48,
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
      duration_hours: 72,
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
      duration_hours: 3,
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
      duration_hours: 8,
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
    duration_hours = Map.get(event_data, :duration_hours, 4)  # default 4 hours

    # Generate start time
    start_at = Faker.DateTime.forward(Enum.random(7..60))

    # Calculate ends_at based on duration (convert to integer for DateTime.add)
    ends_at = DateTime.add(start_at, round(duration_hours * 3600), :second)

    event_params = Map.merge(%{
      title: unique_title(event_data.title),
      description: event_data.description,
      tagline: event_data.tagline,
      status: :confirmed,
      visibility: :public,
      theme: theme,
      is_virtual: true,  # Set to virtual since we don't create venues for these events
      virtual_venue_url: "https://zoom.us/j/#{:rand.uniform(999999999)}",
      is_ticketed: event_data.is_ticketed,
      taxation_type: if(event_data.is_ticketed, do: "ticketed_event", else: "ticketless"),
      start_at: start_at,
      ends_at: ends_at,
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

  # ============================================================================
  # PHASE 2: FUNDRAISING / KICKSTARTER EVENTS
  # ============================================================================

  def seed_phase_2 do
    Helpers.section("Phase 2: Fundraising / Kickstarter Events")

    # Get or create test organizer for Phase 2 events
    organizer = get_or_create_phase2_organizer()

    if organizer do
      create_community_garden_kickstarter(organizer)
      create_playground_fundraiser(organizer)
      create_book_club_threshold(organizer)
      create_tram_party_threshold(organizer)
      create_exclusive_workshop_threshold(organizer)
      create_coding_bootcamp_combined_threshold(organizer)

      Helpers.success("Phase 2 test scenarios created successfully")
    else
      Helpers.error("Failed to create Phase 2 organizer")
    end
  end

  defp get_or_create_phase2_organizer do
    Helpers.log("Getting or creating Phase 2 test organizer...")

    persona_attrs = %{
      name: "Community Builder",
      email: "community_builder@example.com",
      username: "community_builder",
      password: "testpass123",
      bio: "Passionate community organizer focused on Kickstarter-style events and grassroots fundraising initiatives.",
      profile_public: true,
      website_url: "https://example.com/community",
      timezone: "America/Los_Angeles"
    }

    case SeedUserManager.get_or_create_user(persona_attrs) do
      {:ok, user} ->
        Helpers.log("Created/Retrieved organizer: #{user.name}", :green)
        user
      {:error, reason} ->
        Helpers.error("Failed to create Community Builder: #{inspect(reason)}")
        nil
    end
  end

  # Phase 2, Scenario 1: Community Garden Kickstarter
  defp create_community_garden_kickstarter(organizer) do
    Helpers.log("Creating Community Garden Kickstarter (revenue threshold: $5,000)...", :blue)

    event_data = %{
      title: "Community Garden Project",
      description: """
      Help us build a beautiful community garden in the heart of our neighborhood!

      🌱 Project Goals:
      - Build 20 raised garden beds
      - Install irrigation system
      - Create composting area
      - Plant fruit trees and berry bushes
      - Build gathering pavilion for workshops

      🎯 Funding Goal: $5,000
      If we reach our goal, construction starts in Spring 2025!

      🌻 Contribution Benefits:
      Every contribution helps make this dream a reality. Choose your support level and help grow our community!

      📍 Location: Corner of Maple & Oak Street
      ⏰ Garden will be open to all community members
      """,
      tagline: "Grow Community, Grow Together",
      is_ticketed: true,
      taxation_type: "contribution_collection",
      status: :threshold,
      threshold_type: "revenue",
      threshold_revenue_cents: 500_000, # $5,000
      duration_hours: 720, # 30-day fundraising campaign
      ticket_types: [
        %{name: "Seedling Supporter", price: 10.00, quantity: 100, description: "Every bit helps! Thank you for planting the seeds of community."},
        %{name: "Gardener Friend", price: 25.00, quantity: 100, description: "Your name on our donor wall + community garden newsletter"},
        %{name: "Green Thumb Champion", price: 50.00, quantity: 50, description: "All above + personalized garden brick + early access to harvests"},
        %{name: "Harvest Hero", price: 100.00, quantity: 30, description: "All above + reserved garden plot for one season + workshop credits"},
        %{name: "Garden Founder", price: 500.00, quantity: 10, description: "All above + permanent plaque + lifetime VIP garden access + annual dinner"}
      ]
    }

    create_threshold_event_with_tickets(organizer, event_data, :nature)
  end

  # Phase 2, Scenario 2: Playground Fundraiser
  defp create_playground_fundraiser(organizer) do
    Helpers.log("Creating New Playground Fundraiser (revenue threshold: $10,000)...", :blue)

    event_data = %{
      title: "New Playground for Lincoln Elementary",
      description: """
      Our children deserve a safe, modern playground! Help us replace the 30-year-old equipment.

      🎪 What We're Building:
      - Modern climbing structures
      - Accessible swings and slides
      - Sensory play areas
      - Shaded seating for parents
      - Safety surfacing throughout

      🎯 Funding Goal: $10,000
      Reach our goal and installation happens this summer!

      👶 Impact:
      - 400+ students will benefit daily
      - Improved safety standards
      - Inclusive play for all abilities
      - Community gathering space

      📍 Location: Lincoln Elementary School
      ⏰ Completion: Summer 2025
      """,
      tagline: "Where Children Play and Memories Are Made",
      is_ticketed: true,
      taxation_type: "contribution_collection",
      status: :threshold,
      threshold_type: "revenue",
      threshold_revenue_cents: 1_000_000, # $10,000
      duration_hours: 720, # 30-day fundraising campaign
      ticket_types: [
        %{name: "Friend of the Playground", price: 25.00, quantity: 150, description: "Thank you card from the students"},
        %{name: "Play Supporter", price: 100.00, quantity: 75, description: "Recognition on our donor board + school newsletter feature"},
        %{name: "Playground Champion", price: 250.00, quantity: 30, description: "All above + engraved brick in playground walkway"},
        %{name: "Founding Benefactor", price: 1000.00, quantity: 10, description: "All above + name on playground plaque + dedication ceremony invitation"}
      ]
    }

    create_threshold_event_with_tickets(organizer, event_data, :celebration)
  end

  # Phase 2, Scenario 3: Book Club Threshold
  defp create_book_club_threshold(organizer) do
    Helpers.log("Creating Book Club Launch (attendee threshold: 20 people)...", :blue)

    event_data = %{
      title: "Mystery Book Club Launch",
      description: """
      Love mystery novels? Join our monthly book club!

      📚 What to Expect:
      - Monthly mystery novel selections
      - Engaging discussions and theories
      - Author Q&A sessions (quarterly)
      - Cozy meeting space at local cafe
      - Book swap opportunities

      🎯 Minimum Attendees: 20 members
      We need at least 20 committed members to launch!

      📖 First Book: "The Thursday Murder Club"
      Meeting: Second Tuesday of each month

      ☕ Location: Corner Cafe
      ⏰ Time: 7:00 PM - 8:30 PM
      """,
      tagline: "Unravel Mysteries Together",
      is_ticketed: false,
      taxation_type: "ticketless",
      status: :threshold,
      threshold_type: "attendee_count",
      threshold_count: 20,
      duration_hours: 1.5, # 7PM to 8:30PM
      ticket_types: [] # Free event
    }

    create_threshold_event_with_tickets(organizer, event_data, :minimal)
  end

  # Phase 2, Scenario 3b: Tram Party Threshold
  defp create_tram_party_threshold(organizer) do
    Helpers.log("Creating Tram Party (attendee threshold: 10 people)...", :blue)

    event_data = %{
      title: "Tram Party",
      description: """
      All aboard for the ultimate party on rails!

      🚃 What to Expect:
      - Private vintage tram rental
      - 2-hour scenic route through the city
      - DJ and sound system on board
      - Drinks and snacks included
      - Photo opportunities at iconic stops
      - Party lights and decorations

      🎯 Minimum Attendees: 10 people
      We need at least 10 party-goers to book the tram!

      🎉 Perfect For:
      - Birthday celebrations
      - Bachelor/bachelorette parties
      - Team building events
      - Just because it's awesome!

      📍 Departure: Central Station Tram Stop
      ⏰ Duration: 2 hours (8 PM - 10 PM)
      """,
      tagline: "Party on Rails",
      is_ticketed: true,
      taxation_type: "ticketed_event",
      status: :threshold,
      threshold_type: "attendee_count",
      threshold_count: 10,
      duration_hours: 2,
      ticket_types: [
        %{name: "Party Ticket", price: 25.00, quantity: 30, description: "Includes tram ride, drinks, snacks, and all the fun!"}
      ]
    }

    create_threshold_event_with_tickets(organizer, event_data, :celebration)
  end

  # Phase 2, Scenario 4: Exclusive Workshop Threshold
  defp create_exclusive_workshop_threshold(organizer) do
    Helpers.log("Creating Exclusive Workshop (revenue threshold: $1,125)...", :blue)

    event_data = %{
      title: "Advanced Photography Workshop",
      description: """
      Master portrait photography with award-winning photographer Sarah Chen!

      📸 Workshop Details:
      - Full-day intensive training
      - Studio lighting techniques
      - Post-processing workflows
      - Portfolio review session
      - Professional networking

      🎯 Minimum Revenue: $1,125 (15 attendees at $75 each)
      Workshop only runs if we reach minimum enrollment!

      🏆 Instructor: Sarah Chen
      - 15+ years professional experience
      - Published in National Geographic
      - Former Adobe Creative Resident

      📍 Location: Downtown Studio
      ⏰ Duration: 9 AM - 5 PM (lunch included)
      """,
      tagline: "Elevate Your Photography Skills",
      is_ticketed: true,
      taxation_type: "ticketed_event",
      status: :threshold,
      threshold_type: "revenue",
      threshold_revenue_cents: 112_500, # $1,125 (15 × $75)
      duration_hours: 8, # 9 AM to 5 PM
      ticket_types: [
        %{name: "Workshop Seat", price: 75.00, quantity: 20, description: "Full-day workshop with professional photographer + lunch + materials"}
      ]
    }

    create_threshold_event_with_tickets(organizer, event_data, :professional)
  end

  # Phase 2, Scenario 5: Combined Threshold Event
  defp create_coding_bootcamp_combined_threshold(organizer) do
    Helpers.log("Creating Coding Bootcamp (combined threshold: 50 attendees AND $2,500)...", :blue)

    event_data = %{
      title: "Intro to Web Development Bootcamp",
      description: """
      Launch your web development career in this intensive weekend bootcamp!

      💻 What You'll Learn:
      - HTML, CSS, JavaScript fundamentals
      - Responsive web design
      - Git version control
      - Deploy your first website
      - Portfolio project

      🎯 Requirements to Run:
      - Minimum 50 students enrolled
      - Minimum $2,500 total revenue
      Both requirements must be met!

      👩‍💻 Includes:
      - 2-day intensive training
      - All materials and tools
      - Lunch both days
      - Certificate of completion
      - Job search resources
      - 30 days of mentorship support

      📍 Location: Tech Training Center
      ⏰ Duration: Saturday & Sunday, 9 AM - 5 PM
      """,
      tagline: "Code Your Future",
      is_ticketed: true,
      taxation_type: "ticketed_event",
      status: :threshold,
      threshold_type: "both",
      threshold_count: 50,
      threshold_revenue_cents: 250_000, # $2,500
      duration_hours: 16, # 2 days × 8 hours (Saturday & Sunday, 9 AM - 5 PM)
      ticket_types: [
        %{name: "Bootcamp Ticket", price: 50.00, quantity: 100, description: "2-day intensive web development bootcamp + all materials + certificate + mentorship"}
      ]
    }

    create_threshold_event_with_tickets(organizer, event_data, :professional)
  end

  # Helper function to create threshold event with tickets
  defp create_threshold_event_with_tickets(organizer, event_data, theme) do
    ticket_types = Map.get(event_data, :ticket_types, [])
    duration_hours = Map.get(event_data, :duration_hours, 4)

    # Generate start time once
    start_at = Faker.DateTime.forward(Enum.random(30..90))

    # Calculate ends_at based on duration (convert to integer for DateTime.add)
    ends_at = DateTime.add(start_at, round(duration_hours * 3600), :second)

    event_params = Map.merge(%{
      title: unique_title(event_data.title),
      description: event_data.description,
      tagline: event_data.tagline,
      status: event_data.status,
      visibility: :public,
      theme: theme,
      is_virtual: true,  # Set to virtual since we don't create venues for these events
      virtual_venue_url: "https://zoom.us/j/#{:rand.uniform(999999999)}",
      is_ticketed: event_data.is_ticketed,
      taxation_type: event_data.taxation_type,
      threshold_type: event_data.threshold_type,
      threshold_count: Map.get(event_data, :threshold_count),
      threshold_revenue_cents: Map.get(event_data, :threshold_revenue_cents),
      start_at: start_at,
      ends_at: ends_at,
      timezone: organizer.timezone || "America/Los_Angeles"
    }, Helpers.get_random_image_attrs())

    case Events.create_event_with_organizer(event_params, organizer) do
      {:ok, event} ->
        # Create tickets for ticketed events
        if event_data.is_ticketed && ticket_types != [] do
          create_tickets_for_event(event, ticket_types)
        end

        Helpers.log("Created threshold event: #{event.title} (status: #{event.status}, threshold_type: #{event.threshold_type})", :green)
        event

      {:error, changeset} ->
        Helpers.error("Failed to create threshold event: #{inspect(changeset.errors)}")
        nil
    end
  end
end

# Allow direct execution of this script
if __ENV__.file == Path.absname(__ENV__.file) do
  DevSeeds.ExtendedTicketScenarios.seed_phase_1()
  DevSeeds.ExtendedTicketScenarios.seed_phase_2()
end
