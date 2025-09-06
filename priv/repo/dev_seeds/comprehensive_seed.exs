# Comprehensive Development Seeding Script
# Creates 100+ events in various states as per issue #812

alias EventasaurusApp.{Repo, Events, Groups, Accounts}
import Ecto.Query
require Logger

defmodule ComprehensiveSeed do
  def run do
    Logger.info("Starting comprehensive event seeding...")
    
    users = Repo.all(from u in Accounts.User, limit: 10)
    groups = Repo.all(Groups.Group)
    
    if length(users) < 5 do
      Logger.error("Not enough users! Please run user seeding first.")
      exit(:no_users)
    end
    
    # Ensure we have some groups
    groups = if length(groups) < 3 do
      create_groups(users)
    else
      groups
    end
    
    # Create 100+ events with variety
    create_diverse_events(users, groups)
    
    Logger.info("Comprehensive seeding complete!")
  end
  
  defp create_groups(users) do
    Logger.info("Creating groups...")
    
    group_configs = [
      %{name: "Weekend Warriors", description: "For weekend adventurers", size: :large},
      %{name: "Book Club Central", description: "Monthly book discussions", size: :medium},
      %{name: "Tech Talks", description: "Technology meetups and talks", size: :large},
      %{name: "Foodies Unite", description: "Restaurant and cooking events", size: :medium},
      %{name: "Fitness Fanatics", description: "Sports and fitness activities", size: :small},
      %{name: "Movie Nights", description: "Film screenings and discussions", size: :medium},
      %{name: "Game Night Crew", description: "Board games and video games", size: :small},
      %{name: "Art Collective", description: "Creative arts and crafts", size: :medium},
      %{name: "Music Lovers", description: "Concerts and jam sessions", size: :large},
      %{name: "Hiking Club", description: "Trail adventures", size: :medium},
      %{name: "Photography Walk", description: "Photo walks and workshops", size: :small},
      %{name: "Startup Founders", description: "Entrepreneurship events", size: :medium},
      %{name: "Language Exchange", description: "Practice foreign languages", size: :large},
      %{name: "Volunteer Corps", description: "Community service events", size: :medium},
      %{name: "Wine Tasting Society", description: "Wine appreciation events", size: :small}
    ]
    
    Enum.map(group_configs, fn config ->
      creator = Enum.random(users)
      
      # Create diverse privacy settings with equal distribution
      visibility = Enum.random(["public", "unlisted", "private"])
      join_policy_pool =
        case visibility do
          "private" -> ["request", "invite_only"]  # Private groups cannot be open
          _ -> ["open", "request", "invite_only"]
        end
      
      # Use production API that handles slug generation automatically
      {:ok, group} = Groups.create_group_with_creator(%{
        "name" => config.name,
        "description" => config.description,
        "visibility" => visibility,
        "join_policy" => Enum.random(join_policy_pool)
      }, creator)
      
      # Add members based on size
      member_count = case config.size do
        :small -> 3..5
        :medium -> 6..12  
        :large -> 13..25
      end |> Enum.random()
      
      users
      |> Enum.take_random(member_count)
      |> Enum.each(fn user ->
        role = if user.id == creator.id, do: "owner", else: Enum.random(["member", "member", "admin"])
        Groups.add_user_to_group(group, user, role)
      end)
      
      Logger.info("Created group: #{group.name} with #{member_count} members")
      group
    end)
  end
  
  defp create_diverse_events(users, groups) do
    Logger.info("Creating 120 diverse events with Phase I & II enhancements...")
    
    # Phase II: PRE-CREATE VENUE POOL (key lesson learned!)
    Logger.info("Phase II: Pre-creating venue pool before events...")
    venue_pool = create_venue_pool()
    Logger.info("Created venue pool with #{length(venue_pool)} venues")
    
    event_templates = [
      # Past events (30)
      %{time_offset: -60, status: "confirmed", title_prefix: "Past Conference", participant_range: 5..20},
      %{time_offset: -45, status: "confirmed", title_prefix: "Completed Workshop", participant_range: 3..10},
      %{time_offset: -30, status: "cancelled", title_prefix: "Cancelled Meetup", participant_range: 0..5},
      %{time_offset: -20, status: "confirmed", title_prefix: "Last Month's Party", participant_range: 10..30},
      %{time_offset: -15, status: "confirmed", title_prefix: "Previous Game Night", participant_range: 4..8},
      
      # Current/Recent events (20)
      %{time_offset: -7, status: "confirmed", title_prefix: "Last Week's Talk", participant_range: 8..15},
      %{time_offset: -3, status: "confirmed", title_prefix: "Recent Dinner", participant_range: 4..12},
      %{time_offset: -1, status: "confirmed", title_prefix: "Yesterday's Hike", participant_range: 3..8},
      %{time_offset: 0, status: "confirmed", title_prefix: "Today's Workshop", participant_range: 5..15},
      %{time_offset: 1, status: "confirmed", title_prefix: "Tomorrow's Meetup", participant_range: 6..20},
      
      # Future events (50+) - Now with Phase I polling events
      %{time_offset: 3, status: "confirmed", title_prefix: "Weekend Adventure", participant_range: 4..12},
      %{time_offset: 7, status: "draft", title_prefix: "Draft Planning Session", participant_range: 0..0},
      %{time_offset: 10, status: "polling", title_prefix: "Movie Night Planning", participant_range: 2..8, phase_1: true},
      %{time_offset: 14, status: "confirmed", title_prefix: "Upcoming Conference", participant_range: 15..50},
      %{time_offset: 21, status: "threshold", title_prefix: "Minimum Attendees Event", participant_range: 3..6},
      %{time_offset: 30, status: "confirmed", title_prefix: "Next Month's Gathering", participant_range: 8..25},
      %{time_offset: 45, status: "polling", title_prefix: "Cinema Club Planning", participant_range: 3..8, phase_1: true},
      %{time_offset: 60, status: "confirmed", title_prefix: "Summer Festival", participant_range: 20..100},
      %{time_offset: 90, status: "cancelled", title_prefix: "Cancelled Future Event", participant_range: 0..0},
    ]
    
    event_types = [
      "Workshop", "Conference", "Meetup", "Party", "Dinner", "Lunch",
      "Game Night", "Movie Night", "Hike", "Concert", "Talk", "Class",
      "Festival", "Retreat", "Hackathon", "Tournament", "Exhibition",
      "Networking", "Fundraiser", "Launch Party"
    ]
    
    # Create 120 events with good variety
    created_events = Enum.map(1..120, fn i ->
      template = Enum.random(event_templates)
      event_type = Enum.random(event_types)
      organizer = Enum.random(users)
      group = if rem(i, 3) == 0 && length(groups) > 0, do: Enum.random(groups), else: nil
      
      # Determine visibility
      visibility = Enum.random(["public", "public", "public", "private", "unlisted"])
      
      # Phase II: Determine if event should be physical (40% chance)
      # But avoid physical for certain event types
      physical_incompatible = template.status in ["draft", "cancelled"] 
      should_be_physical = not physical_incompatible and :rand.uniform(100) <= 40 and length(venue_pool) > 0
      venue = if should_be_physical, do: Enum.random(venue_pool), else: nil
      
      # DEBUG: Log venue assignment
      if rem(i, 10) == 1 do  # Log every 10th event
        Logger.info("DEBUG Event ##{i}: status=#{template.status}, physical_incompatible=#{physical_incompatible}, venue_pool_length=#{length(venue_pool)}, should_be_physical=#{should_be_physical}, venue=#{if venue, do: venue.name, else: "nil"}")
      end
      
      # Build event title with variety
      title_parts = [
        template.title_prefix,
        "-",
        event_type,
        if(rem(i, 5) == 0, do: "Special", else: nil),
        if(rem(i, 7) == 0, do: "Annual", else: nil)
      ] |> Enum.filter(&(&1)) |> Enum.join(" ")
      
      event_params = %{
        title: "#{title_parts} ##{i}",
        description: generate_description(event_type),
        # Remove manual slug generation - let the system handle it automatically
        start_at: Timex.shift(DateTime.utc_now(), days: template.time_offset, hours: :rand.uniform(12)),
        ends_at: if(rem(i, 3) == 0, do: Timex.shift(DateTime.utc_now(), days: template.time_offset, hours: :rand.uniform(12) + 2), else: nil),
        timezone: Enum.random(["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo"]),
        visibility: visibility,
        status: template.status,
        group_id: group && group.id,
        # Phase II: Assign venue from pre-created pool
        is_virtual: venue == nil,
        venue_id: venue && venue.id,
        virtual_venue_url: if(venue == nil, do: "https://zoom.us/j/#{:rand.uniform(999999999)}", else: nil),
        threshold_count: if(template.status == "threshold", do: Enum.random(5..15), else: nil),
        polling_deadline: if(template.status == "polling", do: Timex.shift(DateTime.utc_now(), days: template.time_offset - 3), else: nil)
      }
      
      case Events.create_event(event_params) do
        {:ok, event} ->
          # Add organizer
          Events.add_user_to_event(event, organizer, "organizer")
          
          # Add participants based on template range
          if template.participant_range != 0..0 do
            participant_count = Enum.random(template.participant_range)
            participants = users |> Enum.reject(&(&1.id == organizer.id)) |> Enum.take_random(min(participant_count, length(users) - 1))
            
            Enum.each(participants, fn participant ->
              # Use the correct function to add participants
              Events.create_event_participant(%{
                event_id: event.id,
                user_id: participant.id,
                status: Enum.random(["confirmed", "confirmed", "confirmed", "maybe", "declined"])
              })
            end)
          end
          
          # Phase I: Add polling functionality for polling events
          if template.status == "polling" && Map.get(template, :phase_1, false) do
            create_phase_1_polls(event, organizer)
          end
          
          if rem(i, 10) == 0 do
            Logger.info("Created #{i}/120 events...")
          end
          
          event
          
        {:error, changeset} ->
          Logger.error("Failed to create event: #{inspect(changeset.errors)}")
          nil
      end
    end)
    |> Enum.filter(&(&1))
    
    Logger.info("Created #{length(created_events)} events successfully!")
  end
  
  defp generate_description(event_type) do
    intros = [
      "Join us for an amazing",
      "Don't miss this incredible", 
      "Be part of our exciting",
      "Experience the best",
      "Come enjoy our"
    ]
    
    middles = [
      "where we'll explore",
      "featuring special guests and",
      "with opportunities for",
      "including hands-on",
      "showcasing the latest in"
    ]
    
    endings = [
      "networking and fun!",
      "learning and growth.",
      "community building.",
      "skill development.",
      "entertainment and relaxation."
    ]
    
    "#{Enum.random(intros)} #{event_type} #{Enum.random(middles)} #{Enum.random(endings)} #{Faker.Lorem.paragraph(2..4)}"
  end
  
  # Phase II: Pre-create venue pool to avoid Google API rate limits
  defp create_venue_pool do
    Logger.info("Creating venue pool (slowly to avoid API rate limits)...")
    alias EventasaurusApp.Venues
    alias EventasaurusWeb.Services.GooglePlaces.TextSearch
    
    venues = []
    
    # Create 8 venues total (4 restaurants, 4 theaters) with delays
    restaurant_venues = create_restaurant_venues(4)
    Process.sleep(2000) # 2 second delay between venue types
    
    theater_venues = create_theater_venues(4)
    
    all_venues = restaurant_venues ++ theater_venues
    Logger.info("Venue pool created: #{length(all_venues)} venues")
    all_venues
  end
  
  defp create_restaurant_venues(count) do
    Logger.info("Creating #{count} restaurant venues...")
    alias EventasaurusApp.Venues
    alias EventasaurusWeb.Services.GooglePlaces.TextSearch
    
    # First try Google Places API for real data
    google_venues = case TextSearch.search("restaurant", %{
      type: "restaurant", 
      location: {37.7749, -122.4194}, # San Francisco
      radius: 5000
    }) do
      {:ok, venues} when length(venues) >= count ->
        Logger.info("Using Google Places restaurant data")
        venues |> Enum.take(count)
      _ ->
        Logger.info("Google Places unavailable, using fallback restaurant data")
        []
    end
    
    # Create venues with delay to avoid rate limits
    Enum.with_index(google_venues)
    |> Enum.map(fn {venue_data, index} ->
      if index > 0, do: Process.sleep(1500) # 1.5s delay between venues
      
      venue_params = %{
        name: venue_data["name"],
        address: venue_data["formatted_address"] || venue_data["vicinity"] || "San Francisco, CA",
        city: extract_city_from_address(venue_data) || "San Francisco",
        state: extract_state_from_address(venue_data) || "CA",
        country: extract_country_from_address(venue_data) || "United States",
        latitude: get_in(venue_data, ["geometry", "location", "lat"]) || 37.7749,
        longitude: get_in(venue_data, ["geometry", "location", "lng"]) || -122.4194,
        venue_type: "venue"
      }
      
      case Venues.create_venue(venue_params) do
        {:ok, venue} -> 
          Logger.info("Created restaurant venue: #{venue.name}")
          venue
        {:error, reason} -> 
          Logger.error("Failed to create venue: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(&(&1)) # Remove nils
    |> Kernel.++(create_fallback_restaurants(count - length(google_venues))) # Fill remaining with fallbacks
    |> Enum.take(count)
  end
  
  defp create_theater_venues(count) do
    Logger.info("Creating #{count} theater venues...")
    alias EventasaurusApp.Venues
    alias EventasaurusWeb.Services.GooglePlaces.TextSearch
    
    # Try Google Places API for theaters
    google_venues = case TextSearch.search("movie theater", %{
      type: "movie_theater",
      location: {37.7749, -122.4194}, # San Francisco
      radius: 5000
    }) do
      {:ok, venues} when length(venues) >= count ->
        Logger.info("Using Google Places theater data")
        venues |> Enum.take(count)
      _ ->
        Logger.info("Google Places unavailable, using fallback theater data") 
        []
    end
    
    # Create venues with delay to avoid rate limits
    Enum.with_index(google_venues)
    |> Enum.map(fn {venue_data, index} ->
      if index > 0, do: Process.sleep(1500) # 1.5s delay between venues
      
      venue_params = %{
        name: venue_data["name"],
        address: venue_data["formatted_address"] || venue_data["vicinity"] || "San Francisco, CA",
        city: extract_city_from_address(venue_data) || "San Francisco",
        state: extract_state_from_address(venue_data) || "CA", 
        country: extract_country_from_address(venue_data) || "United States",
        latitude: get_in(venue_data, ["geometry", "location", "lat"]) || 37.7849,
        longitude: get_in(venue_data, ["geometry", "location", "lng"]) || -122.4094,
        venue_type: "venue"
      }
      
      case Venues.create_venue(venue_params) do
        {:ok, venue} -> 
          Logger.info("Created theater venue: #{venue.name}")
          venue
        {:error, reason} -> 
          Logger.error("Failed to create venue: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(&(&1)) # Remove nils
    |> Kernel.++(create_fallback_theaters(count - length(google_venues))) # Fill remaining with fallbacks
    |> Enum.take(count)
  end
  
  defp create_fallback_restaurants(count) do
    Logger.info("Creating #{count} fallback restaurant venues...")
    alias EventasaurusApp.Venues
    
    fallback_restaurants = [
      %{name: "Luigi's Italian Kitchen", address: "123 Market Street, San Francisco, CA 94103", lat: 37.7849, lng: -122.4094},
      %{name: "Sakura Sushi Bar", address: "456 Mission Street, San Francisco, CA 94105", lat: 37.7749, lng: -122.4194},
      %{name: "El Mariachi Cantina", address: "789 Valencia Street, San Francisco, CA 94110", lat: 37.7599, lng: -122.4213},
      %{name: "The Garden Restaurant", address: "321 Union Square, San Francisco, CA 94108", lat: 37.7879, lng: -122.4074}
    ]
    
    fallback_restaurants
    |> Enum.take(count)
    |> Enum.with_index()
    |> Enum.map(fn {restaurant, index} ->
      if index > 0, do: Process.sleep(500) # Brief delay for fallbacks
      
      venue_params = %{
        name: restaurant.name,
        address: restaurant.address,
        city: "San Francisco",
        state: "CA",
        country: "United States", 
        latitude: restaurant.lat,
        longitude: restaurant.lng,
        venue_type: "venue"
      }
      
      case Venues.create_venue(venue_params) do
        {:ok, venue} -> 
          Logger.info("Created fallback restaurant: #{venue.name}")
          venue
        {:error, reason} -> 
          Logger.error("Failed to create fallback restaurant: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(&(&1)) # Remove nils
  end
  
  defp create_fallback_theaters(count) do
    Logger.info("Creating #{count} fallback theater venues...")
    alias EventasaurusApp.Venues
    
    fallback_theaters = [
      %{name: "AMC Theater Downtown", address: "987 Powell Street, San Francisco, CA 94102", lat: 37.7849, lng: -122.4094},
      %{name: "Century Theaters SF", address: "654 Geary Boulevard, San Francisco, CA 94102", lat: 37.7866, lng: -122.4196},
      %{name: "Landmark Cinema", address: "432 Castro Street, San Francisco, CA 94114", lat: 37.7609, lng: -122.4350},
      %{name: "Roxie Theater", address: "876 16th Street, San Francisco, CA 94114", lat: 37.7656, lng: -122.4180}
    ]
    
    fallback_theaters
    |> Enum.take(count)
    |> Enum.with_index()
    |> Enum.map(fn {theater, index} ->
      if index > 0, do: Process.sleep(500) # Brief delay for fallbacks
      
      venue_params = %{
        name: theater.name,
        address: theater.address,
        city: "San Francisco",
        state: "CA", 
        country: "United States",
        latitude: theater.lat,
        longitude: theater.lng,
        venue_type: "venue"
      }
      
      case Venues.create_venue(venue_params) do
        {:ok, venue} -> 
          Logger.info("Created fallback theater: #{venue.name}")
          venue
        {:error, reason} -> 
          Logger.error("Failed to create fallback theater: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(&(&1)) # Remove nils
  end
  
  # Google Places address extraction helpers
  defp extract_city_from_address(venue_data) do
    address_components = venue_data["address_components"] || []
    city_component = Enum.find(address_components, fn component ->
      types = component["types"] || []
      "locality" in types or "administrative_area_level_2" in types
    end)
    
    case city_component do
      %{"long_name" => city} -> city
      _ -> nil
    end
  end
  
  defp extract_state_from_address(venue_data) do
    address_components = venue_data["address_components"] || []
    state_component = Enum.find(address_components, fn component ->
      types = component["types"] || []
      "administrative_area_level_1" in types
    end)
    
    case state_component do
      %{"short_name" => state} -> state
      _ -> nil
    end
  end
  
  defp extract_country_from_address(venue_data) do
    address_components = venue_data["address_components"] || []
    country_component = Enum.find(address_components, fn component ->
      types = component["types"] || []
      "country" in types
    end)
    
    case country_component do
      %{"long_name" => country} -> country
      _ -> "United States"
    end
  end
  
  # Phase I: Create date + movie star rating polls
  defp create_phase_1_polls(event, organizer) do
    Logger.info("Adding Phase I polls to polling event: #{event.title}")
    
    # Load curated movie data
    Code.require_file("curated_data.exs", __DIR__)
    
    # Create date poll
    create_date_poll_for_event(event, organizer)
    
    # Create movie star rating poll
    create_movie_star_poll_for_event(event, organizer)
  end
  
  defp create_date_poll_for_event(event, organizer) do
    # Generate 3-4 future date options
    base_date = event.start_at
    date_options = [
      DateTime.add(base_date, -2 * 24 * 60 * 60, :second),
      base_date,
      DateTime.add(base_date, 1 * 24 * 60 * 60, :second),
      DateTime.add(base_date, 3 * 24 * 60 * 60, :second)
    ]
    |> Enum.map(&Calendar.strftime(&1, "%A, %B %-d at %-I:%M %p"))
    
    poll_params = %{
      event_id: event.id,
      title: "What date works best for everyone?",
      description: "Vote for your preferred event date",
      poll_type: "date_selection",
      voting_system: "binary",
      created_by_id: organizer.id,
      voting_deadline: event.polling_deadline
    }
    
    case Events.create_poll(poll_params) do
      {:ok, poll} ->
        # Use proper phase transition
        {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
        
        # Create date options
        Enum.each(date_options, fn option ->
          {:ok, _option} = Events.create_poll_option(%{
            poll_id: poll.id,
            title: option,
            description: "Proposed date option",
            suggested_by_id: organizer.id,
            metadata: %{"date_type" => "single_date"}
          })
        end)
        
        Logger.info("Created date poll for #{event.title}")
        
      {:error, reason} ->
        Logger.error("Failed to create date poll: #{inspect(reason)}")
    end
  end
  
  defp create_movie_star_poll_for_event(event, organizer) do
    # Get 5 random movies from curated data
    movies = DevSeeds.CuratedData.movies() |> Enum.take_random(5)
    
    poll_params = %{
      event_id: event.id,
      title: "Rate these movie options (5 stars = most excited to watch)",
      description: "Rate each movie from 1-5 stars based on how excited you are to watch it",
      poll_type: "movie",
      voting_system: "star",
      created_by_id: organizer.id,
      voting_deadline: event.polling_deadline
    }
    
    case Events.create_poll(poll_params) do
      {:ok, poll} ->
        # Use proper phase transition
        {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
        
        # Create movie options
        Enum.each(movies, fn movie ->
          {:ok, _option} = Events.create_poll_option(%{
            poll_id: poll.id,
            title: movie.title,
            description: "#{movie.year} • #{movie.genre} • ★#{movie.rating}/10\n#{movie.description}",
            suggested_by_id: organizer.id,
            metadata: %{
              "year" => movie.year,
              "genre" => movie.genre,
              "tmdb_rating" => movie.rating,
              "tmdb_id" => movie.tmdb_id
            }
          })
        end)
        
        Logger.info("Created movie star rating poll for #{event.title}")
        
      {:error, reason} ->
        Logger.error("Failed to create movie poll: #{inspect(reason)}")
    end
  end
end

# Run the comprehensive seeding
ComprehensiveSeed.run()