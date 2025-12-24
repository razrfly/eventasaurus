# Diverse Polling Events - Phase I Implementation
# Creates date + movie star rating polls with future dates
# Addresses Phase I requirements from issue #900

alias EventasaurusApp.{Repo, Events, Accounts, Groups}
import Ecto.Query
require Logger

defmodule DiversePollingEvents do
  @moduledoc """
  Phase I Implementation: Date + Movie Star Rating Polls
  
  This creates events with:
  1. Date polls - always future dates relative to seed run time
  2. Movie star rating polls - different from existing RCV polls
  3. 3-5 diverse poll combinations per seed group
  """

  def run do
    Logger.info("Starting Phase I: Diverse polling events with future dates...")

    # Load curated movie data
    Code.require_file("../../support/curated_data.exs", __DIR__)
    
    users = get_users()
    groups = get_groups()
    
    if length(users) < 5 do
      Logger.error("Need at least 5 users for realistic polling")
      exit(:insufficient_users)
    end
    
    # Create 15 events with date + movie star rating polls
    create_date_movie_poll_events(users, groups)
    
    Logger.info("Phase I diverse polling events complete!")
  end
  
  defp get_users do
    Repo.all(from(u in Accounts.User, limit: 15))
  end
  
  defp get_groups do
    Repo.all(Groups.Group) |> Enum.take(10)
  end
  
  defp create_date_movie_poll_events(users, groups) do
    Logger.info("Creating 15 events with date + movie star rating polls...")

    # Load helpers for image assignment
    Code.require_file("../../support/helpers.exs", __DIR__)
    
    # Date + Movie combination templates
    event_templates = [
      %{
        title_template: "Movie Night: Pick Date & Film", 
        description_template: "Let's plan our movie night! First vote on the date, then rate your movie preferences.",
        days_ahead: 7..30
      },
      %{
        title_template: "Weekend Movie Marathon Planning",
        description_template: "Planning our weekend movie marathon. Vote for the best weekend and rate the movies you'd like to watch.",
        days_ahead: 14..45
      },
      %{
        title_template: "Cinema Club: Date & Movie Selection",
        description_template: "Our monthly cinema club needs your input on when to meet and what to watch.",
        days_ahead: 21..60
      },
      %{
        title_template: "Drive-In Movie Event Planning",
        description_template: "Planning a drive-in movie experience. Help us pick the perfect date and movies to show.",
        days_ahead: 10..35
      },
      %{
        title_template: "Movie & Discussion Night Setup",
        description_template: "Setting up our next movie discussion night. Choose your preferred date and rate the movies for discussion potential.",
        days_ahead: 12..40
      }
    ]
    
    # Create 15 events (3 per template)
    Enum.each(event_templates, fn template ->
      Enum.each(1..3, fn iteration ->
        organizer = Enum.random(users)
        group = if rem(iteration, 2) == 0 && length(groups) > 0, do: Enum.random(groups), else: nil
        
        # Generate future dates relative to now
        days_ahead = Enum.random(template.days_ahead)
        base_date = DateTime.utc_now() |> DateTime.add(days_ahead * 24 * 60 * 60, :second)
        
        event_params = Map.merge(%{
          title: "#{template.title_template} ##{iteration}",
          description: template.description_template,
          start_at: base_date,
          ends_at: DateTime.add(base_date, 3 * 60 * 60, :second), # 3 hours later
          timezone: "America/Los_Angeles",
          visibility: "public",
          status: :polling,
          group_id: group && group.id,
          is_virtual: true, # Phase I focuses on polling, Phase II adds venues
          virtual_venue_url: "https://zoom.us/j/#{:rand.uniform(999999999)}",
          polling_deadline: DateTime.add(base_date, -3 * 24 * 60 * 60, :second) # 3 days before event
        }, DevSeeds.Helpers.get_random_image_attrs())
        
        case Events.create_event(event_params) do
          {:ok, event} ->
            # Add organizer
            Events.add_user_to_event(event, organizer, "organizer")
            
            # Add 4-8 participants for realistic voting
            participant_count = Enum.random(4..8)
            participants = users
              |> Enum.reject(&(&1.id == organizer.id))
              |> Enum.take_random(participant_count)

            Enum.each(participants, fn participant ->
              case Events.create_event_participant(%{
                event_id: event.id,
                user_id: participant.id,
                status: "accepted",
                role: "poll_voter"
              }) do
                {:ok, _} -> :ok
                {:error, changeset} ->
                  Logger.warning("Failed to add participant #{participant.id} to event #{event.id}: #{inspect(changeset.errors)}")
              end
            end)
            
            # Create Phase I polls: Date poll + Movie star rating poll
            create_date_poll(event)
            create_movie_star_rating_poll(event)
            
            # Create voting data for realism
            all_participants = [organizer | participants]
            create_realistic_voting_data(event, all_participants)
            
            Logger.info("Created event with polls: #{event.title}")
            
          {:error, changeset} ->
            Logger.error("Failed to create event: #{inspect(changeset.errors)}")
        end
      end)
    end)
  end
  
  defp create_date_poll(event) do
    Logger.debug("Creating date poll for event: #{event.title}")

    organizer_id = get_event_organizer(event)

    # Generate 3-4 future date options relative to the event date
    base_date = event.start_at

    date_options = [
      DateTime.add(base_date, -2 * 24 * 60 * 60, :second), # 2 days earlier
      base_date, # Original date
      DateTime.add(base_date, 1 * 24 * 60 * 60, :second), # 1 day later
      DateTime.add(base_date, 3 * 24 * 60 * 60, :second)  # 3 days later
    ]
    |> Enum.map(fn date ->
      Calendar.strftime(date, "%A, %B %-d at %-I:%M %p")
    end)

    poll_params = %{
      event_id: event.id,
      title: "What date works best for everyone?",
      description: "Vote for your preferred event date",
      poll_type: "date_selection", # Use supported poll type
      voting_system: "binary", # Use supported voting system
      created_by_id: organizer_id,
      voting_deadline: event.polling_deadline
    }

    case Events.create_poll(poll_params) do
      {:ok, poll} ->
        # Use proper phase transition
        case Events.transition_poll_phase(poll, "voting_only") do
          {:ok, transitioned_poll} ->
            # Create date options
            Enum.each(date_options, fn option ->
              case Events.create_poll_option(%{
                poll_id: transitioned_poll.id,
                title: option,
                description: "Proposed date option",
                suggested_by_id: organizer_id,
                metadata: %{
                  "date_type" => "single_date"
                }
              }) do
                {:ok, _option} -> :ok
                {:error, reason} ->
                  Logger.warning("Failed to create poll option: #{inspect(reason)}")
              end
            end)

            Logger.debug("Created date poll with #{length(date_options)} options")
            {:ok, transitioned_poll}

          {:error, transition_error} ->
            Logger.error("Failed to transition poll phase: #{inspect(transition_error)}")
            {:error, transition_error}
        end

      {:error, changeset} ->
        Logger.error("Failed to create date poll: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end
  
  defp create_movie_star_rating_poll(event) do
    Logger.debug("Creating movie star rating poll for event: #{event.title}")

    organizer_id = get_event_organizer(event)

    # Get 4-5 popular movies from curated data
    movies = DevSeeds.CuratedData.movies()
      |> Enum.take_random(5)

    poll_params = %{
      event_id: event.id,
      title: "Rate these movie options (5 stars = most excited to watch)",
      description: "Rate each movie from 1-5 stars based on how excited you are to watch it",
      poll_type: "movie", # Use supported poll type for movies
      voting_system: "star", # Use supported star voting system
      created_by_id: organizer_id,
      voting_deadline: event.polling_deadline
    }

    case Events.create_poll(poll_params) do
      {:ok, poll} ->
        # Use proper phase transition
        case Events.transition_poll_phase(poll, "voting_only") do
          {:ok, transitioned_poll} ->
            # Create movie options with rich data
            Enum.each(movies, fn movie ->
              case Events.create_poll_option(%{
                poll_id: transitioned_poll.id,
                title: movie.title,
                description: "#{movie.year} • #{movie.genre} • ★#{movie.rating}/10\n#{movie.description}",
                suggested_by_id: organizer_id,
                metadata: %{
                  "year" => movie.year,
                  "genre" => movie.genre,
                  "tmdb_rating" => movie.rating,
                  "tmdb_id" => movie.tmdb_id
                }
              }) do
                {:ok, _option} -> :ok
                {:error, reason} ->
                  Logger.warning("Failed to create movie poll option: #{inspect(reason)}")
              end
            end)

            Logger.debug("Created star rating poll with #{length(movies)} movie options")
            {:ok, transitioned_poll}

          {:error, transition_error} ->
            Logger.error("Failed to transition poll phase: #{inspect(transition_error)}")
            {:error, transition_error}
        end

      {:error, changeset} ->
        Logger.error("Failed to create movie star rating poll: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end
  
  defp get_event_organizer(event) do
    # Find the organizer from event users
    query = from eu in "event_users", 
      where: eu.event_id == ^event.id and eu.role == "organizer",
      select: eu.user_id,
      limit: 1
    
    case Repo.one(query) do
      nil -> 
        Logger.warning("No organizer found for event #{event.id}, using event creator")
        # Fallback to first user if no organizer found
        1 # Default user ID
      user_id -> user_id
    end
  end
  
  defp create_realistic_voting_data(event, participants) do
    Logger.debug("Creating realistic voting data for #{length(participants)} participants")
    
    # Get the polls for this event using the correct function
    polls = Events.list_polls(event)
    
    # Create varied voting patterns
    Enum.each(participants, fn participant ->
      Enum.each(polls, fn poll ->
        options = Repo.all(from po in EventasaurusApp.Events.PollOption, where: po.poll_id == ^poll.id)
        
        case poll.voting_system do
          "binary" ->
            # Date polls - each person votes yes/no/maybe for dates
            Enum.each(Enum.take_random(options, 3), fn option ->
              vote = Enum.random(["yes", "no", "maybe"])
              case Events.create_poll_vote(option, participant, %{vote_value: vote}, "binary") do
                {:ok, _vote} -> :ok
                {:error, reason} -> Logger.warning("Failed to create binary vote: #{inspect(reason)}")
              end
            end)
            
          "star" ->
            # Movie star rating - rate each movie 1-5 stars
            Enum.each(options, fn option ->
              # Generate realistic ratings (bias toward 3-5 stars for popular movies)
              rating = case :rand.uniform(100) do
                n when n <= 10 -> 1  # 10% give 1 star
                n when n <= 25 -> 2  # 15% give 2 stars  
                n when n <= 50 -> 3  # 25% give 3 stars
                n when n <= 80 -> 4  # 30% give 4 stars
                _ -> 5               # 20% give 5 stars
              end
              
              case Events.create_poll_vote(option, participant, %{vote_value: "star", vote_numeric: Decimal.new(rating)}, "star") do
                {:ok, _vote} -> :ok
                {:error, reason} -> Logger.warning("Failed to create star vote: #{inspect(reason)}")
              end
            end)
        end
      end)
    end)
    
    Logger.debug("Completed voting data creation")
  end
end

# Run the diverse polling events seeding
DiversePollingEvents.run()