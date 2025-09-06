defmodule DevSeeds.VenueService do
  @moduledoc """
  Centralized service for handling event venue assignment and virtual/physical logic.
  
  This service ensures consistent venue assignment across all seed modules,
  properly handling both physical venues and virtual events.
  """
  
  import EventasaurusApp.Factory
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  
  @doc """
  Gets venue attributes for an event based on its type and options.
  
  ## Parameters
  - event_type: atom representing the event type (:conference, :wedding, etc.)
  - options: keyword list of options
    - virtual: boolean to force virtual event (default: false)  
    - venue_type: override default venue type for event type
    - location: specific location/city for venue selection
    
  ## Returns
  Map with venue-related attributes (venue_id, is_virtual, virtual_venue_url, etc.)
  
  ## Examples
  
      # Create physical conference venue
      attrs = DevSeeds.VenueService.get_venue_attributes(:conference)
      # => %{venue_id: 123, is_virtual: false}
      
      # Force virtual event
      attrs = DevSeeds.VenueService.get_venue_attributes(:wedding, virtual: true)
      # => %{venue_id: nil, is_virtual: true, virtual_venue_url: "https://zoom.us/..."}
  """
  def get_venue_attributes(event_type, options \\ []) do
    virtual = Keyword.get(options, :virtual, false)
    
    if virtual or should_be_virtual?(event_type) do
      get_virtual_venue_attributes(event_type)
    else
      get_physical_venue_attributes(event_type, options)
    end
  end
  
  @doc """
  Gets or creates a venue appropriate for the event type.
  
  ## Parameters
  - event_type: atom representing the event type
  - options: keyword list of options
    - location: preferred location/city
    - venue_type: specific venue type override
    - capacity: minimum venue capacity needed
    
  ## Returns
  Venue struct that can be used for venue_id assignment
  """
  def get_or_create_venue(event_type, options \\ []) do
    venue_type = Keyword.get(options, :venue_type) || get_default_venue_type(event_type)
    capacity = Keyword.get(options, :capacity, get_default_capacity(event_type))
    
    # Try to find existing suitable venue first
    case find_suitable_venue(venue_type, capacity) do
      nil ->
        create_venue_for_type(venue_type, capacity, options)
      venue ->
        venue
    end
  end
  
  @doc """
  Validates that an event has proper venue configuration.
  
  ## Parameters
  - event: event struct or map
  
  ## Returns
  - {:ok, event} if venue configuration is valid
  - {:error, reason} if venue configuration is invalid
  """
  def validate_event_venue(event) do
    is_virtual = Map.get(event, :is_virtual, false)
    venue_id = Map.get(event, :venue_id)
    virtual_venue_url = Map.get(event, :virtual_venue_url)
    
    cond do
      is_virtual and not is_nil(venue_id) ->
        {:error, "Virtual event should not have venue_id"}
        
      is_virtual and is_nil(virtual_venue_url) ->
        {:error, "Virtual event missing virtual_venue_url"}
        
      not is_virtual and is_nil(venue_id) ->
        {:error, "Physical event missing venue_id"}
        
      true ->
        {:ok, event}
    end
  end
  
  # Private functions
  
  # Determines if an event type should default to virtual
  defp should_be_virtual?(:webinar), do: true
  defp should_be_virtual?(:online_course), do: true
  defp should_be_virtual?(_), do: false
  
  # Gets virtual venue attributes for an event
  defp get_virtual_venue_attributes(_event_type) do
    %{
      venue_id: nil,
      is_virtual: true,
      virtual_venue_url: generate_virtual_venue_url()
    }
  end
  
  # Gets physical venue attributes for an event
  defp get_physical_venue_attributes(event_type, options) do
    venue = get_or_create_venue(event_type, options)
    
    %{
      venue_id: venue.id,
      is_virtual: false,
      virtual_venue_url: nil
    }
  end
  
  # Maps event types to appropriate venue types
  defp get_default_venue_type(:conference), do: "convention_center"
  defp get_default_venue_type(:wedding), do: "event_hall"
  defp get_default_venue_type(:workshop), do: "classroom"
  defp get_default_venue_type(:meetup), do: "cafe"
  defp get_default_venue_type(:party), do: "event_hall"
  defp get_default_venue_type(:festival), do: "outdoor_venue"
  defp get_default_venue_type(:seminar), do: "conference_room"
  defp get_default_venue_type(:retreat), do: "resort"
  defp get_default_venue_type(:networking), do: "business_center"
  defp get_default_venue_type(:launch), do: "event_space"
  defp get_default_venue_type(_), do: "event_space"
  
  # Gets default capacity for event types
  defp get_default_capacity(:conference), do: 200
  defp get_default_capacity(:wedding), do: 150
  defp get_default_capacity(:workshop), do: 30
  defp get_default_capacity(:meetup), do: 50
  defp get_default_capacity(:party), do: 100
  defp get_default_capacity(:festival), do: 500
  defp get_default_capacity(:seminar), do: 75
  defp get_default_capacity(:retreat), do: 40
  defp get_default_capacity(:networking), do: 80
  defp get_default_capacity(:launch), do: 120
  defp get_default_capacity(_), do: 100
  
  # Tries to find an existing venue suitable for the requirements
  defp find_suitable_venue(venue_type, min_capacity) do
    # Query existing venues that match our needs
    # This is a simplified query - could be more sophisticated
    import Ecto.Query
    
    from(v in Venue,
      where: v.venue_type == ^venue_type and v.capacity >= ^min_capacity,
      limit: 1
    )
    |> Repo.one()
  end
  
  # Creates a new venue for the specified type and capacity
  defp create_venue_for_type(venue_type, capacity, options) do
    location = Keyword.get(options, :location, get_default_location())
    
    venue_attrs = %{
      name: generate_venue_name(venue_type),
      venue_type: venue_type,
      capacity: capacity,
      address: generate_venue_address(location),
      city: location,
      state: "CA", # Default to California for seed data
      country: "US",
      description: generate_venue_description(venue_type)
    }
    
    insert(:venue, venue_attrs)
  end
  
  # Generates realistic venue names based on type
  defp generate_venue_name("convention_center"), do: Faker.Company.name() <> " Convention Center"
  defp generate_venue_name("event_hall"), do: Faker.Address.street_name() <> " Event Hall"
  defp generate_venue_name("classroom"), do: Faker.Company.name() <> " Learning Center"
  defp generate_venue_name("cafe"), do: Faker.Food.dish() <> " Cafe"
  defp generate_venue_name("outdoor_venue"), do: Faker.Address.street_name() <> " Park"
  defp generate_venue_name("conference_room"), do: Faker.Company.name() <> " Conference Center"
  defp generate_venue_name("resort"), do: Faker.Address.street_name() <> " Resort"
  defp generate_venue_name("business_center"), do: Faker.Company.name() <> " Business Center"
  defp generate_venue_name("event_space"), do: Faker.Address.street_name() <> " Event Space"
  defp generate_venue_name(_), do: Faker.Company.name() <> " Venue"
  
  # Generates venue addresses
  defp generate_venue_address(city) do
    "#{Faker.Address.street_address()}, #{city}"
  end
  
  # Generates venue descriptions
  defp generate_venue_description(venue_type) do
    base_descriptions = %{
      "convention_center" => "Modern convention center with state-of-the-art facilities",
      "event_hall" => "Elegant event hall perfect for celebrations and gatherings",
      "classroom" => "Interactive learning space with modern teaching facilities",
      "cafe" => "Cozy cafe atmosphere perfect for casual meetings",
      "outdoor_venue" => "Beautiful outdoor space with natural surroundings",
      "conference_room" => "Professional conference facilities with latest technology",
      "resort" => "Luxury resort venue with comprehensive amenities",
      "business_center" => "Professional business environment for corporate events",
      "event_space" => "Versatile event space suitable for various occasions"
    }
    
    Map.get(base_descriptions, venue_type, "Professional event venue")
  end
  
  # Gets default location for venue creation
  defp get_default_location() do
    locations = ["San Francisco", "Los Angeles", "San Diego", "Sacramento", "Oakland"]
    Enum.random(locations)
  end
  
  # Generates virtual venue URLs
  defp generate_virtual_venue_url() do
    platforms = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com"]
    platform = Enum.random(platforms)
    room_id = :crypto.strong_rand_bytes(8) |> Base.encode64() |> String.slice(0, 10)
    
    case platform do
      "zoom.us" -> "https://zoom.us/j/#{:rand.uniform(999999999)}"
      "meet.google.com" -> "https://meet.google.com/#{room_id}"
      "teams.microsoft.com" -> "https://teams.microsoft.com/l/meetup-join/#{room_id}"
      "webex.com" -> "https://#{room_id}.webex.com/join"
    end
  end
end