defmodule DevSeeds.EventBuilder do
  @moduledoc """
  Centralized service for creating events with all required attributes.
  Ensures consistency across all seed modules.
  
  This service coordinates with other specialized services to ensure
  every event has proper images, venues, and all required attributes.
  """
  
  import EventasaurusApp.Factory
  alias DevSeeds.{ImageService, VenueService, EventTypes}
  
  @doc """
  Creates an event with all required attributes using centralized logic.
  
  ## Parameters
  - event_type: atom representing the event type (:conference, :wedding, etc.)
  - base_attrs: map of base attributes for the event
  - options: keyword list of options
    - virtual: boolean to force virtual event (default: false)
    - image_category: override default image category for event type
    
  ## Examples
    
      # Create a physical conference event
      event = DevSeeds.EventBuilder.create_event(:conference, %{
        title: "Tech Conference 2025",
        description: "Annual technology conference"
      })
      
      # Create a virtual wedding planning event
      event = DevSeeds.EventBuilder.create_event(:wedding, %{
        title: "Wedding Planning Session"
      }, virtual: true)
  """
  def create_event(event_type, base_attrs \\ %{}, options \\ []) do
    # Get configuration for this event type
    config = EventTypes.get_configuration(event_type)
    
    # Build complete attributes by merging in order of priority:
    # 1. Event type defaults
    # 2. Image attributes
    # 3. Venue attributes  
    # 4. User-provided base_attrs (highest priority)
    config.default_attrs
    |> Map.merge(ImageService.get_image_attributes(event_type, options))
    |> Map.merge(VenueService.get_venue_attributes(event_type, options))
    |> Map.merge(base_attrs)
    |> create_realistic_event()
  end
  
  @doc """
  Creates multiple events of the same type with varied attributes.
  
  ## Parameters
  - event_type: atom representing the event type
  - count: number of events to create
  - attrs_fn: function that takes index and returns attributes map
  - options: keyword list passed to create_event/3
  
  ## Examples
  
      events = DevSeeds.EventBuilder.create_events(:conference, 3, fn i ->
        %{title: "Conference \#{i}", capacity: 50 + i * 10}
      end)
  """
  def create_events(event_type, count, attrs_fn \\ fn _i -> %{} end, options \\ []) do
    Enum.map(1..count, fn i ->
      attrs = attrs_fn.(i)
      create_event(event_type, attrs, options)
    end)
  end
  
  @doc """
  Creates an event with polls using the centralized system.
  
  This is a convenience function that creates an event and then
  adds polls to it using the poll creation services.
  
  ## Parameters
  - event_type: atom representing the event type
  - base_attrs: map of base attributes for the event
  - poll_configs: list of poll configuration maps
  - options: keyword list passed to create_event/3
  
  ## Examples
  
      event = DevSeeds.EventBuilder.create_event_with_polls(:conference, %{
        title: "Tech Summit 2025"
      }, [
        %{poll_type: "date_selection", title: "Choose Conference Date"},
        %{poll_type: "places", title: "Select Venue Location"}
      ])
  """
  def create_event_with_polls(event_type, base_attrs, poll_configs, options \\ []) do
    # Create the event first
    event = create_event(event_type, base_attrs, options)
    
    # Add polls to the event (this will be implemented when we add poll services)
    # For now, return the event - polls will be added by existing poll creation logic
    event
  end
  
  # Private function to create the actual event using factory
  # Uses :realistic_event factory which should include proper defaults
  defp create_realistic_event(attrs) do
    insert(:realistic_event, attrs)
  end
end