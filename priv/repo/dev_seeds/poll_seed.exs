# Poll and Voting Seeding Module
# Creates polls with votes for testing, especially RCV movie polls

alias EventasaurusApp.{Repo, Events, Accounts}
alias EventasaurusApp.Events.{Poll, PollOption}
alias EventasaurusWeb.Services.TmdbService
alias EventasaurusWeb.Services.MovieConfig
alias EventasaurusWeb.Services.MovieDataAdapter
alias EventasaurusWeb.Services.GooglePlaces.TextSearch
alias EventasaurusWeb.Services.GooglePlaces.Photos
import Ecto.Query
require Logger

defmodule PollSeed do
  @moduledoc """
  Seeds polls with comprehensive voting data for testing.
  Priority on Ranked Choice Voting movie polls for debugging.
  """

  def run do
    Logger.info("Starting poll seeding...")

    # Load curated data for realistic content
    Code.require_file("curated_data.exs", __DIR__)

    # Get users and events
    users = get_users()
    events = get_events()

    if length(users) < 10 do
      Logger.error("Not enough users! Need at least 10 users for realistic voting.")
      exit(:insufficient_users)
    end

    if length(events) == 0 do
      Logger.error("No events found! Please run event seeding first.")
      exit(:no_events)
    end

    # Seed polls for events
    Enum.each(events, fn event ->
      seed_polls_for_event(event, users)
    end)

    Logger.info("Poll seeding complete!")
  end

  defp get_users do
    Repo.all(from(u in Accounts.User, limit: 50))
  end

  defp get_events do
    # Get a mix of events in different states
    Repo.all(
      from(e in Events.Event,
        where: e.status in [:draft, :confirmed, :polling],
        limit: 20,
        order_by: [desc: e.inserted_at]
      )
    )
    |> Repo.preload(:users)
  end

  defp seed_polls_for_event(event, all_users) do
    Logger.info("Seeding polls for event: #{event.title}")

    # Get participants for this event (or use random users)
    participants = get_event_participants(event, all_users)
    
    # Defensive check: Skip if not enough participants
    if length(participants) < 2 do
      Logger.info("Skipping poll creation for '#{event.title}' - insufficient participants (#{length(participants)})")
      nil
    else

    # Check if this event belongs to movie_buff or foodie_friend
    event_with_users = Repo.preload(event, :users)
    movie_buff = Accounts.get_user_by_email("movie_buff@example.com")
    foodie_friend = Accounts.get_user_by_email("foodie_friend@example.com")

    is_movie_buff_event =
      movie_buff && Enum.any?(event_with_users.users, fn u -> u.id == movie_buff.id end)

    is_foodie_event =
      foodie_friend && Enum.any?(event_with_users.users, fn u -> u.id == foodie_friend.id end)

    # Determine poll types based on event owner and title
    cond do
      # PRIORITY: Movie buff should always get movie RCV polls
      is_movie_buff_event || String.contains?(String.downcase(event.title), "movie") ->
        Logger.info("Creating RCV movie poll for movie event: #{event.title}")
        create_movie_rcv_poll(event, participants)

      # PRIORITY: Foodie friend gets restaurant/food selection polls
      is_foodie_event || String.contains?(String.downcase(event.title), "dinner") ||
          String.contains?(String.downcase(event.title), "restaurant") ->
        Logger.info("Creating restaurant selection poll for food event: #{event.title}")
        create_restaurant_selection_poll(event, participants)

      String.contains?(String.downcase(event.title), "date") ->
        create_date_selection_poll(event, participants)

      String.contains?(String.downcase(event.title), "game") ->
        create_game_selection_poll(event, participants)

      true ->
        # Random poll types for other events - but prefer meaningful ones
        poll_type =
          Enum.random([:movie_rcv, :restaurant_selection, :game_approval, :date_selection])

        create_poll_by_type(poll_type, event, participants)
    end
    end  # End of defensive if-else block
  end

  defp get_event_organizer(event) do
    # The event.users association gives us User records directly
    # For seeding, we'll just use the first user or a default
    # In production, we'd need to check the EventUser join table for roles
    case event.users do
      [user | _] -> user.id
      _ -> 1
    end
  end

  defp get_event_participants(event, all_users) do
    participants = Events.list_event_participants(event)

    if length(participants) < 5 do
      # Not enough participants, use random users
      Enum.take_random(all_users, Enum.random(5..15))
    else
      # Convert participants to users
      participant_user_ids = Enum.map(participants, & &1.user_id)
      Enum.filter(all_users, fn user -> user.id in participant_user_ids end)
    end
  end

  # Priority: Movie RCV Poll with real movie data
  defp create_movie_rcv_poll(event, participants) do
    Logger.info("Creating RCV movie poll for event: #{event.id}")

    # Use real movies from TMDB API with fallback to curated data
    movies =
      case fetch_tmdb_movies() do
        [] ->
          Logger.info("No TMDB movies available, using curated data")
          DevSeeds.CuratedData.movies() |> Enum.take_random(7)

        tmdb_movies ->
          Logger.info("Using #{length(tmdb_movies)} TMDB movies for poll")
          Enum.take_random(tmdb_movies, 7)
      end

    if length(movies) < 3 do
      Logger.warning("Not enough movies available, skipping movie poll")
      nil
    else
      # Create the poll
      organizer_id = get_event_organizer(event)

      poll_result =
        Events.create_poll(%{
          event_id: event.id,
          title: "Movie Night Selection",
          description: "Rank your movie preferences for our movie night!",
          poll_type: "movie",
          voting_system: "ranked",
          allow_suggestions: false,
          created_by_id: organizer_id,
          status: "voting"
        })

      poll =
        case poll_result do
          {:ok, poll} ->
            # Use proper phase transition instead of setting phase directly
            case Events.transition_poll_phase(poll, "voting_only") do
              {:ok, poll} ->
                poll

              {:error, reason} ->
                Logger.error("Failed to transition poll phase: #{inspect(reason)}")
                poll
            end

          {:error, reason} ->
            Logger.error("Failed to create movie poll: #{inspect(reason)}")
            nil
        end

      if is_nil(poll) do
        nil
      else
        # Create poll options from movies with real data using adapter
        options =
          Enum.reduce(movies, [], fn movie, acc ->
            case MovieDataAdapter.build_poll_option_attrs(movie, poll.id, organizer_id)
                 |> Events.create_poll_option() do
              {:ok, option} ->
                [option | acc]

              {:error, reason} ->
                Logger.error(
                  "Failed to create poll option for #{movie.title}: #{inspect(reason)}"
                )

                acc
            end
          end)
          |> Enum.reverse()

        if length(options) < 2 do
          Logger.error("Could not create enough poll options, deleting poll")
          Events.delete_poll(poll)
          nil
        else
          # Seed RCV votes with scenarios valid for the number of options
          options_count = length(options)
          scenarios =
            cond do
              options_count >= 5 ->
                [:contested_race, :clear_winner, :multiple_rounds, :exhausted_ballots,
                 :tied_elimination, :second_round_winner, :third_round_winner]
              options_count >= 4 ->
                [:contested_race, :clear_winner, :multiple_rounds, :exhausted_ballots,
                 :tied_elimination, :second_round_winner]
              options_count >= 3 ->
                [:contested_race, :clear_winner, :multiple_rounds, :exhausted_ballots,
                 :tied_elimination]
              true ->
                [:contested_race, :clear_winner, :exhausted_ballots]
            end
          scenario = Enum.random(scenarios)

          seed_rcv_votes(poll, options, participants, scenario)
          Logger.info("Created RCV movie poll with scenario: #{scenario}")
          poll
        end
      end
    end
  end

  defp fetch_tmdb_movies do
    case TmdbService.get_popular_movies(1) do
      {:ok, movies} ->
        Logger.info("Successfully fetched #{length(movies)} popular movies from TMDB")
        # Limit to 10 movies for seeding - adapter handles format conversion
        movies |> Enum.take(10)

      {:error, reason} ->
        Logger.warning("Failed to fetch TMDB movies (#{inspect(reason)}), using fallback data")
        fallback_movies()
    end
  end


  defp fallback_movies do
    # Hardcoded popular movies as fallback
    [
      %{
        tmdb_id: 565_770,
        title: "Blue Beetle",
        overview:
          "Recent college grad Jaime Reyes returns home full of aspirations for his future.",
        poster_path: "/mXLOHHc1Zeuwsl4xYKjKh2280oL.jpg",
        backdrop_path: "/H6j5smdpRqP9a8UnhWp6zfl0SC.jpg",
        release_date: "2023-08-16",
        vote_average: 7.0
      },
      %{
        tmdb_id: 872_585,
        title: "Oppenheimer",
        overview:
          "The story of J. Robert Oppenheimer's role in the development of the atomic bomb.",
        poster_path: "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg",
        backdrop_path: "/fm6KqXpk3M2HVveHwCrBSSBaO0V.jpg",
        release_date: "2023-07-19",
        vote_average: 8.2
      },
      %{
        tmdb_id: 346_698,
        title: "Barbie",
        overview:
          "Barbie and Ken are having the time of their lives in the colorful world of Barbie Land.",
        poster_path: "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg",
        backdrop_path: "/nHf61UzkfFno5X1ofIhugCPus2R.jpg",
        release_date: "2023-07-19",
        vote_average: 7.3
      },
      %{
        tmdb_id: 299_054,
        title: "The Expanse",
        overview: "A thriller set in a future where humanity has colonized the Solar System.",
        poster_path: "/5Ex9ZTDgerZL9oAGJwQkPjVnUqz.jpg",
        backdrop_path: "/r21HmSn6SjOZjfYkFREWP1ydQJh.jpg",
        release_date: "2023-06-01",
        vote_average: 7.5
      },
      %{
        tmdb_id: 667_538,
        title: "Transformers: Rise of the Beasts",
        overview: "Optimus Prime and the Autobots face a new threat.",
        poster_path: "/gPbM0MK8CP8A174rmUwGsADNYKD.jpg",
        backdrop_path: "/xwA90BwZA6sTFaY96JC2HXdg1J8.jpg",
        release_date: "2023-06-06",
        vote_average: 7.1
      }
    ]
  end


  # Seed RCV votes with specific scenarios
  defp seed_rcv_votes(poll, options, participants, scenario) do
    case scenario do
      :contested_race ->
        seed_contested_rcv(poll, options, participants)

      :clear_winner ->
        seed_clear_winner_rcv(poll, options, participants)

      :multiple_rounds ->
        seed_multiple_rounds_rcv(poll, options, participants)

      :exhausted_ballots ->
        seed_exhausted_ballots_rcv(poll, options, participants)

      :tied_elimination ->
        seed_tied_elimination_rcv(poll, options, participants)

      :second_round_winner ->
        seed_second_round_winner_rcv(poll, options, participants)

      :third_round_winner ->
        seed_third_round_winner_rcv(poll, options, participants)

      _ ->
        seed_contested_rcv(poll, options, participants)
    end
  end

  defp seed_contested_rcv(poll, options, participants) do
    # Close race between first 2 options
    Logger.info("Seeding contested RCV race")

    option_ids = Enum.map(options, & &1.id)
    [favorite1, favorite2 | rest] = option_ids

    Enum.with_index(participants)
    |> Enum.each(fn {user, idx} ->
      ranking =
        if rem(idx, 2) == 0 do
          # Half prefer option 1
          [favorite1, favorite2] ++ Enum.take_random(rest, 2)
        else
          # Half prefer option 2
          [favorite2, favorite1] ++ Enum.take_random(rest, 2)
        end

      cast_ranked_votes(poll, user, ranking)
    end)
  end

  defp seed_clear_winner_rcv(poll, options, participants) do
    # One option gets >50% first choice
    Logger.info("Seeding clear winner RCV")

    option_ids = Enum.map(options, & &1.id)
    [winner | rest] = option_ids

    # 60% vote for winner first
    {winner_voters, other_voters} =
      participants
      |> Enum.split(round(length(participants) * 0.6))

    # Winner voters
    Enum.each(winner_voters, fn user ->
      ranking = [winner | Enum.take_random(rest, 3)]
      cast_ranked_votes(poll, user, ranking)
    end)

    # Other voters spread among rest
    Enum.each(other_voters, fn user ->
      ranking = Enum.shuffle(option_ids) |> Enum.take(4)
      cast_ranked_votes(poll, user, ranking)
    end)
  end

  defp seed_multiple_rounds_rcv(poll, options, participants) do
    # Ensure multiple elimination rounds needed
    Logger.info("Seeding multiple rounds RCV")

    option_ids = Enum.map(options, & &1.id)

    # Distribute first choices evenly to force eliminations
    groups = Enum.chunk_every(participants, div(length(participants), length(options)) + 1)

    Enum.zip(option_ids, groups)
    |> Enum.each(fn {option_id, group} ->
      Enum.each(group || [], fn user ->
        # Start with their preferred option
        rest = List.delete(option_ids, option_id)
        ranking = [option_id | Enum.take_random(rest, 3)]
        cast_ranked_votes(poll, user, ranking)
      end)
    end)
  end

  defp seed_exhausted_ballots_rcv(poll, options, participants) do
    # Some voters only rank 1-2 choices
    Logger.info("Seeding exhausted ballots RCV")

    option_ids = Enum.map(options, & &1.id)

    Enum.each(participants, fn user ->
      # Random number of rankings (some incomplete)
      num_rankings = Enum.random([1, 2, 2, 3, 3, 4, 5])
      ranking = Enum.take_random(option_ids, num_rankings)
      cast_ranked_votes(poll, user, ranking)
    end)
  end

  defp seed_tied_elimination_rcv(poll, options, participants) do
    # Create a tie for last place
    Logger.info("Seeding tied elimination RCV")

    option_ids = Enum.map(options, & &1.id)
    [opt1, opt2, opt3 | rest] = option_ids

    # Split participants into groups
    third = div(length(participants), 3)
    {group1, temp} = Enum.split(participants, third)
    {group2, group3} = Enum.split(temp, third)

    # Group 1 prefers opt1
    Enum.each(group1, fn user ->
      cast_ranked_votes(poll, user, [opt1, opt2, opt3])
    end)

    # Group 2 prefers opt2
    Enum.each(group2, fn user ->
      cast_ranked_votes(poll, user, [opt2, opt3, opt1])
    end)

    # Group 3 splits between opt3 and rest (creates tie)
    Enum.with_index(group3)
    |> Enum.each(fn {user, idx} ->
      if rem(idx, 2) == 0 && length(rest) > 0 do
        cast_ranked_votes(poll, user, [opt3, opt1, opt2])
      else
        cast_ranked_votes(poll, user, [Enum.random(rest ++ [opt3]), opt1, opt2])
      end
    end)
  end

  defp seed_second_round_winner_rcv(poll, options, participants) do
    # Design scenario where winner emerges in second round (not first)
    Logger.info("Seeding second round winner RCV")

    option_ids = Enum.map(options, & &1.id)

    # Require at least 4 options for this scenario
    if length(option_ids) < 4 do
      Logger.warning(
        "Need at least 4 options for second round winner scenario, falling back to contested race"
      )

      seed_contested_rcv(poll, options, participants)
    else
      [eventual_winner, first_leader, third_place, fourth_place | rest] = option_ids

      # Calculate voter groups - need enough participants (minimum 10)
      total_voters = length(participants)

      if total_voters < 10 do
        Logger.warning(
          "Need at least 10 voters for second round winner scenario, falling back to contested race"
        )

        seed_contested_rcv(poll, options, participants)
      else
        # Distribution designed to ensure second-round victory:
        # Round 1: first_leader gets plurality but not majority (35%)
        # Round 1: eventual_winner gets second place (30%)  
        # Round 1: third_place and others split remaining votes
        # Round 2: After eliminations, eventual_winner gets majority from redistributed votes

        first_leader_votes = round(total_voters * 0.35)
        eventual_winner_votes = round(total_voters * 0.30)
        third_place_votes = round(total_voters * 0.20)

        _remaining_votes =
          total_voters - first_leader_votes - eventual_winner_votes - third_place_votes

        voters_list = Enum.shuffle(participants)

        # First leader voters: prefer first_leader > third_place > eventual_winner
        {first_leader_voters, rest_voters} = Enum.split(voters_list, first_leader_votes)

        Enum.each(first_leader_voters, fn voter ->
          ranking = [first_leader, third_place, eventual_winner] ++ Enum.take_random(rest, 2)
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Eventual winner voters: prefer eventual_winner > third_place > first_leader  
        {eventual_winner_voters, rest_voters} = Enum.split(rest_voters, eventual_winner_votes)

        Enum.each(eventual_winner_voters, fn voter ->
          ranking = [eventual_winner, third_place, first_leader] ++ Enum.take_random(rest, 2)
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Third place voters: prefer third_place > eventual_winner > first_leader
        # These votes will transfer to eventual_winner when third_place is eliminated
        {third_place_voters, rest_voters} = Enum.split(rest_voters, third_place_votes)

        Enum.each(third_place_voters, fn voter ->
          ranking = [third_place, eventual_winner, first_leader] ++ Enum.take_random(rest, 2)
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Remaining voters: vote for other options but have eventual_winner as second choice
        Enum.each(rest_voters, fn voter ->
          other_options = [fourth_place | rest]

          if length(other_options) > 0 do
            first_choice = Enum.random(other_options)
            ranking = [first_choice, eventual_winner, first_leader, third_place]
            cast_ranked_votes(poll, voter, ranking)
          end
        end)

        Logger.info(
          "Second round winner scenario: #{first_leader_votes} votes for first leader, #{eventual_winner_votes} for eventual winner, #{third_place_votes} for third place"
        )
      end
    end
  end

  defp seed_third_round_winner_rcv(poll, options, participants) do
    # Design scenario where winner emerges in third round (not first or second)
    Logger.info("Seeding third round winner RCV")

    option_ids = Enum.map(options, & &1.id)

    # Require at least 5 options for this scenario
    if length(option_ids) < 5 do
      Logger.warning(
        "Need at least 5 options for third round winner scenario, falling back to multiple rounds"
      )

      seed_multiple_rounds_rcv(poll, options, participants)
    else
      [eventual_winner, first_leader, second_leader, weak_option1, weak_option2 | rest] =
        option_ids

      # Calculate voter groups - need enough participants (minimum 15)
      total_voters = length(participants)

      if total_voters < 15 do
        Logger.warning(
          "Need at least 15 voters for third round winner scenario, falling back to multiple rounds"
        )

        seed_multiple_rounds_rcv(poll, options, participants)
      else
        # Distribution designed to ensure third-round victory:
        # Round 1: first_leader gets plurality (25%), second_leader second (20%), eventual_winner third (18%)
        # Round 1: weak options get small shares to be eliminated first
        # Round 2: weak_option1 eliminated, votes transfer, still no majority
        # Round 3: weak_option2 eliminated, votes transfer to eventual_winner for majority

        first_leader_votes = round(total_voters * 0.25)
        second_leader_votes = round(total_voters * 0.20)
        eventual_winner_votes = round(total_voters * 0.18)
        weak1_votes = round(total_voters * 0.12)
        weak2_votes = round(total_voters * 0.15)

        _remaining_votes =
          total_voters - first_leader_votes - second_leader_votes - eventual_winner_votes -
            weak1_votes - weak2_votes

        voters_list = Enum.shuffle(participants)

        # First leader voters: prefer first_leader > second_leader > weak options > eventual_winner
        {first_leader_voters, rest_voters} = Enum.split(voters_list, first_leader_votes)

        Enum.each(first_leader_voters, fn voter ->
          ranking = [first_leader, second_leader, weak_option1, eventual_winner]
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Second leader voters: prefer second_leader > first_leader > weak options > eventual_winner
        {second_leader_voters, rest_voters} = Enum.split(rest_voters, second_leader_votes)

        Enum.each(second_leader_voters, fn voter ->
          ranking = [second_leader, first_leader, weak_option2, eventual_winner]
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Eventual winner voters: prefer eventual_winner > weak options > leaders
        {eventual_winner_voters, rest_voters} = Enum.split(rest_voters, eventual_winner_votes)

        Enum.each(eventual_winner_voters, fn voter ->
          ranking = [eventual_winner, weak_option1, weak_option2, second_leader]
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Weak option 1 voters: prefer weak_option1 > eventual_winner > leaders
        # These transfers help eventual_winner in later rounds
        {weak1_voters, rest_voters} = Enum.split(rest_voters, weak1_votes)

        Enum.each(weak1_voters, fn voter ->
          ranking = [weak_option1, eventual_winner, first_leader, second_leader]
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Weak option 2 voters: prefer weak_option2 > eventual_winner > leaders  
        # These transfers help eventual_winner win in third round
        {weak2_voters, rest_voters} = Enum.split(rest_voters, weak2_votes)

        Enum.each(weak2_voters, fn voter ->
          ranking = [weak_option2, eventual_winner, second_leader, first_leader]
          cast_ranked_votes(poll, voter, ranking)
        end)

        # Remaining voters: spread among other options with eventual_winner as backup
        Enum.each(rest_voters, fn voter ->
          other_options = rest

          if length(other_options) > 0 do
            first_choice = Enum.random(other_options)
            ranking = [first_choice, eventual_winner, weak_option1, weak_option2]
            cast_ranked_votes(poll, voter, ranking)
          else
            # If no other options, boost eventual_winner
            ranking = [eventual_winner, weak_option1, first_leader, second_leader]
            cast_ranked_votes(poll, voter, ranking)
          end
        end)

        Logger.info(
          "Third round winner scenario: #{first_leader_votes} first leader, #{second_leader_votes} second leader, #{eventual_winner_votes} eventual winner, #{weak1_votes}+#{weak2_votes} weak options"
        )
      end
    end
  end

  defp cast_ranked_votes(_poll, user, option_ids) do
    # Use Events.create_poll_vote/1 for each ranking instead of the convenience function
    option_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {option_id, rank} ->
      # Get the poll option with defensive check
      case Repo.get(EventasaurusApp.Events.PollOption, option_id) do
        nil ->
          Logger.warning("Poll option #{option_id} not found, skipping vote")
          :ok
        
        poll_option ->
          case Events.create_poll_vote(poll_option, user, %{vote_rank: rank}, "ranked") do
            {:ok, _vote} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "Failed to create ranked vote for option #{option_id}, rank #{rank}: #{inspect(reason)}"
              )
          end
      end
    end)
  end

  defp fetch_google_places_restaurants do
    # Search for restaurants using Google Places API with location
    # Using Warsaw, Poland coordinates for more relevant local restaurants
    warsaw_coordinates = {52.2297, 21.0122}
    
    case TextSearch.search("restaurants", %{
      type: "restaurant", 
      location: warsaw_coordinates,
      radius: 5000  # 5km radius
    }) do
      {:ok, [_|_] = places} ->
        Logger.info("Successfully fetched #{length(places)} restaurants from Google Places")
        # Convert Google Places format to our expected format
        places
        |> Enum.take(10)  # Limit to 10 restaurants for seeding
        |> Enum.map(&convert_google_place_to_restaurant_format/1)

      {:error, reason} ->
        Logger.warning("Failed to fetch Google Places restaurants (#{inspect(reason)}), using curated data")
        DevSeeds.CuratedData.restaurants() |> Enum.take(6)

      _ ->
        Logger.warning("Google Places API returned unexpected response, using curated data")
        DevSeeds.CuratedData.restaurants() |> Enum.take(6)
    end
  rescue
    error ->
      Logger.error("Error fetching Google Places restaurants: #{inspect(error)}")
      DevSeeds.CuratedData.restaurants() |> Enum.take(6)
  end

  defp convert_google_place_to_restaurant_format(place) do
    # Extract cuisine type from types array or place description
    cuisine = extract_cuisine_from_place(place)
    
    # Extract price level (Google Places returns 0-4 scale)
    price_range = extract_price_range(place["price_level"])
    
    # Extract image URL from photos
    image_url = Photos.extract_first_image_url(place)

    %{
      name: place["name"] || "Restaurant",
      cuisine: cuisine,
      price: price_range,
      description: place["formatted_address"] || "No description available",
      specialties: [],  # Google Places doesn't provide specialties directly
      rating: place["rating"],
      google_place_id: place["place_id"],
      api_source: "google_places",
      photos: extract_place_photos(place["photos"]),
      image_url: image_url
    }
  end

  defp extract_cuisine_from_place(place) do
    types = place["types"] || []
    
    cond do
      "restaurant" in types && "meal_takeaway" in types -> "Fast Food"
      "bakery" in types -> "Bakery"
      "bar" in types -> "Bar & Grill"  
      "cafe" in types -> "Cafe"
      "meal_delivery" in types -> "Delivery"
      "meal_takeaway" in types -> "Takeaway"
      "food" in types -> "Restaurant"
      true -> "Restaurant"
    end
  end

  defp extract_price_range(price_level) do
    case price_level do
      0 -> "Free"
      1 -> "$"
      2 -> "$$" 
      3 -> "$$$"
      4 -> "$$$$"
      _ -> "$$"  # Default to moderate pricing
    end
  end

  defp extract_place_photos(photos) when is_list(photos) do
    photos
    |> Enum.take(3)  # Limit to 3 photos
    |> Enum.map(fn photo ->
      %{
        photo_reference: photo["photo_reference"],
        width: photo["width"],
        height: photo["height"]
      }
    end)
  end

  defp extract_place_photos(_), do: []

  defp build_restaurant_description(restaurant) do
    case Map.get(restaurant, :api_source) do
      "google_places" ->
        rating_text = if restaurant.rating, do: " • #{restaurant.rating}⭐", else: ""
        "#{restaurant.cuisine} cuisine - #{restaurant.price}#{rating_text}"
      
      _ ->
        # Curated data format
        "#{restaurant.cuisine} cuisine - #{restaurant.price}"
    end
  end

  defp build_restaurant_metadata(restaurant) do
    base_metadata = %{
      "cuisine" => restaurant.cuisine,
      "price_range" => restaurant.price,
      "api_source" => Map.get(restaurant, :api_source, "curated")
    }

    case Map.get(restaurant, :api_source) do
      "google_places" ->
        base_metadata
        |> Map.put("google_place_id", restaurant.google_place_id)
        |> Map.put("rating", restaurant.rating)
        |> Map.put("photos", restaurant.photos)
        |> Map.put("address", restaurant.description)
      
      _ ->
        # Curated data format
        base_metadata
        |> Map.put("description", Map.get(restaurant, :description))
        |> Map.put("specialties", Map.get(restaurant, :specialties, []))
    end
  end

  defp create_restaurant_selection_poll(event, participants) do
    Logger.info("Creating restaurant selection poll")

    organizer_id = get_event_organizer(event)

    {:ok, poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Restaurant Choice",
        description: "Vote for your preferred dining options!",
        poll_type: "places",
        voting_system: "approval",
        created_by_id: organizer_id
      })

    # Use proper phase transition
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")

    # Use real restaurants from Google Places API with fallback to curated data
    restaurants =
      case fetch_google_places_restaurants() do
        [] ->
          Logger.info("No Google Places restaurants available, using curated data")
          DevSeeds.CuratedData.restaurants() |> Enum.take(6)

        google_restaurants ->
          Logger.info("Using real Google Places restaurants for poll options")
          Enum.take(google_restaurants, 6)
      end

    options =
      Enum.map(restaurants, fn restaurant ->
        # Build description based on available data
        description = build_restaurant_description(restaurant)
        
        # Build comprehensive metadata
        metadata = build_restaurant_metadata(restaurant)

        {:ok, option} =
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: restaurant.name,
            description: description,
            suggested_by_id: organizer_id,
            image_url: restaurant.image_url,
            metadata: metadata
          })

        option
      end)

    # Seed approval votes
    Enum.each(participants, fn user ->
      # Each person approves 2-4 restaurants
      Enum.take_random(options, Enum.random(2..4))
      |> Enum.each(fn option ->
        case Events.create_poll_vote(option, user, %{vote_value: "selected"}, "approval") do
          {:ok, _vote} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to create approval vote: #{inspect(reason)}")
        end
      end)
    end)
  end

  # Other poll types
  defp create_date_selection_poll(event, participants) do
    Logger.info("Creating date selection poll")

    organizer_id = get_event_organizer(event)

    {:ok, poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Select Event Date",
        description: "Vote for your preferred dates",
        poll_type: "date_selection",
        voting_system: "binary",
        created_by_id: organizer_id
      })

    # Use proper phase transition
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")

    # Create date options
    dates =
      for i <- 0..4 do
        date = Date.add(Date.utc_today(), i * 7)
        display_date = Calendar.strftime(date, "%B %d, %Y")

        {:ok, option} =
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: display_date,
            description: "Proposed date option",
            suggested_by_id: organizer_id,
            metadata: %{
              "date" => Date.to_iso8601(date),
              "display_date" => display_date,
              "date_type" => "single_date",
              "time" => "19:00",
              "display_time" => "7:00 PM"
            }
          })

        option
      end

    # Seed binary votes
    Enum.each(participants, fn user ->
      Enum.each(Enum.take_random(dates, 3), fn option ->
        vote = Enum.random(["yes", "no", "maybe"])

        case Events.create_poll_vote(option, user, %{vote_value: vote}, "binary") do
          {:ok, _vote} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to create binary vote: #{inspect(reason)}")
        end
      end)
    end)
  end

  defp create_game_selection_poll(event, participants) do
    Logger.info("Creating game selection poll")

    organizer_id = get_event_organizer(event)

    {:ok, poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Choose Game to Play",
        description: "Select all games you'd like to play",
        poll_type: "general",
        voting_system: "approval",
        created_by_id: organizer_id
      })

    # Use proper phase transition
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")

    games = ["Settlers of Catan", "Codenames", "Ticket to Ride", "Wingspan", "Azul", "Splendor"]

    options =
      Enum.map(games, fn game ->
        {:ok, option} =
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: game,
            description: "Board game option",
            suggested_by_id: organizer_id
          })

        option
      end)

    # Seed approval votes
    Enum.each(participants, fn user ->
      # Each person approves 1-4 games
      Enum.take_random(options, Enum.random(1..4))
      |> Enum.each(fn option ->
        case Events.create_poll_vote(option, user, %{vote_value: "selected"}, "approval") do
          {:ok, _vote} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to create approval vote: #{inspect(reason)}")
        end
      end)
    end)
  end

  defp create_poll_by_type(type, event, participants) do
    case type do
      :movie_rcv -> create_movie_rcv_poll(event, participants)
      :restaurant_selection -> create_restaurant_selection_poll(event, participants)
      :game_approval -> create_game_approval_poll(event, participants)
      :date_selection -> create_date_selection_poll(event, participants)
      :threshold -> create_threshold_poll(event, participants)
      _ -> Logger.warning("Unknown poll type: #{type}")
    end
  end

  defp create_game_approval_poll(event, participants) do
    Logger.info("Creating generic approval poll")

    organizer_id = get_event_organizer(event)

    {:ok, poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Activity Selection",
        description: "Choose activities you're interested in",
        poll_type: "general",
        voting_system: "approval",
        created_by_id: organizer_id
      })

    # Use proper phase transition
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")

    activities = ["Hiking", "Museum Visit", "Escape Room", "Bowling", "Karaoke", "Mini Golf"]

    options =
      Enum.map(activities, fn activity ->
        {:ok, option} =
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: activity,
            description: "Proposed activity",
            suggested_by_id: organizer_id
          })

        option
      end)

    Enum.each(participants, fn user ->
      Enum.take_random(options, Enum.random(2..5))
      |> Enum.each(fn option ->
        case Events.create_poll_vote(option, user, %{vote_value: "selected"}, "approval") do
          {:ok, _vote} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to create approval vote: #{inspect(reason)}")
        end
      end)
    end)
  end

  defp create_threshold_poll(event, participants) do
    Logger.info("Creating threshold interest poll")

    organizer_id = get_event_organizer(event)

    {:ok, poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Minimum Attendance Check",
        description: "We need at least 5 people to proceed",
        poll_type: "venue",
        voting_system: "binary",
        created_by_id: organizer_id,
        threshold: 5
      })

    # Use proper phase transition
    {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")

    {:ok, option} =
      Events.create_poll_option(%{
        poll_id: poll.id,
        title: "I will attend",
        description: "Confirm your attendance",
        suggested_by_id: organizer_id
      })

    # Randomly have 30-90% confirm
    attending =
      Enum.take_random(
        participants,
        round(length(participants) * Enum.random(30..90) / 100)
      )

    Enum.each(attending, fn user ->
      case Events.create_poll_vote(option, user, %{vote_value: "yes"}, "binary") do
        {:ok, _vote} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to create binary vote: #{inspect(reason)}")
      end
    end)
  end
end

# Run the seeding
PollSeed.run()
