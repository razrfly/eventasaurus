defmodule DevSeeds.TicketedEventOrganizers do
  @moduledoc """
  Creates event organizer personas who create ticketed events and participate in the community.
  Phase 1 implementation from issue #1036.
  """
  
  alias EventasaurusApp.{Repo, Accounts, Events}
  alias EventasaurusApp.Events.EventUser
  alias EventasaurusApp.Auth.SeedUserManager
  
  # Load helpers
  Code.require_file("helpers.exs", __DIR__)
  alias DevSeeds.Helpers
  
  def ensure_ticketed_event_organizers do
    Helpers.section("Creating Ticketed Event Organizer Personas")
    
    # Load curated data for realistic content
    Code.require_file("curated_data.exs", __DIR__)
    
    # Create or get our event organizer personas
    organizers = create_organizer_personas()
    
    # Create events for each organizer
    create_go_kart_events(Enum.at(organizers, 0))
    create_workshop_events(Enum.at(organizers, 1))
    create_entertainment_events(Enum.at(organizers, 2))
    create_fundraiser_events(Enum.at(organizers, 3))
    
    # Make organizers participate in other events
    make_organizers_participate(organizers)
    
    Helpers.success("Ticketed event organizers created with their events")
  end
  
  defp create_organizer_personas do
    Helpers.log("Creating event organizer personas...")
    
    personas = [
      %{
        name: "Go-Kart Racer",
        email: "go_kart_racer@example.com",
        username: "go_kart_racer",
        password: "testpass123",
        bio: "Professional go-kart racing organizer. Love speed and competition! Organizing racing events and competitions.",
        profile_public: true,
        website_url: "https://example.com/racing",
        instagram_handle: "gokart_racer",
        timezone: "America/Los_Angeles"
      },
      %{
        name: "Workshop Leader",
        email: "workshop_leader@example.com",
        username: "workshop_leader",
        password: "testpass123",
        bio: "Educational workshop facilitator. Teaching practical skills and fostering learning communities.",
        profile_public: true,
        linkedin_handle: "workshop-leader",
        timezone: "America/New_York"
      },
      %{
        name: "Entertainment Host",
        email: "entertainment_host@example.com",
        username: "entertainment_host",
        password: "testpass123",
        bio: "Entertainment coordinator bringing comedy, music, and fun to the community!",
        profile_public: true,
        instagram_handle: "entertainment_host",
        x_handle: "entertain_host",
        timezone: "America/Chicago"
      },
      %{
        name: "Community Fundraiser",
        email: "community_fundraiser@example.com",
        username: "community_fundraiser",
        password: "testpass123",
        bio: "Passionate about community causes. Organizing fundraisers and charity events for local nonprofits.",
        profile_public: true,
        website_url: "https://example.com/fundraising",
        timezone: "America/Denver"
      }
    ]
    
    Enum.map(personas, fn persona_attrs ->
      case SeedUserManager.get_or_create_user(persona_attrs) do
        {:ok, user} -> 
          Helpers.log("Created/Retrieved persona: #{user.name}", :green)
          user
        {:error, reason} -> 
          Helpers.error("Failed to create #{persona_attrs.name}: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(& &1)
  end
  
  defp create_go_kart_events(organizer) when not is_nil(organizer) do
    import Ecto.Query
    
    Helpers.log("Creating go-kart racing events for #{organizer.name}")
    
    # Check existing events
    existing_count = Repo.aggregate(
      from(eu in EventUser, 
        join: e in assoc(eu, :event),
        where: eu.user_id == ^organizer.id and 
               eu.role in ["owner", "organizer"] and 
               is_nil(e.deleted_at)),
      :count
    )
    
    if existing_count < 4 do
      # Create racing events with tickets
      events_data = [
        %{
          title: "Grand Prix Go-Kart Championship",
          description: """
          Join us for an exciting day of go-kart racing! This is our flagship championship event.
          
          🏁 Professional track with timing system
          🏆 Trophies for top 3 finishers
          🎯 Multiple race heats based on skill level
          🍕 Food and drinks available at the venue
          
          All skill levels welcome! Safety gear provided.
          """,
          tagline: "Speed, Competition, and Fun!",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 45.00,
              quantity: 50,
              description: "Standard race entry with 2 qualifying heats"
            },
            %{
              name: "VIP Racer",
              price: 85.00,
              quantity: 20,
              description: "Premium package with 3 heats, reserved pit area, and lunch included"
            },
            %{
              name: "Early Bird Special",
              price: 35.00,
              quantity: 15,
              description: "Limited early bird pricing - same as general admission"
            }
          ]
        },
        %{
          title: "Beginner's Karting Workshop",
          description: """
          New to karting? This is the perfect event for you!
          
          Learn the basics of go-kart racing in a fun, supportive environment.
          - Racing line theory
          - Braking and acceleration techniques
          - Safety procedures
          - Practice sessions with instruction
          """,
          tagline: "Learn to Race Like a Pro",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 60.00,
              quantity: 30,
              description: "Full workshop with 90 minutes of track time"
            }
          ]
        },
        %{
          title: "Night Racing Under the Lights",
          description: """
          Experience the thrill of racing under the lights!
          
          Special evening event with:
          - LED-lit track
          - Glow-in-the-dark elements
          - DJ and music
          - BBQ dinner available
          """,
          tagline: "Racing After Dark",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 55.00,
              quantity: 40,
              description: "Night racing experience with 2 race sessions"
            }
          ]
        },
        %{
          title: "Team Endurance Race",
          description: """
          Form a team and compete in our 2-hour endurance race!
          
          - Teams of 3-4 drivers
          - Driver changes every 15 minutes
          - Real-time scoring and leaderboard
          - Team strategy is key!
          """,
          tagline: "Teamwork Makes the Dream Work",
          is_ticketed: false  # One free event to show mix
        }
      ]
      
      Enum.each(events_data, fn event_data ->
        # Extract ticket types if present
        ticket_types = Map.get(event_data, :ticket_types, [])
        
        # Prepare event params
        event_params = Map.merge(%{
          title: unique_title(event_data.title),
          description: event_data.description,
          tagline: event_data.tagline,
          status: :confirmed,
          visibility: :public,
          theme: :velocity,
          is_virtual: false,
          is_ticketed: event_data.is_ticketed,
          taxation_type: if(event_data.is_ticketed, do: "ticketed_event", else: "ticketless"),
          start_at: Faker.DateTime.forward(Enum.random(5..45)),
          ends_at: Faker.DateTime.forward(Enum.random(46..48)),
          timezone: organizer.timezone || "America/Los_Angeles"
        }, Helpers.get_random_image_attrs())
        
        {:ok, event} = Events.create_event_with_organizer(event_params, organizer)
        
        # Create tickets for ticketed events
        if event_data.is_ticketed && ticket_types != [] do
          create_tickets_for_event(event, ticket_types)
        end
        
        Helpers.log("Created go-kart event: #{event.title} (ticketed: #{event.is_ticketed})", :green)
      end)
    end
  end
  
  defp create_go_kart_events(_), do: Helpers.log("Go-Kart organizer not found", :yellow)
  
  defp create_workshop_events(organizer) when not is_nil(organizer) do
    import Ecto.Query
    
    Helpers.log("Creating workshop events for #{organizer.name}")
    
    existing_count = Repo.aggregate(
      from(eu in EventUser, 
        join: e in assoc(eu, :event),
        where: eu.user_id == ^organizer.id and 
               eu.role in ["owner", "organizer"] and 
               is_nil(e.deleted_at)),
      :count
    )
    
    if existing_count < 4 do
      events_data = [
        %{
          title: "Introduction to Web Development",
          description: """
          Learn the fundamentals of web development in this hands-on workshop!
          
          📚 What you'll learn:
          - HTML & CSS basics
          - JavaScript fundamentals
          - Building your first website
          - Deploying to the web
          
          💻 Bring your laptop! All software will be provided.
          """,
          tagline: "Build Your First Website",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 75.00,
              quantity: 25,
              description: "Full workshop access with materials and resources"
            }
          ]
        },
        %{
          title: "Photography Masterclass",
          description: """
          Elevate your photography skills with professional techniques!
          
          📸 Topics covered:
          - Composition and lighting
          - Camera settings explained
          - Portrait photography
          - Photo editing basics
          
          Suitable for beginners and intermediate photographers.
          """,
          tagline: "Capture Better Photos",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 65.00,
              quantity: 20,
              description: "Workshop access with hands-on practice sessions"
            }
          ]
        },
        %{
          title: "Public Speaking Workshop",
          description: """
          Overcome your fear of public speaking and become a confident presenter!
          
          🎤 Workshop includes:
          - Speaking techniques
          - Managing nervousness
          - Engaging your audience
          - Practice presentations with feedback
          """,
          tagline: "Find Your Voice",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 50.00,
              quantity: 15,
              description: "Interactive workshop with personalized feedback"
            }
          ]
        },
        %{
          title: "Creative Writing Circle",
          description: """
          Join our creative writing workshop and unleash your imagination!
          
          ✍️ Activities:
          - Writing prompts and exercises
          - Group feedback sessions
          - Genre exploration
          - Publishing tips
          """,
          tagline: "Tell Your Story",
          is_ticketed: false  # One free workshop
        }
      ]
      
      Enum.each(events_data, fn event_data ->
        ticket_types = Map.get(event_data, :ticket_types, [])
        
        event_params = Map.merge(%{
          title: unique_title(event_data.title),
          description: event_data.description,
          tagline: event_data.tagline,
          status: :confirmed,
          visibility: :public,
          theme: :professional,
          is_virtual: Enum.random([true, false]),
          is_ticketed: event_data.is_ticketed,
          taxation_type: if(event_data.is_ticketed, do: "ticketed_event", else: "ticketless"),
          start_at: Faker.DateTime.forward(Enum.random(3..40)),
          ends_at: Faker.DateTime.forward(Enum.random(41..43)),
          timezone: organizer.timezone || "America/New_York"
        }, Helpers.get_random_image_attrs())
        
        {:ok, event} = Events.create_event_with_organizer(event_params, organizer)
        
        # Create tickets for ticketed events
        if event_data.is_ticketed && ticket_types != [] do
          create_tickets_for_event(event, ticket_types)
        end
        
        Helpers.log("Created workshop event: #{event.title} (ticketed: #{event.is_ticketed})", :green)
      end)
    end
  end
  
  defp create_workshop_events(_), do: Helpers.log("Workshop organizer not found", :yellow)
  
  defp create_entertainment_events(organizer) when not is_nil(organizer) do
    import Ecto.Query
    
    Helpers.log("Creating entertainment events for #{organizer.name}")
    
    existing_count = Repo.aggregate(
      from(eu in EventUser, 
        join: e in assoc(eu, :event),
        where: eu.user_id == ^organizer.id and 
               eu.role in ["owner", "organizer"] and 
               is_nil(e.deleted_at)),
      :count
    )
    
    if existing_count < 4 do
      events_data = [
        %{
          title: "Comedy Night at the Lounge",
          description: """
          Get ready to laugh! Join us for an evening of stand-up comedy.
          
          🎭 Featuring:
          - 4 professional comedians
          - 2 hours of non-stop laughs
          - Full bar available
          - 18+ event
          
          Doors open at 7 PM, show starts at 8 PM.
          """,
          tagline: "Laughter is the Best Medicine",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 25.00,
              quantity: 80,
              description: "General seating - first come, first served"
            }
          ]
        },
        %{
          title: "Live Music Festival",
          description: """
          A day of amazing live music featuring local and touring bands!
          
          🎸 Lineup:
          - 5 incredible bands
          - Multiple genres
          - Food trucks on site
          - Beer garden
          
          All ages welcome! Under 18 must be accompanied by an adult.
          """,
          tagline: "Music for Everyone",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "General Admission",
              price: 40.00,
              quantity: 200,
              description: "Full day festival access"
            }
          ]
        },
        %{
          title: "Trivia Night Championship",
          description: """
          Test your knowledge at our monthly trivia championship!
          
          🧠 Details:
          - Teams of up to 6 people
          - 6 rounds of questions
          - Prizes for top 3 teams
          - Food and drinks available
          
          Reserve your team's spot today!
          """,
          tagline: "Battle of the Brains",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "Team Registration",
              price: 60.00,
              quantity: 20,
              description: "Register your entire team (up to 6 people)"
            }
          ]
        },
        %{
          title: "Open Mic Night",
          description: """
          Share your talent at our open mic night!
          
          🎤 All performers welcome:
          - Musicians
          - Comedians
          - Poets
          - Storytellers
          
          Sign up starts at 6 PM, performances at 7 PM.
          """,
          tagline: "Your Stage Awaits",
          is_ticketed: false  # Free community event
        }
      ]
      
      Enum.each(events_data, fn event_data ->
        ticket_types = Map.get(event_data, :ticket_types, [])
        
        event_params = Map.merge(%{
          title: unique_title(event_data.title),
          description: event_data.description,
          tagline: event_data.tagline,
          status: :confirmed,
          visibility: :public,
          theme: :celebration,
          is_virtual: false,
          is_ticketed: event_data.is_ticketed,
          taxation_type: if(event_data.is_ticketed, do: "ticketed_event", else: "ticketless"),
          start_at: Faker.DateTime.forward(Enum.random(7..50)),
          ends_at: Faker.DateTime.forward(Enum.random(51..53)),
          timezone: organizer.timezone || "America/Chicago"
        }, Helpers.get_random_image_attrs())
        
        {:ok, event} = Events.create_event_with_organizer(event_params, organizer)
        
        # Create tickets for ticketed events
        if event_data.is_ticketed && ticket_types != [] do
          create_tickets_for_event(event, ticket_types)
        end
        
        Helpers.log("Created entertainment event: #{event.title} (ticketed: #{event.is_ticketed})", :green)
      end)
    end
  end
  
  defp create_entertainment_events(_), do: Helpers.log("Entertainment organizer not found", :yellow)
  
  defp create_fundraiser_events(organizer) when not is_nil(organizer) do
    import Ecto.Query
    
    Helpers.log("Creating fundraiser events for #{organizer.name}")
    
    existing_count = Repo.aggregate(
      from(eu in EventUser, 
        join: e in assoc(eu, :event),
        where: eu.user_id == ^organizer.id and 
               eu.role in ["owner", "organizer"] and 
               is_nil(e.deleted_at)),
      :count
    )
    
    if existing_count < 3 do
      events_data = [
        %{
          title: "Charity Gala for Children's Hospital",
          description: """
          Join us for an elegant evening supporting our local children's hospital.
          
          ✨ Evening includes:
          - Cocktail reception
          - Three-course dinner
          - Silent auction
          - Live entertainment
          - Keynote speaker
          
          All proceeds benefit the pediatric wing expansion project.
          """,
          tagline: "An Evening of Giving",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "Individual Ticket",
              price: 150.00,
              quantity: 100,
              description: "Includes dinner and entertainment"
            }
          ]
        },
        %{
          title: "5K Run for Clean Water",
          description: """
          Run or walk to support clean water initiatives worldwide!
          
          🏃 Event features:
          - Chip-timed 5K race
          - Kids fun run (1 mile)
          - Post-race celebration
          - Raffles and prizes
          - T-shirt for all participants
          
          100% of proceeds go to water.org
          """,
          tagline: "Every Step Counts",
          is_ticketed: true,
          ticket_types: [
            %{
              name: "Adult Registration",
              price: 35.00,
              quantity: 300,
              description: "5K race entry with t-shirt"
            }
          ]
        },
        %{
          title: "Community Food Drive & BBQ",
          description: """
          Help us fight hunger in our community!
          
          🍽️ Bring non-perishable food items and enjoy:
          - Free BBQ lunch
          - Live music
          - Kids activities
          - Community resources fair
          
          Suggested donation: 5 canned goods per person
          """,
          tagline: "Feed Our Neighbors",
          is_ticketed: false  # Free community service event
        }
      ]
      
      Enum.each(events_data, fn event_data ->
        ticket_types = Map.get(event_data, :ticket_types, [])
        
        event_params = Map.merge(%{
          title: unique_title(event_data.title),
          description: event_data.description,
          tagline: event_data.tagline,
          status: :confirmed,
          visibility: :public,
          theme: :nature,
          is_virtual: false,
          is_ticketed: event_data.is_ticketed,
          taxation_type: if(event_data.is_ticketed, do: "ticketed_event", else: "ticketless"),
          start_at: Faker.DateTime.forward(Enum.random(10..60)),
          ends_at: Faker.DateTime.forward(Enum.random(61..63)),
          timezone: organizer.timezone || "America/Denver"
        }, Helpers.get_random_image_attrs())
        
        {:ok, event} = Events.create_event_with_organizer(event_params, organizer)
        
        # Create tickets for ticketed events
        if event_data.is_ticketed && ticket_types != [] do
          create_tickets_for_event(event, ticket_types)
        end
        
        Helpers.log("Created fundraiser event: #{event.title} (ticketed: #{event.is_ticketed})", :green)
      end)
    end
  end
  
  defp create_fundraiser_events(_), do: Helpers.log("Fundraiser organizer not found", :yellow)
  
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
          Helpers.log("  → Created ticket: #{ticket.title} ($#{ticket_data.price})", :blue)
        {:error, changeset} ->
          Helpers.error("  → Failed to create ticket: #{inspect(changeset.errors)}")
      end
    end)
  end
  
  defp make_organizers_participate(organizers) do
    import Ecto.Query
    
    Helpers.log("Making organizers participate in other events...")
    
    # Get a sample of existing events (excluding ones they organize)
    all_events = Repo.all(
      from e in EventasaurusApp.Events.Event,
      where: is_nil(e.deleted_at) and e.status == :confirmed,
      limit: 50
    )
    
    Enum.each(organizers, fn organizer ->
      # Get events this organizer doesn't already organize or participate in
      existing_event_ids = Repo.all(
        from eu in EventUser,
        where: eu.user_id == ^organizer.id,
        select: eu.event_id
      )
      
      # Also check event_participants table
      participant_event_ids = Repo.all(
        from ep in EventasaurusApp.Events.EventParticipant,
        where: ep.user_id == ^organizer.id,
        select: ep.event_id
      )
      
      all_connected_events = existing_event_ids ++ participant_event_ids
      
      # Filter out events they're already connected to
      available_events = Enum.filter(all_events, fn event ->
        event.id not in all_connected_events
      end)
      
      # Make them participate in 5-8 random events as "interested" participants
      events_to_join = Enum.take_random(available_events, Enum.random(5..8))
      
      participation_count = Enum.reduce(events_to_join, 0, fn event, acc ->
        case Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: :interested,  # Using interested status instead of accepted
          role: :attendee,
          source: "ticketed_organizer_seeding"
        }) do
          {:ok, _participant} -> acc + 1
          {:error, _reason} -> acc
        end
      end)
      
      if participation_count > 0 do
        Helpers.log("#{organizer.name} is now interested in #{participation_count} events", :green)
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
  DevSeeds.TicketedEventOrganizers.ensure_ticketed_event_organizers()
end