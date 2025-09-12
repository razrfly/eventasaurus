defmodule DevSeeds.AddInterestToTicketedEvents do
  @moduledoc """
  Adds interested participants to the ticketed events created by our event organizer personas.
  This simulates community interest in the events.
  """
  
  alias EventasaurusApp.{Repo, Accounts, Events}
  alias EventasaurusApp.Events.{EventUser, EventParticipant}
  
  # Load helpers
  Code.require_file("helpers.exs", __DIR__)
  alias DevSeeds.Helpers
  
  def add_interest_to_organizer_events do
    Helpers.section("Adding Interested Participants to Ticketed Events")
    
    # Get our event organizer personas
    organizer_emails = [
      "go_kart_racer@example.com",
      "workshop_leader@example.com",
      "entertainment_host@example.com",
      "community_fundraiser@example.com"
    ]
    
    organizers = Enum.map(organizer_emails, fn email ->
      Accounts.get_user_by_email(email)
    end) |> Enum.filter(& &1)
    
    if length(organizers) == 0 do
      Helpers.error("No event organizer personas found. Run ticketed_event_organizers.exs first.")
    else
    
    # Get a pool of users who can be interested (excluding the organizers themselves)
    organizer_ids = Enum.map(organizers, & &1.id)
    
    import Ecto.Query
    available_users = Repo.all(
      from u in Accounts.User,
      where: u.id not in ^organizer_ids,
      limit: 100
    )
    
      if length(available_users) < 10 do
        Helpers.error("Not enough users in database to add interest. Need at least 10 non-organizer users.")
      else
        # For each organizer, get their events and add interested participants
        Enum.each(organizers, fn organizer ->
          add_interest_to_user_events(organizer, available_users)
        end)
        
        Helpers.success("Added interested participants to all ticketed events")
      end
    end
  end
  
  defp add_interest_to_user_events(organizer, available_users) do
    import Ecto.Query
    
    # Get events this organizer created
    organizer_events = Repo.all(
      from eu in EventUser,
      join: e in assoc(eu, :event),
      where: eu.user_id == ^organizer.id and 
             eu.role in ["owner", "organizer"] and 
             is_nil(e.deleted_at),
      select: e
    ) |> Repo.preload(:tickets)
    
    if length(organizer_events) == 0 do
      Helpers.log("No events found for #{organizer.name}", :yellow)
    else
      Helpers.log("Adding interest to #{length(organizer_events)} events for #{organizer.name}")
    
    Enum.each(organizer_events, fn event ->
      # Determine how many interested participants based on event type
      num_interested = cond do
        # Ticketed events with multiple ticket types get more interest
        event.is_ticketed && length(event.tickets) > 1 -> Enum.random(15..25)
        # Regular ticketed events get moderate interest
        event.is_ticketed -> Enum.random(10..20)
        # Free events get good interest too
        true -> Enum.random(8..15)
      end
      
      # Get existing participants for this event to avoid duplicates
      existing_participant_ids = Repo.all(
        from ep in EventParticipant,
        where: ep.event_id == ^event.id,
        select: ep.user_id
      )
      
      # Also check event_users to avoid adding organizers as participants
      event_user_ids = Repo.all(
        from eu in EventUser,
        where: eu.event_id == ^event.id,
        select: eu.user_id
      )
      
      excluded_ids = existing_participant_ids ++ event_user_ids
      
      # Filter available users and select random ones
      eligible_users = Enum.filter(available_users, fn user ->
        user.id not in excluded_ids
      end)
      
      users_to_add = Enum.take_random(eligible_users, num_interested)
      
      added_count = Enum.reduce(users_to_add, 0, fn user, acc ->
        # Use appropriate status based on event type
        status = if event.is_ticketed do
          # For ticketed events, only use interested (can't accept without buying a ticket)
          # See issue #1040 for discussion about this status confusion
          :interested
        else
          # For free events, mix of interested and accepted
          Enum.random([:interested, :accepted, :accepted])
        end
        
        # Use appropriate role based on event type
        role = :invitee  # Use invitee as the default role for interested participants
        
        case Events.create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          status: status,
          role: role,
          source: "interest_seeding"
        }) do
          {:ok, _participant} -> acc + 1
          {:error, changeset} -> 
            Helpers.log("    Failed to add participant: #{inspect(changeset.errors)}", :red)
            acc
        end
      end)
      
      if added_count > 0 do
        ticket_info = if event.is_ticketed do
          " (#{length(event.tickets)} ticket types)"
        else
          " (free event)"
        end
        
        Helpers.log("  → Added #{added_count} interested users to: #{event.title}#{ticket_info}", :green)
      end
    end)
    end
  end
end

# Allow direct execution of this script
if __ENV__.file == Path.absname(__ENV__.file) do
  DevSeeds.AddInterestToTicketedEvents.add_interest_to_organizer_events()
end