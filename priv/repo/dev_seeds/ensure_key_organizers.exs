defmodule DevSeeds.EnsureKeyOrganizers do
  @moduledoc """
  Ensures key themed users (movie_buff, foodie_friend) actually organize events.
  This fixes the issue where these important users have 0 or few events.
  """
  
  import EventasaurusApp.Factory
  alias EventasaurusApp.{Repo, Accounts, Events}
  alias EventasaurusApp.Events.EventUser
  
  # Load helpers
  Code.require_file("helpers.exs", __DIR__)
  alias DevSeeds.Helpers
  
  def ensure_key_organizers do
    Helpers.section("Ensuring Key Organizers Have Events")
    
    # Load curated data for realistic content
    Code.require_file("curated_data.exs", __DIR__)
    
    # Ensure movie_buff organizes movie events
    ensure_movie_events()
    
    # Ensure foodie organizes restaurant events  
    ensure_foodie_events()
    
    # Fix participant managing events
    fix_participant_events()
    
    Helpers.success("Key organizers now have appropriate events")
  end
  
  defp ensure_movie_events do
    import Ecto.Query
    movie_user = Accounts.get_user_by_email("movie_buff@example.com")
    
    if movie_user do
      # Check how many events they organize (excluding deleted events)
      _existing_count = Repo.aggregate(
        from(eu in EventUser, 
          join: e in assoc(eu, :event),
          where: eu.user_id == ^movie_user.id and eu.role in ["owner", "organizer"] and is_nil(e.deleted_at)),
        :count
      )
      
      # Always check for movie-themed events specifically
      movie_event_count = Repo.aggregate(
        from(eu in EventUser, 
          join: e in assoc(eu, :event),
          where: eu.user_id == ^movie_user.id and 
                 eu.role in ["owner", "organizer"] and 
                 is_nil(e.deleted_at) and
                 ilike(e.title, "%movie%")),
        :count
      )
      
      if movie_event_count < 5 do
        Helpers.log("Creating movie events for movie_buff (currently has #{movie_event_count} movie events)")
        needed = 5 - movie_event_count
        
        # Get real movies from curated data
        movies = DevSeeds.CuratedData.movies() |> Enum.take_random(needed)
        
        Enum.each(movies, fn movie ->
          title = unique_title("Movie Night: #{movie.title}")
          
          description = """
          Join us for a screening of #{movie.title} (#{movie.year})!
          
          #{movie.description}
          
          Genre: #{movie.genre} | IMDB Rating: #{movie.rating}/10
          
          We'll have popcorn, snacks, and drinks. Feel free to bring your favorite movie snacks!
          Discussion afterwards for those interested. This will be a ranked choice poll to select from several great movies.
          """
          
          # Use Events context to create event with organizer (ensures proper slug generation)
          {:ok, _event} = Events.create_event_with_organizer(%{
            title: title,
            description: description,
            tagline: "Movie Night - #{movie.genre}",
            status: :confirmed,
            visibility: :public,
            theme: :cosmic,
            is_virtual: Enum.random([true, false]),
            start_at: Faker.DateTime.forward(Enum.random(1..30)),
            ends_at: Faker.DateTime.forward(Enum.random(31..32)),
            timezone: Faker.Address.time_zone()
          }, movie_user)
        end)
      end
    else
      Helpers.log("movie_buff@example.com not found", :yellow)
    end
  end
  
  defp ensure_foodie_events do
    import Ecto.Query
    foodie_user = Accounts.get_user_by_email("foodie_friend@example.com")
    
    if foodie_user do
      # Check how many events they organize (excluding deleted events)
      _existing_count = Repo.aggregate(
        from(eu in EventUser, 
          join: e in assoc(eu, :event),
          where: eu.user_id == ^foodie_user.id and eu.role in ["owner", "organizer"] and is_nil(e.deleted_at)),
        :count
      )
      
      # Always check for restaurant/food-themed events specifically
      food_event_count = Repo.aggregate(
        from(eu in EventUser, 
          join: e in assoc(eu, :event),
          where: eu.user_id == ^foodie_user.id and 
                 eu.role in ["owner", "organizer"] and 
                 is_nil(e.deleted_at) and
                 (ilike(e.title, "%restaurant%") or ilike(e.title, "%dinner%") or 
                  ilike(e.title, "%food%") or ilike(e.title, "%brunch%"))),
        :count
      )
      
      if food_event_count < 5 do
        Helpers.log("Creating restaurant events for foodie_friend (currently has #{food_event_count} food events)")
        needed = 5 - food_event_count
        
        # Get real restaurants from curated data
        restaurants = DevSeeds.CuratedData.restaurants() |> Enum.take_random(needed)
        
        Enum.each(restaurants, fn restaurant ->
          title = unique_title("Dinner at #{restaurant.name}")
          
          description = """
          Let's gather for an amazing culinary experience at #{restaurant.name}!
          
          #{restaurant.description}
          
          Cuisine: #{restaurant.cuisine} | Price Range: #{restaurant.price}
          
          Specialties: #{Enum.join(restaurant.specialties, ", ")}
          
          Please RSVP so we can make reservations. We'll use ranked choice voting to select our final restaurant choice.
          Separate checks available. Can't wait to share this meal with you all!
          """
          
          # Use Events context to create event with organizer (ensures proper slug generation)
          {:ok, _event} = Events.create_event_with_organizer(%{
            title: title,
            description: description,
            tagline: "#{restaurant.cuisine} Cuisine - #{restaurant.price}",
            status: :confirmed,
            visibility: :public,
            theme: :celebration,
            is_virtual: false,
            is_ticketed: false,
            start_at: Faker.DateTime.forward(Enum.random(1..30)),
            ends_at: Faker.DateTime.forward(Enum.random(31..32)),
            timezone: Faker.Address.time_zone()
          }, foodie_user)
        end)
      end
    else
      Helpers.log("foodie_friend@example.com not found", :yellow)
    end
  end
  
  defp fix_participant_events do
    import Ecto.Query
    # participant@example.com should NOT be organizing events
    participant = Accounts.get_user_by_email("participant@example.com")
    
    if participant do
      # Find events where they're an organizer
      organizer_roles = Repo.all(
        from eu in EventUser,
        where: eu.user_id == ^participant.id and eu.role in ["owner", "organizer"],
        select: eu
      )
      
      if length(organizer_roles) > 0 do
        Helpers.log("Removing #{length(organizer_roles)} organizer roles from participant@example.com")
        
        # Change their role to participant
        Enum.each(organizer_roles, fn eu ->
          eu
          |> Ecto.Changeset.change(%{role: "participant"})
          |> Repo.update!()
        end)
      end
    end
  end
  
  defp event_exists?(title) do
    import Ecto.Query
    Repo.exists?(from e in EventasaurusApp.Events.Event, where: e.title == ^title and is_nil(e.deleted_at))
  end
  
  defp unique_title(base, attempt \\ 0) do
    # Prevent unbounded recursion with a reasonable limit
    max_attempts = 100
    
    if attempt >= max_attempts do
      # If we hit the limit, use a timestamp to ensure uniqueness
      "#{base} #{System.unique_integer([:positive])}"
    else
      candidate = if attempt == 0, do: base, else: "#{base} (#{attempt})"
      if event_exists?(candidate), do: unique_title(base, attempt + 1), else: candidate
    end
  end
end

# Allow direct execution of this script
if __ENV__.file == Path.absname(__ENV__.file) do
  DevSeeds.EnsureKeyOrganizers.ensure_key_organizers()
end