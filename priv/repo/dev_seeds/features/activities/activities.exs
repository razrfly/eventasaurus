# Activity Seeding Module
# Creates activities for events using real API data, following polling patterns

alias EventasaurusApp.{Repo, Events, Accounts}
alias EventasaurusWeb.Services.TmdbService
alias EventasaurusWeb.Services.MovieDataAdapter
alias EventasaurusWeb.Services.GooglePlaces.TextSearch
alias EventasaurusWeb.Services.GooglePlaces.Photos
import Ecto.Query
require Logger

defmodule ActivitySeed do
  @moduledoc """
  Seeds activities for events using real API data.
  Follows the same patterns established in poll_seed.exs for consistency.
  """

  def run do
    Logger.info("Starting activity seeding...")

    # Load curated data for realistic content
    Code.require_file("../../support/curated_data.exs", __DIR__)

    # Get users and events
    users = get_users()
    events = get_events()

    if length(users) < 5 do
      Logger.error("Not enough users! Need at least 5 users for realistic activities.")
      exit(:insufficient_users)
    end

    if length(events) == 0 do
      Logger.error("No events found! Please run event seeding first.")
      exit(:no_events)
    end

    # Seed activities for events in parallel
    Logger.info("Seeding activities for #{length(events)} events in parallel (max concurrency: 10)...")

    events
    |> Task.async_stream(
      fn event -> seed_activities_for_event(event, users) end,
      max_concurrency: 10,
      timeout: :infinity,
      on_timeout: :kill_task
    )
    |> Stream.run()

    Logger.info("Activity seeding complete!")
  end

  defp get_users do
    Repo.all(from(u in Accounts.User, limit: 50))
  end

  defp get_events do
    # Get events in confirmed status for activities (these are the ones that actually happened)
    Repo.all(
      from(e in Events.Event,
        where: e.status == :confirmed,
        limit: 30,
        order_by: [desc: e.inserted_at]
      )
    )
    |> Repo.preload(:users)
  end

  defp seed_activities_for_event(event, all_users) do
    Logger.info("Seeding activities for event: #{event.title}")

    # Get event organizer
    event_with_users = Repo.preload(event, :users)
    organizer = get_event_organizer(event, all_users)

    # Check if this event belongs to specific personas
    movie_buff = Accounts.get_user_by_email("movie_buff@example.com")
    foodie_friend = Accounts.get_user_by_email("foodie_friend@example.com")

    is_movie_buff_event =
      movie_buff && Enum.any?(event_with_users.users, fn u -> u.id == movie_buff.id end)

    is_foodie_event =
      foodie_friend && Enum.any?(event_with_users.users, fn u -> u.id == foodie_friend.id end)

    # Determine activity types based on event owner and title
    cond do
      # Movie events get movie activities
      is_movie_buff_event || String.contains?(String.downcase(event.title), "movie") ->
        Logger.info("Creating movie activity for movie event: #{event.title}")
        create_movie_activity(event, organizer)

      # Food events get restaurant activities
      is_foodie_event || String.contains?(String.downcase(event.title), "dinner") ||
          String.contains?(String.downcase(event.title), "restaurant") ->
        Logger.info("Creating restaurant activity for food event: #{event.title}")
        create_restaurant_activity(event, organizer)

      String.contains?(String.downcase(event.title), "game") ->
        create_game_activity(event, organizer)

      String.contains?(String.downcase(event.title), "book") ->
        create_book_activity(event, organizer)

      true ->
        # Random activity types for other events
        activity_type = Enum.random([:movie, :restaurant, :game, :book, :custom])

        case activity_type do
          :movie -> create_movie_activity(event, organizer)
          :restaurant -> create_restaurant_activity(event, organizer)
          :game -> create_game_activity(event, organizer)
          :book -> create_book_activity(event, organizer)
          :custom -> create_custom_activity(event, organizer)
        end
    end
  end

  defp create_movie_activity(event, organizer) do
    Logger.info("Creating movie activity for event: #{event.id}")

    # Use real movies from TMDB API with fallback to curated data (same pattern as polling)
    movie =
      case fetch_tmdb_movies() do
        [] ->
          Logger.info("No TMDB movies available, using curated data")
          Enum.random(DevSeeds.CuratedData.movies())

        tmdb_movies ->
          Logger.info("Using real TMDB movie for activity")
          Enum.random(tmdb_movies)
      end

    # Create activity with rich metadata using adapter
    {:ok, _activity} =
      Events.create_event_activity(%{
        event_id: event.id,
        activity_type: "movie_watched",
        created_by_id: organizer.id,
        occurred_at: event.start_at || DateTime.utc_now(),
        source: "seed_data",
        metadata: MovieDataAdapter.build_activity_metadata(movie)
      })

    Logger.info("Created movie activity: #{movie.title}")
  end

  defp create_restaurant_activity(event, organizer) do
    Logger.info("Creating restaurant activity for event: #{event.id}")

    # Use real restaurants from Google Places API with fallback to curated data
    restaurant =
      case fetch_google_places_restaurants() do
        [] ->
          Logger.info("No Google Places restaurants available, using curated data")
          Enum.random(DevSeeds.CuratedData.restaurants())

        google_restaurants ->
          Logger.info("Using real Google Places restaurant for activity")
          Enum.random(google_restaurants)
      end

    {:ok, _activity} =
      Events.create_event_activity(%{
        event_id: event.id,
        activity_type: "restaurant_visited",
        created_by_id: organizer.id,
        occurred_at: event.start_at || DateTime.utc_now(),
        source: "seed_data",
        metadata: build_restaurant_activity_metadata(restaurant)
      })

    Logger.info("Created restaurant activity: #{restaurant.name}")
  end

  defp create_game_activity(event, organizer) do
    # Use board games from curated data
    game = Enum.random(DevSeeds.CuratedData.games().board_games)

    {:ok, _activity} =
      Events.create_event_activity(%{
        event_id: event.id,
        activity_type: "game_played",
        created_by_id: organizer.id,
        occurred_at: event.start_at || DateTime.utc_now(),
        source: "seed_data",
        metadata: %{
          "name" => game.name,
          "players" => game.players,
          "duration" => game.duration,
          "description" => game.description,
          "game_type" => "board_game",
          "api_source" => "curated",
          "seeded_at" => DateTime.utc_now()
        }
      })

    Logger.info("Created game activity: #{game.name}")
  end

  defp create_book_activity(event, organizer) do
    book = Enum.random(DevSeeds.CuratedData.books())

    {:ok, _activity} =
      Events.create_event_activity(%{
        event_id: event.id,
        activity_type: "book_read",
        created_by_id: organizer.id,
        occurred_at: event.start_at || DateTime.utc_now(),
        source: "seed_data",
        metadata: %{
          "title" => book.title,
          "author" => book.author,
          "genre" => book.genre,
          "description" => book.description,
          "api_source" => "curated",
          "seeded_at" => DateTime.utc_now()
        }
      })

    Logger.info("Created book activity: #{book.title}")
  end

  defp create_custom_activity(event, organizer) do
    activity_names = [
      "Yoga Session",
      "Photography Walk",
      "Cooking Workshop",
      "Art Class",
      "Music Jam Session",
      "Hiking Adventure",
      "Beach Cleanup",
      "Volunteer Work",
      "Workshop Attendance",
      "Networking Event"
    ]

    activity_name = Enum.random(activity_names)

    {:ok, _activity} =
      Events.create_event_activity(%{
        event_id: event.id,
        activity_type: "activity_completed",
        created_by_id: organizer.id,
        occurred_at: event.start_at || DateTime.utc_now(),
        source: "seed_data",
        metadata: %{
          "name" => activity_name,
          "category" => "general",
          "api_source" => "curated",
          "seeded_at" => DateTime.utc_now()
        }
      })

    Logger.info("Created custom activity: #{activity_name}")
  end

  # Helper functions (following poll_seed.exs patterns)

  defp fetch_google_places_restaurants do
    # Search for restaurants using Google Places API (same pattern as polling)
    # Using Warsaw, Poland coordinates for more relevant local restaurants
    warsaw_coordinates = {52.2297, 21.0122}
    
    case TextSearch.search("restaurants", %{
      type: "restaurant",
      location: warsaw_coordinates,
      radius: 5000  # 5km radius
    }) do
      {:ok, places} when places != [] ->
        Logger.info("Successfully fetched #{length(places)} restaurants from Google Places")
        # Convert Google Places format to our expected format
        places
        |> Enum.take(10)  # Limit to 10 restaurants for activities
        |> Enum.map(&convert_google_place_to_restaurant_format/1)

      {:error, reason} ->
        Logger.warning("Failed to fetch Google Places restaurants (#{inspect(reason)}), using curated data")
        []

      _ ->
        Logger.warning("Google Places API returned unexpected response, using curated data")
        []
    end
  rescue
    error ->
      Logger.error("Error fetching Google Places restaurants: #{inspect(error)}")
      []
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

  defp build_restaurant_activity_metadata(restaurant) do
    case Map.get(restaurant, :api_source) do
      "google_places" ->
        %{
          "name" => restaurant.name,
          "cuisine" => restaurant.cuisine,
          "price" => restaurant.price,
          "address" => restaurant.description,
          "rating" => restaurant.rating,
          "google_place_id" => restaurant.google_place_id,
          "photos" => restaurant.photos,
          "api_source" => "google_places",
          "seeded_at" => DateTime.utc_now()
        }
      
      _ ->
        # Curated data format
        %{
          "name" => restaurant.name,
          "cuisine" => restaurant.cuisine,
          "price" => restaurant.price,
          "description" => restaurant.description,
          "specialties" => Map.get(restaurant, :specialties, []),
          "api_source" => "curated",
          "seeded_at" => DateTime.utc_now()
        }
    end
  end

  defp fetch_tmdb_movies do
    # Follow exact same pattern as poll_seed.exs
    case TmdbService.get_popular_movies(1) do
      {:ok, movies} when movies != [] ->
        movies

      {:error, reason} ->
        Logger.warning("TMDB API failed: #{inspect(reason)}")
        []

      _ ->
        Logger.warning("TMDB API returned unexpected response")
        []
    end
  rescue
    error ->
      Logger.error("Error fetching TMDB movies: #{inspect(error)}")
      []
  end

  defp get_event_organizer(event, users) do
    # Get the first organizer, or fall back to a random user
    event_with_users = Repo.preload(event, :users)

    organizer =
      event_with_users.users
      |> Enum.find(fn user ->
        case Repo.get_by(Events.EventUser, event_id: event.id, user_id: user.id) do
          %{role: :organizer} -> true
          _ -> false
        end
      end)

    organizer || Enum.random(users)
  end

end