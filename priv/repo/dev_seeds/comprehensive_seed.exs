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
      
      # Pick visibility first, then constrain join_policy choices to avoid invalid combinations
      visibility = Enum.random(["public", "public", "unlisted", "private"])
      join_policy_pool =
        case visibility do
          "private" -> ["request", "invite_only"]  # Private groups cannot be open
          _ -> ["open", "open", "request", "invite_only"]
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
    Logger.info("Creating 120 diverse events...")
    
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
      
      # Future events (50+)
      %{time_offset: 3, status: "confirmed", title_prefix: "Weekend Adventure", participant_range: 4..12},
      %{time_offset: 7, status: "draft", title_prefix: "Draft Planning Session", participant_range: 0..0},
      %{time_offset: 10, status: "polling", title_prefix: "Polling for Date", participant_range: 2..8},
      %{time_offset: 14, status: "confirmed", title_prefix: "Upcoming Conference", participant_range: 15..50},
      %{time_offset: 21, status: "threshold", title_prefix: "Minimum Attendees Event", participant_range: 3..6},
      %{time_offset: 30, status: "confirmed", title_prefix: "Next Month's Gathering", participant_range: 8..25},
      %{time_offset: 45, status: "draft", title_prefix: "Future Project Kickoff", participant_range: 0..3},
      %{time_offset: 60, status: "confirmed", title_prefix: "Summer Festival", participant_range: 20..100},
      %{time_offset: 90, status: "cancelled", title_prefix: "Cancelled Future Event", participant_range: 0..0},
    ]
    
    event_types = [
      "Workshop", "Conference", "Meetup", "Party", "Dinner", "Lunch",
      "Game Night", "Movie Night", "Hike", "Concert", "Talk", "Class",
      "Festival", "Retreat", "Hackathon", "Tournament", "Exhibition",
      "Networking", "Fundraiser", "Launch Party"
    ]
    
    created_events = []
    
    # Create 120 events with good variety
    for i <- 1..120 do
      template = Enum.random(event_templates)
      event_type = Enum.random(event_types)
      organizer = Enum.random(users)
      group = if rem(i, 3) == 0 && length(groups) > 0, do: Enum.random(groups), else: nil
      
      # Determine visibility
      visibility = Enum.random(["public", "public", "public", "private", "unlisted"])
      
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
        is_virtual: rem(i, 4) == 0,
        virtual_venue_url: if(rem(i, 4) == 0, do: "https://zoom.us/j/#{:rand.uniform(999999999)}", else: nil),
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
          
          if rem(i, 10) == 0 do
            Logger.info("Created #{i}/120 events...")
          end
          
          event
          
        {:error, changeset} ->
          Logger.error("Failed to create event: #{inspect(changeset.errors)}")
          nil
      end
    end
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
end

# Run the comprehensive seeding
ComprehensiveSeed.run()