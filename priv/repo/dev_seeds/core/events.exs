defmodule DevSeeds.Events do
  @moduledoc """
  Event seeding module for development environment.
  Creates events in various states with realistic data.
  """
  
  alias DevSeeds.Helpers
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventUser
  
  @doc """
  Seeds events with various states and configurations.
  
  Options:
    - count: Total number of events to create (default: 100)
    - users: List of users to assign as organizers/participants
    - groups: List of groups to associate with events
  """
  def seed(opts \\ []) do
    # Load curated data for realistic content
    Code.require_file("../support/curated_data.exs", __DIR__)
    
    count = Keyword.get(opts, :count, 100)
    users = Keyword.get(opts, :users, [])
    groups = Keyword.get(opts, :groups, [])
    
    if length(users) < 5 do
      Helpers.error("Need at least 5 users to create realistic events")
      []
    else
      total_count = if is_map(count) do
        (count[:past] || 0) + (count[:upcoming] || 0) + (count[:future] || 0)
      else
        count
      end
      Helpers.section("Creating #{total_count} Events")
      
      # Phase II: Create venue pool for physical events
      Helpers.section("Creating Venue Pool")
      venue_pool = create_venue_pool()
      Helpers.success("Created venue pool with #{length(venue_pool)} venues")
      
      # Create events with proper time distribution
      events = create_time_distributed_events(count, users, groups, venue_pool)
      
      # Add participants to events
      add_participants_to_events(events, users)
      
      Helpers.success("Created #{length(events)} events")
      events
    end
  end
  
  defp create_time_distributed_events(count, users, groups, venue_pool) do
    # Handle both map and integer count formats
    {past_count, upcoming_count, future_count} = if is_map(count) do
      {count[:past] || 0, count[:upcoming] || 0, count[:future] || 0}
    else
      # Distribution as specified in issue
      past = round(count * 0.30)      # 30% past events
      upcoming = round(count * 0.50)   # 50% current/upcoming
      future = round(count * 0.20)     # 20% far future
      {past, upcoming, future}
    end
    
    # Create event categories in parallel (they're independent)
    Helpers.log("Creating events in parallel (past/upcoming/future)...")

    past_task = Task.async(fn ->
      create_past_events(past_count, users, groups, venue_pool)
    end)

    upcoming_task = Task.async(fn ->
      create_upcoming_events(upcoming_count, users, groups, venue_pool)
    end)

    future_task = Task.async(fn ->
      create_future_events(future_count, users, groups, venue_pool)
    end)

    # Wait for all three to complete
    [past_events, upcoming_events, future_events] =
      Task.await_many([past_task, upcoming_task, future_task], :infinity)

    Helpers.success("✓ Created #{length(past_events)} past, #{length(upcoming_events)} upcoming, #{length(future_events)} future events")

    past_events ++ upcoming_events ++ future_events
  end
  
  defp create_past_events(count, users, groups, venue_pool) do
    Helpers.log("Creating #{count} past events...")

    Enum.map(1..count, fn _ ->
      # Past events (1-365 days ago)
      # Use explicit date calculation instead of Faker to ensure accuracy
      now = DateTime.utc_now() |> truncate_datetime()
      days_ago = Enum.random(1..365)
      start_at = DateTime.add(now, -days_ago * 24 * 60 * 60, :second) |> truncate_datetime()
      duration_hours = Enum.random([2, 3, 4, 6, 8, 24, 48]) # Various durations
      ends_at = DateTime.add(start_at, duration_hours * 3600, :second) |> truncate_datetime()
      
      title = generate_event_title()
      taxation_attrs = random_taxation_and_ticketing()
      event = create_event(Map.merge(%{
        title: title,
        description: DevSeeds.CuratedData.generate_event_description(title),
        tagline: DevSeeds.CuratedData.random_tagline(),
        start_at: start_at,
        ends_at: ends_at,
        status: Enum.random([:confirmed, :confirmed, :canceled]), # Most are confirmed
        visibility: random_visibility(),
        theme: random_theme(),
        is_virtual: Enum.random([false, false, false, true]), # 25% virtual
        timezone: Faker.Address.time_zone()
      }, taxation_attrs), users, groups, venue_pool)
      
      # Mark some as soft-deleted
      if Enum.random(1..20) == 1 do # 5% deleted
        event
        |> Ecto.Changeset.change(%{
          deleted_at: Faker.DateTime.forward(1),
          deleted_by_user_id: Enum.random(users).id
        })
        |> Repo.update!()
      else
        event
      end
    end)
  end
  
  defp create_upcoming_events(count, users, groups, venue_pool) do
    Helpers.log("Creating #{count} upcoming events...")

    Enum.map(1..count, fn _ ->
      # Upcoming events (today to 60 days)
      # Use explicit date calculation instead of Faker to ensure accuracy
      now = DateTime.utc_now() |> truncate_datetime()
      days_forward = Enum.random(0..60)
      start_at = DateTime.add(now, days_forward * 24 * 60 * 60, :second) |> truncate_datetime()
      duration_hours = Enum.random([2, 3, 4, 6, 8])
      ends_at = DateTime.add(start_at, duration_hours * 3600, :second) |> truncate_datetime()

      # For polling events, we need enough time for the deadline to be:
      # 1. Before the event start date
      # 2. In the future (at least 1 day from now)
      # So only allow polling status if event is at least 8 days away
      days_until_event = days_forward  # We know exactly how many days forward

      status = if days_until_event >= 8 do
        Enum.random([
          :draft,
          :polling, :polling,  # More polling
          :confirmed, :confirmed, :confirmed, :confirmed  # Most are confirmed
        ])
      else
        # Not enough time for polling - skip polling status
        Enum.random([:draft, :confirmed, :confirmed, :confirmed, :confirmed])
      end

      # Polling deadline must be BEFORE the event AND in the FUTURE
      polling_deadline = if status == :polling do
        # Set deadline between 1 day from now and 1 day before the event
        min_days_from_now = 1
        max_days_from_now = days_until_event - 1  # At least 1 day before event
        days_from_now = Enum.random(min_days_from_now..max_days_from_now)
        DateTime.add(now, days_from_now * 24 * 60 * 60, :second) |> truncate_datetime()
      else
        nil
      end

      title = generate_event_title()
      taxation_attrs = random_taxation_and_ticketing()
      create_event(Map.merge(%{
        title: title,
        description: DevSeeds.CuratedData.generate_event_description(title),
        tagline: DevSeeds.CuratedData.random_tagline(),
        start_at: start_at,
        ends_at: ends_at,
        status: status,
        polling_deadline: polling_deadline,
        visibility: random_visibility(),
        theme: random_theme(),
        is_virtual: Enum.random([false, false, false, true]),
        threshold_count: maybe_threshold(),
        timezone: Faker.Address.time_zone()
      }, taxation_attrs), users, groups, venue_pool)
    end)
  end

  defp create_future_events(count, users, groups, venue_pool) do
    Helpers.log("Creating #{count} far future events...")

    Enum.map(1..count, fn _ ->
      # Far future events (61-365 days)
      # Use explicit date calculation instead of Faker to ensure accuracy
      now = DateTime.utc_now() |> truncate_datetime()
      days_forward = Enum.random(61..365)
      start_at = DateTime.add(now, days_forward * 24 * 60 * 60, :second) |> truncate_datetime()
      duration_hours = Enum.random([2, 3, 4, 6, 8, 24, 48, 72]) # Can be longer
      ends_at = DateTime.add(start_at, duration_hours * 3600, :second) |> truncate_datetime()

      status = Enum.random([:draft, :draft, :polling]) # Mostly drafts

      # Polling deadline must be BEFORE the event AND in the FUTURE (at least 1 day from now)
      polling_deadline = if status == :polling do
        # Calculate days until event from now
        days_until_event = DateTime.diff(start_at, now, :day)
        # Set deadline between 1 day from now and 7 days before the event
        # Ensure we have at least 8 days until the event for a valid polling window
        max_days_before = min(14, days_until_event - 1)
        min_days_from_now = 1
        max_days_from_now = days_until_event - max_days_before

        if max_days_from_now >= min_days_from_now do
          days_from_now = Enum.random(min_days_from_now..max_days_from_now)
          DateTime.add(now, days_from_now * 24 * 60 * 60, :second) |> truncate_datetime()
        else
          # Fallback: set deadline 7 days from now (safe for future events)
          DateTime.add(now, 7 * 24 * 60 * 60, :second) |> truncate_datetime()
        end
      else
        nil
      end
      
      title = generate_event_title()
      taxation_attrs = random_taxation_and_ticketing()
      create_event(Map.merge(%{
        title: title,
        description: DevSeeds.CuratedData.generate_event_description(title),
        tagline: DevSeeds.CuratedData.random_tagline(),
        start_at: start_at,
        ends_at: ends_at,
        status: status,
        polling_deadline: polling_deadline,
        visibility: random_visibility(),
        theme: random_theme(),
        is_virtual: Enum.random([false, false, true]),
        threshold_count: maybe_threshold(),
        timezone: Faker.Address.time_zone()
      }, taxation_attrs), users, groups, venue_pool)
    end)
  end
  
  defp create_event(attrs, users, groups, venue_pool) do
    # Select a random organizer
    organizer = Enum.random(users)

    # Maybe assign to a group
    group = if Enum.random([true, false, false]) && length(groups) > 0 do
      Enum.random(groups)
    else
      nil
    end

    # Venue assignment: virtual events use virtual_venue_url, physical events use venue_id
    venue_attrs = if Map.get(attrs, :is_virtual) do
      # Virtual events don't need a physical venue, just a URL
      %{
        virtual_venue_url: Faker.Internet.url(),
        is_virtual: true
      }
    else
      # Assign a venue from the pool (if available) for physical events
      if length(venue_pool) > 0 do
        venue = Enum.random(venue_pool)
        %{venue_id: venue.id, is_virtual: false}
      else
        # Fallback: make it virtual if no physical venues available
        %{
          is_virtual: true,
          virtual_venue_url: Faker.Internet.url()
        }
      end
    end
    
    # Get a random default image for the event
    image_attrs = Helpers.get_random_image_attrs()
    
    # Ensure venue_attrs take precedence over incoming attrs (especially is_virtual)
    event_params =
      attrs
      |> Map.merge(venue_attrs)
      |> Map.merge(image_attrs)
    
    # Add group_id if selected
    event_params = if group && is_nil(Map.get(attrs, :group_id)) do
      Map.put(event_params, :group_id, group.id)
    else
      event_params
    end
    
    # Create event using production API with organizer
    {:ok, event} = Events.create_event_with_organizer(event_params, organizer)
    
    # Maybe add co-organizers using production API
    if Enum.random([true, false]) do
      co_organizer = Enum.random(users -- [organizer])
      Events.add_user_to_event(event, co_organizer, "organizer")
    end
    
    event
  end
  
  defp add_participants_to_events(events, users) do
    Helpers.log("Adding participants to events...")
    
    Enum.each(events, fn event ->
      # Skip draft events
      if event.status not in [:draft] do
        # Random number of participants (2-50)
        participant_count = case event.visibility do
          :public -> Enum.random(5..50)
          :private -> Enum.random(2..15)
          _ -> Enum.random(2..30)
        end
        
        # Don't exceed available users
        participant_count = min(participant_count, length(users))
        
        # Select random users as participants
        participants = Enum.take_random(users, participant_count)
        
        # Add them with various statuses
        Enum.each(participants, fn user ->
          status = case event.status do
            :completed -> Enum.random([:accepted, :accepted, :accepted, :declined])
            :canceled -> Enum.random([:accepted, :declined, :cancelled])
            :confirmed -> Enum.random([:pending, :accepted, :accepted, :declined, :interested])
            :polling -> Enum.random([:interested, :interested, :pending])
            _ -> :pending
          end
          
          # Check if user is already an organizer
          unless Repo.get_by(EventUser, event_id: event.id, user_id: user.id) do
            # Use production API for participant creation
            Events.create_event_participant(%{
              event_id: event.id,
              user_id: user.id,
              status: status,
              role: :ticket_holder,
              source: Enum.random(["direct_registration", "invitation", "group_invite"])
            })
          end
        end)
      end
    end)
  end
  
  defp generate_event_title do
    # Use real event titles from curated data - no Lorem ipsum!
    DevSeeds.CuratedData.generate_realistic_event_title()
  end
  
  defp random_visibility do
    Enum.random([:public, :public, :public, :private]) # 75% public
  end
  
  defp random_theme do
    Enum.random([:minimal, :cosmic, :velocity, :retro, :celebration, :nature, :professional])
  end

  # Generate consistent taxation_type and is_ticketed values
  # For now, all events are free (no ticketing) to avoid complications
  defp random_taxation_and_ticketing do
    %{
      taxation_type: "ticketless",
      is_ticketed: false
    }
  end
  
  defp maybe_threshold do
    if Enum.random([true, false, false, false]) do # 25% have thresholds
      Enum.random([5, 10, 15, 20, 25, 30, 50])
    else
      nil
    end
  end

  # Helper function to truncate microseconds from datetime values
  # Database schema expects datetime without microseconds
  defp truncate_datetime(datetime) when is_struct(datetime, DateTime) do
    DateTime.truncate(datetime, :second)
  end

  defp truncate_datetime(datetime), do: datetime
  
  @doc """
  Creates events at maximum capacity for testing
  """
  def create_full_events(users) do
    Helpers.log("Creating events at maximum capacity...")
    
    Enum.map(1..5, fn _ ->
      base_title = generate_event_title()
      event = create_event(%{
        title: "SOLD OUT: #{base_title}",
        description: "This event is at maximum capacity.\n\n#{DevSeeds.CuratedData.generate_event_description(base_title)}",
        tagline: "Fully booked!",
        start_at: Faker.DateTime.forward(30) |> truncate_datetime(),
        ends_at: Faker.DateTime.forward(31) |> truncate_datetime(),
        status: :confirmed,
        threshold_count: 20,
        visibility: :public,
        is_ticketed: false,
        is_virtual: false,
        theme: :celebration,
        taxation_type: "ticketless",
        timezone: Faker.Address.time_zone()
      }, users, [], [])
      
      # Add participants up to the threshold number (or available users)
      participants = Enum.take(users, min(20, length(users)))
      Enum.each(participants, fn user ->
        # Use production API for participant creation  
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          status: :accepted,
          role: :ticket_holder
        })
      end)
      
      event
    end)
  end

  # Venue Pool Creation Functions (from comprehensive_seed.exs)
  
  defp create_venue_pool do
    alias EventasaurusApp.Venues
    alias EventasaurusWeb.Services.GooglePlaces.TextSearch

    Helpers.log("Creating venue pool (slowly to avoid API rate limits)...")
    
    # Create 8 venues total (4 restaurants, 4 theaters) with delays
    restaurant_venues = create_restaurant_venues(4)
    Process.sleep(2000) # 2 second delay between venue types
    
    theater_venues = create_theater_venues(4)
    
    all_venues = restaurant_venues ++ theater_venues
    Helpers.log("Venue pool created: #{length(all_venues)} venues")
    all_venues
  end
  
  defp create_restaurant_venues(count) do
    Helpers.log("Creating #{count} restaurant venues...")
    alias EventasaurusApp.Venues
    alias EventasaurusWeb.Services.GooglePlaces.TextSearch
    
    # First try Google Places API for real data
    google_venues = case TextSearch.search("restaurant", %{
      type: "restaurant", 
      location: {37.7749, -122.4194}, # San Francisco
      radius: 5000
    }) do
      {:ok, venues} when length(venues) >= count ->
        Helpers.log("Using Google Places restaurant data")
        venues |> Enum.take(count)
      _ ->
        Helpers.log("Google Places unavailable, using fallback restaurant data")
        []
    end
    
    # Create venues with delay to avoid rate limits
    google_results =
      Enum.with_index(google_venues)
      |> Enum.map(fn {venue_data, index} ->
        if index > 0, do: Process.sleep(1500) # 1.5s delay between venues
        
        venue_params = %{
          name: venue_data["name"],
          address: venue_data["formatted_address"] || venue_data["vicinity"] || "San Francisco, CA",
          city_name: extract_city_from_address(venue_data) || "San Francisco",
          country_code: extract_country_code_from_address(venue_data) || "US",
          latitude: get_in(venue_data, ["geometry", "location", "lat"]) || 37.7749,
          longitude: get_in(venue_data, ["geometry", "location", "lng"]) || -122.4194,
          venue_type: "venue",
          source: "user"
        }

        # Use VenueStore for automatic city_id lookup
        case EventasaurusDiscovery.Locations.VenueStore.find_or_create_venue(venue_params) do
          {:ok, venue} -> 
            Helpers.log("Created restaurant venue: #{venue.name}")
            venue
          {:error, reason} -> 
            Helpers.error("Failed to create venue: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.filter(&(&1)) # Remove nils

    fallback_venues = create_fallback_restaurants(count - length(google_results))
    (google_results ++ fallback_venues) |> Enum.take(count)
  end
  
  defp create_theater_venues(count) do
    Helpers.log("Creating #{count} theater venues...")
    alias EventasaurusApp.Venues
    alias EventasaurusWeb.Services.GooglePlaces.TextSearch
    
    # Try Google Places API for theaters
    google_venues = case TextSearch.search("movie theater", %{
      type: "movie_theater",
      location: {37.7749, -122.4194}, # San Francisco
      radius: 5000
    }) do
      {:ok, venues} when length(venues) >= count ->
        Helpers.log("Using Google Places theater data")
        venues |> Enum.take(count)
      _ ->
        Helpers.log("Google Places unavailable, using fallback theater data")
        []
    end
    
    google_results =
      Enum.with_index(google_venues)
      |> Enum.map(fn {venue_data, index} ->
        if index > 0, do: Process.sleep(1500) # 1.5s delay between venues
        
        venue_params = %{
          name: venue_data["name"],
          address: venue_data["formatted_address"] || venue_data["vicinity"] || "San Francisco, CA",
          city_name: extract_city_from_address(venue_data) || "San Francisco",
          country_code: extract_country_code_from_address(venue_data) || "US",
          latitude: get_in(venue_data, ["geometry", "location", "lat"]) || 37.7749,
          longitude: get_in(venue_data, ["geometry", "location", "lng"]) || -122.4194,
          venue_type: "venue",
          source: "user"
        }

        # Use VenueStore for automatic city_id lookup
        case EventasaurusDiscovery.Locations.VenueStore.find_or_create_venue(venue_params) do
          {:ok, venue} -> 
            Helpers.log("Created theater venue: #{venue.name}")
            venue
          {:error, reason} -> 
            Helpers.error("Failed to create venue: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.filter(&(&1)) # Remove nils

    fallback_venues = create_fallback_theaters(count - length(google_results))
    (google_results ++ fallback_venues) |> Enum.take(count)
  end
  
  defp create_fallback_restaurants(count) do
    Helpers.log("Creating #{count} fallback restaurant venues...")
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
        city_name: "San Francisco",
        country_code: "US",
        latitude: restaurant.lat,
        longitude: restaurant.lng,
        venue_type: "venue",
        source: "user"
      }

      # Use VenueStore for automatic city_id lookup
      case EventasaurusDiscovery.Locations.VenueStore.find_or_create_venue(venue_params) do
        {:ok, venue} -> 
          Helpers.log("Created fallback restaurant: #{venue.name}")
          venue
        {:error, reason} -> 
          Helpers.error("Failed to create fallback restaurant: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(&(&1)) # Remove nils
  end
  
  defp create_fallback_theaters(count) do
    Helpers.log("Creating #{count} fallback theater venues...")

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
        city_name: "San Francisco",
        country_code: "US",
        latitude: theater.lat,
        longitude: theater.lng,
        venue_type: "venue",
        source: "user"
      }

      # Use VenueStore for automatic city_id lookup
      case EventasaurusDiscovery.Locations.VenueStore.find_or_create_venue(venue_params) do
        {:ok, venue} -> 
          Helpers.log("Created fallback theater: #{venue.name}")
          venue
        {:error, reason} -> 
          Helpers.error("Failed to create fallback theater: #{inspect(reason)}")
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

  defp extract_country_code_from_address(venue_data) do
    address_components = venue_data["address_components"] || []
    country_component = Enum.find(address_components, fn component ->
      types = component["types"] || []
      "country" in types
    end)

    case country_component do
      %{"short_name" => code} -> code
      _ -> nil
    end
  end

end