defmodule DevSeeds.Events do
  @moduledoc """
  Event seeding module for development environment.
  Creates events in various states with realistic data.
  """
  
  import EventasaurusApp.Factory
  alias DevSeeds.Helpers
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.EventUser
  alias EventasaurusWeb.Services.DefaultImagesService
  
  @doc """
  Seeds events with various states and configurations.
  
  Options:
    - count: Total number of events to create (default: 100)
    - users: List of users to assign as organizers/participants
    - groups: List of groups to associate with events
  """
  def seed(opts \\ []) do
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
      
      # Create events with proper time distribution
      events = create_time_distributed_events(count, users, groups)
      
      # Add participants to events
      add_participants_to_events(events, users)
      
      Helpers.success("Created #{length(events)} events")
      events
    end
  end
  
  defp create_time_distributed_events(count, users, groups) do
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
    
    past_events = create_past_events(past_count, users, groups)
    upcoming_events = create_upcoming_events(upcoming_count, users, groups)
    future_events = create_future_events(future_count, users, groups)
    
    past_events ++ upcoming_events ++ future_events
  end
  
  defp create_past_events(count, users, groups) do
    Helpers.log("Creating #{count} past events...")
    
    Enum.map(1..count, fn _ ->
      # Past events (1-365 days ago)
      days_ago = Enum.random(1..365)
      start_at = Faker.DateTime.backward(days_ago)
      duration_hours = Enum.random([2, 3, 4, 6, 8, 24, 48]) # Various durations
      ends_at = DateTime.add(start_at, duration_hours * 3600, :second)
      
      event = create_event(%{
        title: generate_event_title(),
        description: Faker.Lorem.paragraphs(3) |> Enum.join("\n\n"),
        tagline: Faker.Company.catch_phrase(),
        start_at: start_at,
        ends_at: ends_at,
        status: Enum.random([:confirmed, :confirmed, :canceled]), # Most are confirmed
        visibility: random_visibility(),
        theme: random_theme(),
        is_virtual: Enum.random([false, false, false, true]), # 25% virtual
        is_ticketed: Enum.random([false, false, true]), # 33% ticketed
        taxation_type: random_taxation_type(),
        timezone: Faker.Address.time_zone()
      }, users, groups)
      
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
  
  defp create_upcoming_events(count, users, groups) do
    Helpers.log("Creating #{count} upcoming events...")
    
    Enum.map(1..count, fn _ ->
      # Upcoming events (today to 60 days)
      days_forward = Enum.random(0..60)
      start_at = Faker.DateTime.forward(days_forward)
      duration_hours = Enum.random([2, 3, 4, 6, 8])
      ends_at = DateTime.add(start_at, duration_hours * 3600, :second)
      
      status = Enum.random([
        :draft, 
        :polling, :polling,  # More polling
        :confirmed, :confirmed, :confirmed, :confirmed  # Most are confirmed
      ])
      
      polling_deadline = if status == :polling do
        Faker.DateTime.forward(Enum.random(1..7))
      else
        nil
      end
      
      create_event(%{
        title: generate_event_title(),
        description: Faker.Lorem.paragraphs(3) |> Enum.join("\n\n"),
        tagline: Faker.Company.catch_phrase(),
        start_at: start_at,
        ends_at: ends_at,
        status: status,
        polling_deadline: polling_deadline,
        visibility: random_visibility(),
        theme: random_theme(),
        is_virtual: Enum.random([false, false, false, true]),
        is_ticketed: Enum.random([false, false, true]),
        taxation_type: random_taxation_type(),
        threshold_count: maybe_threshold(),
        timezone: Faker.Address.time_zone()
      }, users, groups)
    end)
  end
  
  defp create_future_events(count, users, groups) do
    Helpers.log("Creating #{count} far future events...")
    
    Enum.map(1..count, fn _ ->
      # Far future events (61-365 days)
      days_forward = Enum.random(61..365)
      start_at = Faker.DateTime.forward(days_forward)
      duration_hours = Enum.random([2, 3, 4, 6, 8, 24, 48, 72]) # Can be longer
      ends_at = DateTime.add(start_at, duration_hours * 3600, :second)
      
      create_event(%{
        title: generate_event_title(),
        description: Faker.Lorem.paragraphs(3) |> Enum.join("\n\n"),
        tagline: Faker.Company.catch_phrase(),
        start_at: start_at,
        ends_at: ends_at,
        status: Enum.random([:draft, :draft, :polling]), # Mostly drafts
        visibility: random_visibility(),
        theme: random_theme(),
        is_virtual: Enum.random([false, false, true]),
        is_ticketed: Enum.random([false, true]), # More likely to be ticketed
        taxation_type: random_taxation_type(),
        threshold_count: maybe_threshold(),
        timezone: Faker.Address.time_zone()
      }, users, groups)
    end)
  end
  
  defp create_event(attrs, users, groups) do
    # Select a random organizer
    organizer = Enum.random(users)
    
    # Maybe assign to a group
    group = if Enum.random([true, false, false]) && length(groups) > 0 do
      Enum.random(groups)
    else
      nil
    end
    
    # Create venue or virtual URL
    venue_attrs = if attrs.is_virtual do
      %{virtual_venue_url: Faker.Internet.url()}
    else
      %{venue: build(:realistic_venue)}
    end
    
    # Get a random default image for the event
    image_attrs = get_random_image_attrs()
    
    # Create the event with image - ensure caller-provided attrs take precedence
    event = insert(:realistic_event, Map.merge(Map.merge(venue_attrs, image_attrs), attrs))
    
    # Assign to group if selected AND caller didn't supply group_id
    if group && is_nil(Map.get(attrs, :group_id)) do
      event
      |> Ecto.Changeset.change(%{group_id: group.id})
      |> Repo.update!()
    end
    
    # Add organizer
    insert(:event_user, %{
      event: event,
      user: organizer,
      role: "owner"
    })
    
    # Maybe add co-organizers
    if Enum.random([true, false]) do
      co_organizer = Enum.random(users -- [organizer])
      insert(:event_user, %{
        event: event,
        user: co_organizer,
        role: "organizer"
      })
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
            insert(:event_participant, %{
              event: event,
              user: user,
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
    event_types = [
      "#{Faker.Person.name()} Birthday Party",
      "Movie Night: #{Faker.Lorem.word()}",
      "Dinner at #{Faker.Company.name()}",
      "#{Faker.Lorem.word()} Game Night",
      "#{Faker.Team.name()} vs #{Faker.Team.name()}",
      "#{Faker.Person.name()} Concert",
      "Book Club: #{Faker.Lorem.word()}",
      "Wine Tasting at #{Faker.Company.name()}",
      "Hiking: #{Faker.Address.city()} Trail",
      "Tech Talk: #{Faker.Company.catch_phrase()}",
      "#{Faker.Lorem.word()} Workshop",
      "Community Meetup",
      "#{Faker.Address.city()} Food Festival",
      "Board Game Tournament",
      "Karaoke Night",
      Faker.Lorem.sentence(3)
    ]
    
    Enum.random(event_types)
  end
  
  defp random_visibility do
    Enum.random([:public, :public, :public, :private]) # 75% public
  end
  
  defp random_theme do
    Enum.random([:minimal, :cosmic, :velocity, :retro, :celebration, :nature, :professional])
  end
  
  defp random_taxation_type do
    Enum.random([
      "ticketed_event", "ticketed_event",  # 50% ticketed
      "contribution_collection",            # 25% contribution
      "ticketless", "ticketless"           # 25% ticketless
    ])
  end
  
  defp maybe_threshold do
    if Enum.random([true, false, false, false]) do # 25% have thresholds
      Enum.random([5, 10, 15, 20, 25, 30, 50])
    else
      nil
    end
  end
  
  @doc """
  Creates events at maximum capacity for testing
  """
  def create_full_events(users) do
    Helpers.log("Creating events at maximum capacity...")
    
    Enum.map(1..5, fn _ ->
      event = create_event(%{
        title: "SOLD OUT: #{generate_event_title()}",
        description: "This event is at maximum capacity.",
        tagline: "Fully booked event",
        start_at: Faker.DateTime.forward(30),
        ends_at: Faker.DateTime.forward(31),
        status: :confirmed,
        threshold_count: 20,
        visibility: :public,
        is_ticketed: true,
        is_virtual: false,
        theme: :celebration,
        taxation_type: "ticketed_event",
        timezone: Faker.Address.time_zone()
      }, users, [])
      
      # Add participants up to the threshold number (or available users)
      participants = Enum.take(users, min(20, length(users)))
      Enum.each(participants, fn user ->
        insert(:event_participant, %{
          event: event,
          user: user,
          status: :accepted,
          role: :ticket_holder
        })
      end)
      
      event
    end)
  end
  
  defp get_random_image_attrs do
    # Get a random default image from our collection
    case DefaultImagesService.get_random_image() do
      nil ->
        # Fallback if no images are available
        %{}
      
      image ->
        # Use the image URL as cover_image_url
        %{cover_image_url: image.url}
    end
  end
end