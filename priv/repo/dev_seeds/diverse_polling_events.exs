# Diverse Polling Events Seeding Script
# Implements Phase 1 and Phase 2 from issue #900
# Creates events with diversified poll types and physical locations

alias EventasaurusApp.{Repo, Events, Groups, Accounts}
import Ecto.Query
require Logger

defmodule DiversePollingEventsSeed do
  def run do
    Logger.info("Creating diverse polling events with physical locations...")
    
    users = Repo.all(from u in Accounts.User, limit: 15)
    groups = Repo.all(Groups.Group)
    
    if length(users) < 5 do
      Logger.error("Not enough users! Please run user seeding first.")
      exit(:no_users)
    end
    
    # Create diverse events with polling scenarios
    create_diverse_polling_events(users, groups)
    
    Logger.info("Diverse polling events seeding complete!")
  end
  
  defp create_diverse_polling_events(users, groups) do
    Logger.info("Creating 20 diverse polling events...")
    
    # Define diverse poll combinations with relative future dates
    poll_scenarios = [
      # Scenario 1: Date + Movie (Star Rating) 
      %{
        event_title: "Weekend Movie Night Planning",
        event_description: "Let's plan our perfect movie night! Vote on the date and rate your movie preferences.",
        days_offset: 7,
        location_type: :physical,
        polls: [
          %{
            title: "When should we meet?",
            poll_type: "date_selection", 
            voting_system: "approval",
            description: "Select all dates that work for you"
          },
          %{
            title: "Rate these movie options",
            poll_type: "movie",
            voting_system: "star", 
            description: "Rate each movie from 1-5 stars"
          }
        ]
      },
      
      # Scenario 2: Venue + Activity + Budget
      %{
        event_title: "Company Team Building Event",
        event_description: "Help us plan the perfect team building experience for everyone!",
        days_offset: 14,
        location_type: :physical,
        polls: [
          %{
            title: "Choose our venue",
            poll_type: "places",
            voting_system: "ranked",
            description: "Rank your preferred venues in order"
          },
          %{
            title: "What activity should we do?",
            poll_type: "custom",
            voting_system: "approval",
            description: "Select all activities you'd enjoy"
          },
          %{
            title: "Budget range preference",
            poll_type: "general",
            voting_system: "binary",
            description: "Yes/no for each budget range"
          }
        ]
      },
      
      # Scenario 3: Time + Food + Game
      %{
        event_title: "Community Game Night & Dinner",
        event_description: "Monthly community gathering with games, food, and fun!",
        days_offset: 21,
        location_type: :hybrid,
        polls: [
          %{
            title: "What time works best?",
            poll_type: "time", 
            voting_system: "approval",
            description: "Select all time slots that work for you"
          },
          %{
            title: "Food preferences",
            poll_type: "custom",
            voting_system: "ranked",
            description: "Rank your food preferences"
          },
          %{
            title: "Rate these game options",
            poll_type: "general",
            voting_system: "star",
            description: "Rate each game idea from 1-5 stars"
          }
        ]
      },
      
      # Scenario 4: Simple Date + Restaurant
      %{
        event_title: "Foodie Adventure Planning",
        event_description: "Let's explore new restaurants together!",
        days_offset: 10,
        location_type: :physical,
        polls: [
          %{
            title: "Which date works?",
            poll_type: "date_selection",
            voting_system: "binary",
            description: "Yes/no for each proposed date"
          },
          %{
            title: "Restaurant options",
            poll_type: "places",
            voting_system: "approval", 
            description: "Select all restaurants you'd like to try"
          }
        ]
      },
      
      # Scenario 5: Music Event Planning
      %{
        event_title: "Live Music & Venue Selection",
        event_description: "Planning our next music event - help us choose!",
        days_offset: 28,
        location_type: :physical,
        polls: [
          %{
            title: "Rate these venues",
            poll_type: "venue",
            voting_system: "star",
            description: "Rate each venue based on acoustics and atmosphere"
          },
          %{
            title: "Music genre preferences", 
            poll_type: "custom",
            voting_system: "ranked",
            description: "Rank genres by preference"
          }
        ]
      }
    ]
    
    # Create multiple events from each scenario
    created_events = Enum.flat_map(1..4, fn batch ->
      Enum.map(poll_scenarios, fn scenario ->
        create_event_with_polls(scenario, batch, users, groups)
      end)
    end)
    |> Enum.filter(&(&1))
    
    Logger.info("Created #{length(created_events)} diverse polling events!")
  end
  
  defp create_event_with_polls(scenario, batch_num, users, groups) do
    organizer = Enum.random(users)
    group = if rem(batch_num, 3) == 0 && length(groups) > 0, do: Enum.random(groups), else: nil
    
    # Calculate relative future date
    start_datetime = DateTime.utc_now()
    |> DateTime.add(scenario.days_offset * 24 * 60 * 60, :second)
    |> DateTime.add(:rand.uniform(8) * 60 * 60, :second) # Add random hours
    
    end_datetime = DateTime.add(start_datetime, :rand.uniform(4) * 60 * 60, :second)
    
    # Generate physical/virtual location based on scenario
    {is_virtual, virtual_url, physical_location} = generate_location(scenario.location_type)
    
    event_params = %{
      title: "#{scenario.event_title} (Batch #{batch_num})",
      description: scenario.event_description,
      start_at: start_datetime,
      ends_at: end_datetime,
      timezone: Enum.random(["America/Los_Angeles", "America/New_York", "Europe/London"]),
      visibility: Enum.random(["public", "public", "unlisted"]),
      status: "confirmed",
      group_id: group && group.id,
      is_virtual: is_virtual,
      virtual_venue_url: virtual_url,
      location: physical_location
    }
    
    case Events.create_event(event_params) do
      {:ok, event} ->
        # Add organizer
        Events.add_user_to_event(event, organizer, "organizer")
        
        # Add some participants
        participant_count = Enum.random(3..8)
        participants = users 
        |> Enum.reject(&(&1.id == organizer.id)) 
        |> Enum.take_random(min(participant_count, length(users) - 1))
        
        Enum.each(participants, fn participant ->
          Events.create_event_participant(%{
            event_id: event.id,
            user_id: participant.id,
            status: Enum.random(["confirmed", "confirmed", "maybe"])
          })
        end)
        
        # Create polls for this event
        create_polls_for_event(event, scenario.polls, organizer, participants)
        
        Logger.info("Created event: #{event.title} with #{length(scenario.polls)} polls")
        event
        
      {:error, changeset} ->
        Logger.error("Failed to create event: #{inspect(changeset.errors)}")
        nil
    end
  end
  
  defp generate_location(:physical) do
    locations = [
      "123 Main Street, San Francisco, CA 94102",
      "456 Broadway, New York, NY 10013", 
      "789 Olympic Blvd, Los Angeles, CA 90015",
      "321 Pike Place, Seattle, WA 98101",
      "654 Deep Ellum, Dallas, TX 75226",
      "987 Music Row, Nashville, TN 37203",
      "147 Bourbon Street, New Orleans, LA 70116",
      "258 Congress Ave, Austin, TX 78701",
      "369 Lincoln Road, Miami Beach, FL 33139",
      "741 Newbury Street, Boston, MA 02116"
    ]
    
    {false, nil, Enum.random(locations)}
  end
  
  defp generate_location(:virtual) do
    {true, "https://zoom.us/j/#{:rand.uniform(999999999)}", nil}
  end
  
  defp generate_location(:hybrid) do
    if :rand.uniform(2) == 1 do
      generate_location(:physical)
    else
      generate_location(:virtual)
    end
  end
  
  defp create_polls_for_event(event, poll_configs, organizer, participants) do
    Enum.with_index(poll_configs, fn poll_config, index ->
      # Create poll with relative deadlines
      list_deadline = DateTime.add(DateTime.utc_now(), (2 + index) * 24 * 60 * 60, :second)
      voting_deadline = DateTime.add(list_deadline, 3 * 24 * 60 * 60, :second)
      
      poll_params = %{
        title: poll_config.title,
        description: poll_config.description,
        poll_type: poll_config.poll_type,
        voting_system: poll_config.voting_system,
        event_id: event.id,
        created_by_id: organizer.id,
        list_building_deadline: list_deadline,
        voting_deadline: voting_deadline,
        order_index: index
      }
      
      case Events.create_poll(poll_params) do
        {:ok, poll} ->
          # Add poll options based on type
          create_poll_options(poll, poll_config, organizer)
          
          # Add some votes from participants to make it realistic
          if length(participants) > 0 do
            add_sample_votes(poll, participants)
          end
          
          Logger.info("  Created poll: #{poll.title} (#{poll.voting_system})")
          poll
          
        {:error, changeset} ->
          Logger.error("Failed to create poll: #{inspect(changeset.errors)}")
          nil
      end
    end)
    |> Enum.filter(&(&1))
  end
  
  defp create_poll_options(poll, poll_config, organizer) do
    options = get_sample_options(poll_config.poll_type)
    
    Enum.each(options, fn option_title ->
      option_params = %{
        title: option_title,
        poll_id: poll.id,
        suggested_by_id: organizer.id
      }
      
      case Events.create_poll_option(option_params) do
        {:ok, _option} -> :ok
        {:error, _changeset} -> Logger.warning("Failed to create poll option: #{option_title}")
      end
    end)
  end
  
  defp get_sample_options("date_selection") do
    # Generate future dates relative to now
    base_date = Date.utc_today()
    [
      Date.add(base_date, 3) |> Date.to_string(),
      Date.add(base_date, 7) |> Date.to_string(), 
      Date.add(base_date, 10) |> Date.to_string(),
      Date.add(base_date, 14) |> Date.to_string()
    ]
  end
  
  defp get_sample_options("movie") do
    [
      "Inception", "The Dark Knight", "Pulp Fiction", 
      "The Shawshank Redemption", "Forrest Gump", "The Matrix"
    ]
  end
  
  defp get_sample_options("places") do
    [
      "The Italian Corner", "Sushi Zen", "Blue Moon Café", 
      "The Garden Restaurant", "Spice Kitchen", "Ocean View"
    ]
  end
  
  defp get_sample_options("venue") do
    [
      "Downtown Music Hall", "Riverside Amphitheater", "The Jazz Club",
      "Community Center", "Park Pavilion", "Historic Theater"
    ]
  end
  
  defp get_sample_options("time") do
    [
      "6:00 PM - 8:00 PM", "7:00 PM - 9:00 PM", "8:00 PM - 10:00 PM",
      "5:30 PM - 7:30 PM", "6:30 PM - 8:30 PM"
    ]
  end
  
  defp get_sample_options("custom") do
    [
      "Option A", "Option B", "Option C", "Option D"
    ]
  end
  
  defp get_sample_options("general") do
    [
      "$10-20 per person", "$20-35 per person", "$35-50 per person",
      "Casual dining", "Fine dining", "Food trucks"
    ]
  end
  
  defp get_sample_options(_) do
    ["Option 1", "Option 2", "Option 3", "Option 4"]
  end
  
  defp add_sample_votes(poll, participants) do
    # Get poll options
    poll_with_options = Repo.preload(poll, :poll_options)
    
    # Have some participants vote
    voting_participants = Enum.take_random(participants, Enum.random(1..min(3, length(participants))))
    
    Enum.each(voting_participants, fn participant ->
      # Create different voting patterns based on voting system
      case poll.voting_system do
        "binary" ->
          # Vote yes/no on random options
          options_to_vote = Enum.take_random(poll_with_options.poll_options, Enum.random(1..2))
          Enum.each(options_to_vote, fn option ->
            vote_value = if :rand.uniform(3) > 1, do: 1, else: 0  # 66% yes, 33% no
            Events.create_poll_vote(option, participant, %{value: vote_value}, "binary")
          end)
          
        "approval" ->
          # Select multiple options
          options_to_vote = Enum.take_random(poll_with_options.poll_options, Enum.random(1..3))
          Enum.each(options_to_vote, fn option ->
            Events.create_poll_vote(option, participant, %{approved: true}, "approval")
          end)
          
        "ranked" ->
          # Rank top 3 options
          options_to_rank = Enum.take_random(poll_with_options.poll_options, Enum.random(2..3))
          Enum.with_index(options_to_rank, 1) |> Enum.each(fn {option, rank} ->
            Events.create_poll_vote(option, participant, %{rank: rank}, "ranked")
          end)
          
        "star" ->
          # Rate random options 1-5 stars
          options_to_rate = Enum.take_random(poll_with_options.poll_options, Enum.random(2..4))
          Enum.each(options_to_rate, fn option ->
            rating = Enum.random(1..5)
            Events.create_poll_vote(option, participant, %{rating: rating}, "star")
          end)
      end
    end)
  end
end

# Run the diverse polling events seeding
DiversePollingEventsSeed.run()