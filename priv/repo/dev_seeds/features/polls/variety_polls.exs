# Enhanced Variety Polls - Phase IV Implementation
# This module creates comprehensive polling scenarios for testing

# Load helpers if running independently
unless Code.ensure_loaded?(DevSeeds.Helpers) do
  Code.require_file("../../support/helpers.exs", __DIR__)
end

defmodule EnhancedVarietyPolls do
  import Ecto.Query
  alias EventasaurusApp.{Repo, Events, Accounts, Groups, Venues}
  alias DevSeeds.Helpers

  IO.puts("📦 EnhancedVarietyPolls module loaded")

  @doc """
  Creates comprehensive polling scenarios including:
  - Multiple polls per event (3 polls)
  - Different poll states (active, completed, draft)
  - Various poll privacy settings
  - Different group sizes and compositions
  """
  def run do
    IO.puts("🚀 EnhancedVarietyPolls.run() called")
    Helpers.section("Creating Phase IV: Enhanced Seed Variety")

    users = get_available_users()
    groups = get_available_groups()
    venues = get_available_venues()

    if length(users) < 10 do
      Helpers.error("Not enough users available. Need at least 10 users.")
      nil
    else
      # Create multi-poll events with different scenarios
      create_triple_poll_conference_event(users, groups, venues)
      create_wedding_planning_event(users, groups, venues)
      create_startup_launch_event(users, groups, venues)
      create_community_festival_event(users, groups, venues)
      create_corporate_retreat_event(users, groups, venues)

      Helpers.success("Enhanced variety polls created successfully!")
    end
  end

  # Triple Poll Conference Event
  defp create_triple_poll_conference_event(users, groups, venues) do
    Helpers.log("→ Creating Tech Conference with 3 polls...")
    
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)
    
    # Create the event with proper image and venue using existing patterns
    event_attrs = Map.merge(%{
      title: "Annual Tech Conference 2025",
      description: "A comprehensive tech conference covering AI, blockchain, and web development trends.",
      start_at: DateTime.add(DateTime.utc_now(), 45 * 24 * 60 * 60), # 45 days from now
      ends_at: DateTime.add(DateTime.utc_now(), 47 * 24 * 60 * 60), # 47 days from now
      timezone: "America/New_York",
      status: "confirmed",
      taxation_type: "ticketed_event",
      is_virtual: false,
      venue_id: venue.id,
      group_id: group.id
    }, Helpers.get_random_image_attrs())

    # Use Events.create_event API instead of factory for proper creation
    event = case Events.create_event(event_attrs) do
      {:ok, event} -> event
      {:error, changeset} ->
        Helpers.error("Failed to create conference event: #{inspect(changeset.errors)}")
        nil
    end
    
    if event do
      # Add multiple participants with different group sizes
      participants = Enum.take_random(users, 15)
      Enum.each(participants, fn user ->
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          status: "confirmed",
          role: "participant"
        })
      end)

      # Poll 1: Conference Track Selection (ACTIVE state)
      create_conference_track_poll(event, organizer)
      
      # Poll 2: Keynote Speaker Preference (COMPLETED state)  
      create_keynote_speaker_poll(event, organizer)
      
      # Poll 3: Workshop Time Slots (DRAFT state)
      create_workshop_time_poll(event, organizer)

      Helpers.success("  ✓ Tech Conference created with 3 polls (active, completed, draft)")
    end
  end

  # Wedding Planning Event
  defp create_wedding_planning_event(users, groups, venues) do
    Helpers.log("→ Creating Wedding Planning with multiple polls...")
    
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)
    
    event_attrs = Map.merge(%{
      title: "Sarah & Mike's Wedding Planning",
      description: "Help us plan our dream wedding! Your input on venue, menu, and music is invaluable.",
      start_at: DateTime.add(DateTime.utc_now(), 120 * 24 * 60 * 60), # 4 months from now
      ends_at: DateTime.add(DateTime.utc_now(), 121 * 24 * 60 * 60),
      timezone: "America/Los_Angeles",
      status: "confirmed",
      taxation_type: "ticketless",
      is_virtual: false,
      venue_id: venue.id,
      group_id: group.id
    }, Helpers.get_random_image_attrs())

    event = case Events.create_event(event_attrs) do
      {:ok, event} -> event
      {:error, changeset} ->
        Helpers.error("Failed to create wedding event: #{inspect(changeset.errors)}")
        nil
    end
    
    if event do
      # Smaller, intimate group
      participants = Enum.take_random(users, 8)
      Enum.each(participants, fn user ->
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          status: "confirmed",
          role: "participant"
        })
      end)

      # Wedding-specific polls with private settings
      create_wedding_menu_poll(event, organizer)
      create_wedding_music_poll(event, organizer)
      create_wedding_photo_poll(event, organizer)

      Helpers.success("  ✓ Wedding Planning created with 3 private polls")
    end
  end

  # Startup Launch Event
  defp create_startup_launch_event(users, groups, venues) do
    Helpers.log("→ Creating Startup Launch with public polls...")
    
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)
    
    event_attrs = Map.merge(%{
      title: "TechStartup Launch Event",
      description: "Join us for the official launch of our revolutionary AI platform. Network, learn, and celebrate!",
      start_at: DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60), # 30 days from now
      ends_at: DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60 + 6 * 60 * 60), # +6 hours
      timezone: "America/New_York",
      status: "confirmed",
      taxation_type: "ticketed_event",
      is_virtual: false,
      venue_id: venue.id,
      group_id: group.id
    }, Helpers.get_random_image_attrs())

    event = case Events.create_event(event_attrs) do
      {:ok, event} -> event
      {:error, changeset} ->
        Helpers.error("Failed to create startup event: #{inspect(changeset.errors)}")
        nil
    end
    
    if event do
      # Large group - startup launch
      participants = Enum.take_random(users, 25)
      Enum.each(participants, fn user ->
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          status: "confirmed",
          role: "participant"
        })
      end)

      # Public polls with different voting systems
      create_startup_demo_poll(event, organizer)
      create_networking_format_poll(event, organizer)
      create_swag_preference_poll(event, organizer)

      Helpers.success("  ✓ Startup Launch created with 3 public polls")
    end
  end

  # Community Festival Event
  defp create_community_festival_event(users, groups, venues) do
    Helpers.log("→ Creating Community Festival with mixed poll states...")
    
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)
    
    event_attrs = Map.merge(%{
      title: "Annual Community Arts Festival",
      description: "Celebrate local talent with music, art, food, and family activities. Help us plan the perfect festival!",
      start_at: DateTime.add(DateTime.utc_now(), 60 * 24 * 60 * 60), # 2 months from now
      ends_at: DateTime.add(DateTime.utc_now(), 62 * 24 * 60 * 60), # 2 day festival
      timezone: "America/Chicago",
      status: "confirmed",
      taxation_type: "ticketless",
      is_virtual: false,
      venue_id: venue.id,
      group_id: group.id
    }, Helpers.get_random_image_attrs())

    event = case Events.create_event(event_attrs) do
      {:ok, event} -> event
      {:error, changeset} ->
        Helpers.error("Failed to create community festival event: #{inspect(changeset.errors)}")
        nil
    end
    
    # Community-sized group
    participants = Enum.take_random(users, 20)
    Enum.each(participants, fn user ->
      Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        status: "confirmed",
        role: "participant"
      })
    end)

    # Community polls with mixed settings
    create_festival_activities_poll(event, organizer)
    create_food_vendors_poll(event, organizer)
    create_volunteer_shifts_poll(event, organizer)

    Helpers.success("  ✓ Community Festival created with mixed poll privacy settings")
  end

  # Corporate Retreat Event  
  defp create_corporate_retreat_event(users, groups, venues) do
    Helpers.log("→ Creating Corporate Retreat with team-building polls...")
    
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)
    
    event_attrs = Map.merge(%{
      title: "Q4 Corporate Team Retreat",
      description: "Strategic planning and team building for Q4. Let's make decisions together on activities and logistics.",
      start_at: DateTime.add(DateTime.utc_now(), 75 * 24 * 60 * 60), # 2.5 months from now
      ends_at: DateTime.add(DateTime.utc_now(), 77 * 24 * 60 * 60), # 3 day retreat
      timezone: "America/Denver",
      status: "confirmed",
      taxation_type: "ticketless",
      is_virtual: false,
      venue_id: venue.id,
      group_id: group.id
    }, Helpers.get_random_image_attrs())

    event = case Events.create_event(event_attrs) do
      {:ok, event} -> event
      {:error, changeset} ->
        Helpers.error("Failed to create corporate retreat event: #{inspect(changeset.errors)}")
        nil
    end
    
    # Corporate team size - only add participants if event was created successfully
    if event do
      participants = Enum.take_random(users, 12)
      Enum.each(participants, fn user ->
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          status: "confirmed",
          role: "participant"
        })
      end)
    end

    # Corporate polls with restricted visibility - only if event was created
    if event do
      create_team_building_poll(event, organizer)
      create_accommodation_poll(event, organizer) 
      create_workshop_topics_poll(event, organizer)
    end

    Helpers.success("  ✓ Corporate Retreat created with 3 member-only polls")
  end

  # Specific poll creation functions - simplified to use the working API pattern

  defp create_conference_track_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Which conference track interests you most?",
      description: "Help us gauge interest for different technical tracks",
      poll_type: "general",
      voting_system: "binary",
      phase: "active",
      auto_finalize: false,
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        # Create poll options
        tracks = [
          %{title: "AI & Machine Learning", description: "Latest developments in artificial intelligence"},
          %{title: "Blockchain & Web3", description: "Decentralized applications and crypto"},
          %{title: "Full-Stack Development", description: "Modern web development frameworks"},
          %{title: "DevOps & Cloud", description: "Infrastructure and deployment strategies"},
          %{title: "Mobile Development", description: "iOS and Android development trends"}
        ]
        
        Enum.each(tracks, fn track ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: track.title,
            description: track.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create conference track poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_keynote_speaker_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Vote for your preferred keynote speaker",
      description: "These industry leaders have confirmed availability",
      poll_type: "custom", 
      voting_system: "ranked",
      phase: "completed",
      finalized_date: DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60), # Completed 7 days ago
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        speakers = [
          %{title: "Dr. Sarah Chen", description: "AI Ethics researcher at Stanford"},
          %{title: "Marcus Rodriguez", description: "CTO of TechCorp, blockchain expert"},
          %{title: "Lisa Park", description: "Founder of DevTools Inc."},
          %{title: "Ahmed Hassan", description: "Principal Engineer at CloudFirst"}
        ]
        
        Enum.each(speakers, fn speaker ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: speaker.title,
            description: speaker.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create keynote speaker poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_workshop_time_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Preferred workshop time slots",
      description: "When would you prefer hands-on workshops?",
      poll_type: "time",
      voting_system: "approval", 
      phase: "draft",
      max_options_per_user: 2,
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        time_slots = [
          %{title: "Morning Session (9-11 AM)", description: "Early morning deep-dive sessions"},
          %{title: "Late Morning (11 AM-1 PM)", description: "Pre-lunch workshop time"},
          %{title: "Afternoon (2-4 PM)", description: "Post-lunch learning sessions"},
          %{title: "Late Afternoon (4-6 PM)", description: "End-of-day practical workshops"}
        ]
        
        Enum.each(time_slots, fn slot ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: slot.title,
            description: slot.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create workshop time poll: #{inspect(changeset.errors)}")
    end
  end

  # Simplified wedding polls
  defp create_wedding_menu_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Wedding Reception Menu",
      description: "Help us choose the perfect menu for our special day",
      poll_type: "custom",
      voting_system: "ranked",
      phase: "active",
      privacy_settings: %{"visibility" => "private"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        menus = [
          %{title: "Mediterranean Feast", description: "Grilled fish, lamb, fresh vegetables, and baklava"},
          %{title: "Classic American", description: "Roasted chicken, beef, mashed potatoes, wedding cake"},
          %{title: "Italian Elegance", description: "Pasta bar, osso buco, tiramisu, wine pairings"},
          %{title: "Fusion Experience", description: "Asian-Western fusion with unique flavor combinations"}
        ]
        
        Enum.each(menus, fn menu ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: menu.title,
            description: menu.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create wedding menu poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_wedding_music_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Reception Music Style",
      description: "What music style should dominate our reception?",
      poll_type: "general",
      voting_system: "binary",
      phase: "active",
      privacy_settings: %{"visibility" => "private"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        styles = [
          %{title: "Classic Rock & Pop", description: "Timeless hits everyone can dance to"},
          %{title: "Jazz & Swing", description: "Elegant and sophisticated atmosphere"},
          %{title: "Modern Top 40", description: "Current hits and dance music"},
          %{title: "Mixed Decades", description: "Something for every generation"}
        ]
        
        Enum.each(styles, fn style ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: style.title,
            description: style.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create wedding music poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_wedding_photo_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Photo Session Locations",
      description: "Where should we do our couple photo session?",
      poll_type: "places",
      voting_system: "approval",
      phase: "draft",
      max_options_per_user: 2,
      privacy_settings: %{"visibility" => "private"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        locations = [
          %{title: "Beach Sunset", description: "Golden hour photos by the ocean"},
          %{title: "Urban Downtown", description: "City skyline and architecture"},
          %{title: "Garden/Park", description: "Natural greenery and flowers"},
          %{title: "Historic Venue", description: "Classic architecture and charm"}
        ]
        
        Enum.each(locations, fn location ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: location.title,
            description: location.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create wedding photo poll: #{inspect(changeset.errors)}")
    end
  end

  # Additional simplified poll creation methods
  defp create_startup_demo_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Most Exciting Demo Feature",
      description: "Which feature demo are you most excited to see?",
      poll_type: "custom",
      voting_system: "star",
      phase: "active",
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        features = [
          %{title: "AI-Powered Analytics", description: "Real-time data insights and predictions"},
          %{title: "Seamless Integrations", description: "Connect with 50+ popular tools"},
          %{title: "Mobile App Experience", description: "Native iOS and Android applications"},
          %{title: "Enterprise Security", description: "SOC2 compliance and data protection"}
        ]
        
        Enum.each(features, fn feature ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: feature.title,
            description: feature.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create startup demo poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_networking_format_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Networking Format Preference",
      description: "How would you prefer to network at our launch event?",
      poll_type: "general",
      voting_system: "binary",
      phase: "active",
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        formats = [
          %{title: "Speed Networking", description: "Structured 5-minute conversations"},
          %{title: "Open Networking", description: "Free-form mingling and conversations"},
          %{title: "Topic Tables", description: "Sit at tables based on interests"},
          %{title: "Industry Meetups", description: "Group by industry/role"}
        ]
        
        Enum.each(formats, fn format ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: format.title,
            description: format.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create networking format poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_swag_preference_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Preferred Event Swag",
      description: "What swag would you actually use? (Poll closed - results final)",
      poll_type: "custom",
      voting_system: "approval", 
      phase: "completed",
      max_options_per_user: 3,
      finalized_date: DateTime.add(DateTime.utc_now(), -14 * 24 * 60 * 60), # Completed 2 weeks ago
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        swag_items = [
          %{title: "Premium T-Shirt", description: "High-quality cotton tee with logo"},
          %{title: "Insulated Coffee Mug", description: "Perfect for your morning coffee"},
          %{title: "Wireless Phone Charger", description: "Practical tech accessory"},
          %{title: "Laptop Sticker Pack", description: "Show off your tech stack"},
          %{title: "Notebook & Pen Set", description: "Classic professional combo"}
        ]
        
        Enum.each(swag_items, fn item ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: item.title,
            description: item.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create swag preference poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_festival_activities_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Festival Activity Priorities",
      description: "Help us prioritize which activities to include",
      poll_type: "custom",
      voting_system: "ranked",
      phase: "active",
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        activities = [
          %{title: "Live Music Stage", description: "Local bands and performers"},
          %{title: "Art Gallery Tent", description: "Local artists displaying work"},
          %{title: "Kids Activity Zone", description: "Family-friendly games and crafts"},
          %{title: "Food Truck Row", description: "Diverse local food vendors"},
          %{title: "Community Garden Tour", description: "Educational garden walkthrough"}
        ]
        
        Enum.each(activities, fn activity ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: activity.title,
            description: activity.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create festival activities poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_food_vendors_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Food Vendor Selection",
      description: "Voting completed - these vendors are confirmed!",
      poll_type: "places",
      voting_system: "approval",
      phase: "completed",
      max_options_per_user: 4,
      finalized_date: DateTime.add(DateTime.utc_now(), -21 * 24 * 60 * 60), # Completed 3 weeks ago
      privacy_settings: %{"visibility" => "members_only"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        vendors = [
          %{title: "Mario's Pizza Truck", description: "Wood-fired pizza with local ingredients"},
          %{title: "Seoul Kitchen", description: "Korean BBQ and kimchi tacos"},
          %{title: "Sweet Treats Bakery", description: "Artisan desserts and coffee"},
          %{title: "Green Valley Farm Stand", description: "Fresh vegetables and smoothies"},
          %{title: "BBQ Brothers", description: "Smoked meats and classic sides"}
        ]
        
        Enum.each(vendors, fn vendor ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: vendor.title,
            description: vendor.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create food vendors poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_volunteer_shifts_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Volunteer Shift Availability",
      description: "Sign up for volunteer shifts (draft - not yet open)",
      poll_type: "time",
      voting_system: "approval",
      phase: "draft",
      max_options_per_user: 3,
      privacy_settings: %{"visibility" => "public"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        shifts = [
          %{title: "Setup Crew (Friday 6-10 PM)", description: "Help set up stages and booths"},
          %{title: "Saturday Morning (8 AM-12 PM)", description: "Festival opening and crowd control"},
          %{title: "Saturday Afternoon (12-6 PM)", description: "Peak hours support"},
          %{title: "Saturday Evening (6-10 PM)", description: "Evening activities and cleanup prep"},
          %{title: "Teardown (Sunday 8 AM-12 PM)", description: "Post-festival cleanup"}
        ]
        
        Enum.each(shifts, fn shift ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: shift.title,
            description: shift.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create volunteer shifts poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_team_building_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Team Building Activity Preference",
      description: "What team building activities would be most valuable?",
      poll_type: "general",
      voting_system: "ranked",
      phase: "active",
      privacy_settings: %{"visibility" => "members_only"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        activities = [
          %{title: "Outdoor Adventure Course", description: "Rope climbing, obstacles, teamwork challenges"},
          %{title: "Escape Room Challenge", description: "Problem-solving under pressure"},
          %{title: "Cooking Class Competition", description: "Collaborative meal preparation"},
          %{title: "Innovation Workshop", description: "Brainstorming and creative problem solving"},
          %{title: "Volunteer Service Project", description: "Give back to the local community"}
        ]
        
        Enum.each(activities, fn activity ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: activity.title,
            description: activity.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create team building poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_accommodation_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Accommodation Preferences",
      description: "Help us arrange the best lodging for everyone",
      poll_type: "venue",
      voting_system: "binary", 
      phase: "active",
      privacy_settings: %{"visibility" => "members_only"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        accommodations = [
          %{title: "Resort Hotel", description: "All-inclusive with spa and amenities"},
          %{title: "Mountain Lodge", description: "Rustic charm with hiking access"},
          %{title: "Boutique Hotel", description: "Unique local character and style"},
          %{title: "Corporate Retreat Center", description: "Meeting rooms and business facilities"}
        ]
        
        Enum.each(accommodations, fn accommodation ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: accommodation.title,
            description: accommodation.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create accommodation poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_workshop_topics_poll(event, organizer) do
    case Events.create_poll(%{
      event_id: event.id,
      title: "Professional Development Workshop Topics",
      description: "What skills would be most valuable to develop? (Planning phase)",
      poll_type: "general",
      voting_system: "approval",
      phase: "draft",
      max_options_per_user: 3,
      privacy_settings: %{"visibility" => "members_only"},
      created_by_id: organizer.id
    }) do
      {:ok, poll} ->
        topics = [
          %{title: "Leadership & Management", description: "Leading teams and managing projects"},
          %{title: "Communication Skills", description: "Presentation and interpersonal skills"},
          %{title: "Strategic Planning", description: "Long-term thinking and goal setting"},
          %{title: "Innovation & Creativity", description: "Design thinking and creative problem solving"},
          %{title: "Data Analysis & Insights", description: "Making data-driven decisions"}
        ]
        
        Enum.each(topics, fn topic ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: topic.title,
            description: topic.description
          })
        end)

      {:error, changeset} ->
        Helpers.error("Failed to create workshop topics poll: #{inspect(changeset.errors)}")
    end
  end

  # Helper functions to get existing data
  defp get_available_users do
    Repo.all(from u in Accounts.User, limit: 50)
  end

  defp get_available_groups do
    Repo.all(from g in Groups.Group, where: is_nil(g.deleted_at), limit: 10)
  end

  defp get_available_venues do
    Repo.all(from v in Venues.Venue, limit: 20)
  end
end

# Run the enhanced variety polls seeding
EnhancedVarietyPolls.run()