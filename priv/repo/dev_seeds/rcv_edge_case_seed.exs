# RCV Edge Case Seeding Script
# Creates specific edge cases for testing the leaderboard component

alias EventasaurusApp.{Repo, Events, Accounts}
alias EventasaurusApp.Events.{Poll, PollOption}
import Ecto.Query
require Logger

defmodule RCVEdgeCaseSeed do
  @moduledoc """
  Creates specific RCV edge cases for testing leaderboard display:
  1. Second-round winner (elimination required)
  2. Third-round winner (multiple eliminations)
  3. Exhausted ballots scenario
  4. Very close race (margins <2%)
  5. Landslide victory (>70% first choice)
  """

  def run do
    Logger.info("Creating RCV edge case test data...")
    
    # Get or create test users
    users = get_or_create_test_users()
    event = get_or_create_test_event(users)
    
    # Clean up existing polls for this event to avoid conflicts
    existing_polls = Events.list_polls_for_event(event)
    Enum.each(existing_polls, fn poll ->
      if String.contains?(poll.title, "Edge Case") do
        Events.delete_poll(poll)
      end
    end)
    
    # Create edge case scenarios
    create_second_round_winner(event, users)
    create_third_round_winner(event, users)
    create_exhausted_ballots_case(event, users)
    create_very_close_race(event, users)
    create_landslide_victory(event, users)
    
    Logger.info("RCV edge case seed data created successfully!")
  end
  
  defp get_or_create_test_users do
    # Get existing users or create if needed
    users = Repo.all(from u in Accounts.User, limit: 20)
    
    if length(users) < 15 do
      Logger.warning("Not enough users for comprehensive testing. Consider running user seed first.")
      users
    else
      Enum.take(users, 15)
    end
  end
  
  defp get_or_create_test_event(users) do
    organizer = List.first(users)
    
    # Look for existing test event or create one
    case Events.get_event_by_slug("rcv-edge-case-testing") do
      nil ->
        {:ok, event} = Events.create_event(%{
          "title" => "RCV Edge Case Testing",
          "description" => "Event for testing RCV edge cases",
          "start_at" => ~U[2024-12-15 19:00:00Z],
          "timezone" => "UTC",
          "slug" => "rcv-edge-case-testing",
          "status" => :confirmed,
          "taxation_type" => "ticketless"
        })
        
        # Add organizer
        {:ok, _} = Events.add_user_to_event(event, organizer)
        
        Events.get_event!(event.id)
        
      event ->
        event
    end
  end
  
  # Scenario 1: Second Round Winner
  # Winner doesn't have majority in round 1, but wins after elimination
  defp create_second_round_winner(event, users) do
    Logger.info("Creating second-round winner scenario")
    
    organizer = List.first(users)
    {:ok, poll} = Events.create_poll(%{
      event_id: event.id,
      title: "Edge Case: Second Round Winner",
      description: "Movie selection where winner emerges in round 2",
      poll_type: "movie",
      voting_system: "ranked",
      created_by_id: organizer.id,
      status: "voting"
    })
    
    # Transition to voting phase
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
    
    # Create 4 movie options
    movies = [
      "Top Gun: Maverick",
      "Everything Everywhere All at Once", 
      "The Batman",
      "Dune: Part Two"
    ]
    
    options = Enum.map(movies, fn title ->
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: title,
        description: "Popular movie option",
        suggested_by_id: organizer.id,
        metadata: %{"is_movie" => true}
      })
      option
    end)
    
    [opt1, opt2, opt3, opt4] = options
    
    # Vote distribution:
    # Round 1: opt1=6, opt2=4, opt3=3, opt4=2 (no majority, opt4 eliminated)
    # Round 2: opt1=6, opt2=5, opt3=4 (opt1 wins with majority after opt4's votes transfer)
    
    voters = Enum.take(users, 15)
    
    # 6 voters prefer opt1 first
    Enum.take(voters, 6)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt1.id, opt2.id, opt3.id])
    end)
    
    # 4 voters prefer opt2 first
    Enum.slice(voters, 6, 4)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt2.id, opt3.id, opt1.id])
    end)
    
    # 3 voters prefer opt3 first
    Enum.slice(voters, 10, 3)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt3.id, opt1.id, opt2.id])
    end)
    
    # 2 voters prefer opt4 first, but their second choice is opt1 (crucial for round 2)
    Enum.slice(voters, 13, 2)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt4.id, opt1.id, opt2.id])
    end)
  end
  
  # Scenario 2: Third Round Winner  
  # Requires 2 elimination rounds before winner emerges
  defp create_third_round_winner(event, users) do
    Logger.info("Creating third-round winner scenario")
    
    organizer = List.first(users)
    {:ok, poll} = Events.create_poll(%{
      event_id: event.id,
      title: "Edge Case: Third Round Winner",
      description: "Complex elimination requiring 3 rounds",
      poll_type: "movie", 
      voting_system: "ranked",
      created_by_id: organizer.id,
      status: "voting"
    })
    
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
    
    movies = [
      "Oppenheimer",
      "Barbie", 
      "Spider-Man: Across the Spider-Verse",
      "John Wick: Chapter 4",
      "Guardians of the Galaxy Vol. 3"
    ]
    
    options = Enum.map(movies, fn title ->
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: title,
        description: "Blockbuster movie option",
        suggested_by_id: organizer.id,
        metadata: %{"is_movie" => true}
      })
      option
    end)
    
    [opt1, opt2, opt3, opt4, opt5] = options
    voters = Enum.take(users, 15)
    
    # Round 1: opt1=4, opt2=3, opt3=3, opt4=3, opt5=2 (opt5 eliminated)
    # Round 2: opt1=4, opt2=4, opt3=4, opt4=3 (opt4 eliminated) 
    # Round 3: opt1=6, opt2=5, opt3=4 (opt1 wins)
    
    # 4 for opt1 (eventually wins)
    Enum.take(voters, 4)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt1.id, opt3.id, opt2.id])
    end)
    
    # 3 for opt2
    Enum.slice(voters, 4, 3)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt2.id, opt1.id, opt3.id])
    end)
    
    # 3 for opt3
    Enum.slice(voters, 7, 3)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt3.id, opt2.id, opt4.id])
    end)
    
    # 3 for opt4 (will be eliminated in round 2, votes go to opt1)
    Enum.slice(voters, 10, 3)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt4.id, opt1.id, opt2.id])
    end)
    
    # 2 for opt5 (eliminated first, votes transfer to opt1)
    Enum.slice(voters, 13, 2)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt5.id, opt1.id, opt3.id])
    end)
  end
  
  # Scenario 3: Exhausted Ballots
  # Some voters don't rank enough choices
  defp create_exhausted_ballots_case(event, users) do
    Logger.info("Creating exhausted ballots scenario")
    
    organizer = List.first(users)
    {:ok, poll} = Events.create_poll(%{
      event_id: event.id,
      title: "Edge Case: Exhausted Ballots",
      description: "Voters with incomplete rankings",
      poll_type: "movie",
      voting_system: "ranked", 
      created_by_id: organizer.id,
      status: "voting"
    })
    
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
    
    movies = ["Inception", "Interstellar", "The Dark Knight", "Dunkirk"]
    
    options = Enum.map(movies, fn title ->
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: title,
        description: "Christopher Nolan film",
        suggested_by_id: organizer.id,
        metadata: %{"is_movie" => true, "director" => "Christopher Nolan"}
      })
      option
    end)
    
    [opt1, opt2, opt3, opt4] = options
    voters = Enum.take(users, 12)
    
    # 3 voters only rank their #1 choice (will be exhausted after elimination)
    Enum.take(voters, 3)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt4.id]) # Only one choice
    end)
    
    # 3 voters rank only 2 choices  
    Enum.slice(voters, 3, 3)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt3.id, opt4.id]) # Only two choices
    end)
    
    # 6 voters with full rankings
    Enum.slice(voters, 6, 6)
    |> Enum.each(fn user ->
      if rem(user.id, 2) == 0 do
        cast_ranked_votes(poll, user, [opt1.id, opt2.id, opt3.id, opt4.id])
      else
        cast_ranked_votes(poll, user, [opt2.id, opt1.id, opt3.id, opt4.id])
      end
    end)
  end
  
  # Scenario 4: Very Close Race
  # Winner decided by <2% margin
  defp create_very_close_race(event, users) do
    Logger.info("Creating very close race scenario")
    
    organizer = List.first(users)
    {:ok, poll} = Events.create_poll(%{
      event_id: event.id,
      title: "Edge Case: Very Close Race",
      description: "Extremely tight competition",
      poll_type: "movie",
      voting_system: "ranked",
      created_by_id: organizer.id,
      status: "voting"
    })
    
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
    
    movies = ["Avengers: Endgame", "Avatar: The Way of Water", "Black Panther"]
    
    options = Enum.map(movies, fn title ->
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: title,
        description: "Blockbuster option",
        suggested_by_id: organizer.id,
        metadata: %{"is_movie" => true}
      })
      option
    end)
    
    [opt1, opt2, opt3] = options
    voters = Enum.take(users, 13) # Odd number to avoid perfect ties
    
    # Very close first-choice distribution: 5, 4, 4
    # After eliminations: opt1 wins with 7 vs 6 (53.8% vs 46.2%)
    
    # 5 for opt1
    Enum.take(voters, 5)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt1.id, opt2.id, opt3.id])
    end)
    
    # 4 for opt2  
    Enum.slice(voters, 5, 4)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt2.id, opt1.id, opt3.id])
    end)
    
    # 4 for opt3 (eliminated, 2 go to opt1, 2 go to opt2)
    Enum.slice(voters, 9, 4)
    |> Enum.with_index()
    |> Enum.each(fn {user, idx} ->
      if rem(idx, 2) == 0 do
        cast_ranked_votes(poll, user, [opt3.id, opt1.id, opt2.id])
      else
        cast_ranked_votes(poll, user, [opt3.id, opt2.id, opt1.id])
      end
    end)
  end
  
  # Scenario 5: Landslide Victory
  # Winner gets >70% first choice votes
  defp create_landslide_victory(event, users) do
    Logger.info("Creating landslide victory scenario")
    
    organizer = List.first(users)
    {:ok, poll} = Events.create_poll(%{
      event_id: event.id,
      title: "Edge Case: Landslide Victory",
      description: "Overwhelming favorite wins big",
      poll_type: "movie",
      voting_system: "ranked",
      created_by_id: organizer.id,
      status: "voting"
    })
    
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
    
    movies = ["The Godfather", "Citizen Kane", "Pulp Fiction", "The Shawshank Redemption"]
    
    options = Enum.map(movies, fn title ->
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: title,
        description: "Classic film",
        suggested_by_id: organizer.id,
        metadata: %{"is_movie" => true, "genre" => "Classic"}
      })
      option
    end)
    
    [opt1, opt2, opt3, opt4] = options
    voters = Enum.take(users, 14)
    
    # 10 voters (71.4%) choose opt1 first - clear majority
    Enum.take(voters, 10)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt1.id, opt2.id, opt3.id])
    end)
    
    # 2 voters for opt2
    Enum.slice(voters, 10, 2)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt2.id, opt3.id, opt4.id])
    end)
    
    # 1 voter for opt3
    Enum.slice(voters, 12, 1)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt3.id, opt4.id, opt1.id])
    end)
    
    # 1 voter for opt4
    Enum.slice(voters, 13, 1)
    |> Enum.each(fn user ->
      cast_ranked_votes(poll, user, [opt4.id, opt1.id, opt2.id])
    end)
  end
  
  defp cast_ranked_votes(poll, user, option_ids) do
    option_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {option_id, rank} ->
      poll_option = Events.get_poll_option!(option_id)
      
      case Events.create_poll_vote(poll_option, user, %{vote_rank: rank}, "ranked") do
        {:ok, _vote} -> :ok
        {:error, reason} ->
          Logger.warning("Failed to create vote: #{inspect(reason)}")
      end
    end)
  end
end

# Run the seed
RCVEdgeCaseSeed.run()