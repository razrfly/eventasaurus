defmodule DevSeeds.EnsureKeyOrganizers do
  @moduledoc """
  Ensures key themed users (movie_buff, foodie_friend) actually organize events.
  This fixes the issue where these important users have 0 or few events.
  """
  
  import EventasaurusApp.Factory
  alias EventasaurusApp.{Repo, Accounts}
  alias EventasaurusApp.Events.EventUser
  alias DevSeeds.Helpers
  
  def ensure_key_organizers do
    Helpers.section("Ensuring Key Organizers Have Events")
    
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
      # Check how many events they organize
      existing_count = Repo.aggregate(
        from(eu in EventUser, 
          where: eu.user_id == ^movie_user.id and eu.role in ["owner", "organizer"]),
        :count
      )
      
      if existing_count < 5 do
        Helpers.log("Creating movie events for movie_buff (currently has #{existing_count})")
        
        # Create movie night events
        movie_titles = [
          "Friday Film Night: Inception",
          "Classic Cinema: Casablanca",
          "Marvel Movie Marathon",
          "Horror Night: Halloween Special",
          "Indie Film Screening: Moonlight"
        ]
        
        Enum.each(movie_titles, fn title ->
          unless event_exists?(title) do
            event = insert(:realistic_event, %{
              title: title,
              description: "Join us for an amazing movie experience! We'll watch the film together and discuss afterwards.",
              tagline: "Movies & Discussion",
              status: :confirmed,
              visibility: :public,
              theme: :cosmic,
              is_virtual: Enum.random([true, false]),
              start_at: Faker.DateTime.forward(Enum.random(1..30)),
              ends_at: Faker.DateTime.forward(Enum.random(31..32))
            })
            
            # Make movie_buff the organizer
            insert(:event_user, %{
              event: event,
              user: movie_user,
              role: "owner"
            })
          end
        end)
      end
    else
      Helpers.warning("movie_buff@example.com not found")
    end
  end
  
  defp ensure_foodie_events do
    import Ecto.Query
    foodie_user = Accounts.get_user_by_email("foodie_friend@example.com")
    
    if foodie_user do
      # Check how many events they organize
      existing_count = Repo.aggregate(
        from(eu in EventUser, 
          where: eu.user_id == ^foodie_user.id and eu.role in ["owner", "organizer"]),
        :count
      )
      
      if existing_count < 5 do
        Helpers.log("Creating restaurant events for foodie_friend (currently has #{existing_count})")
        
        # Create restaurant events
        restaurant_titles = [
          "Sushi Night at Nobu",
          "Italian Feast at Luigi's",
          "Taco Tuesday Gathering",
          "Wine & Cheese Pairing Evening",
          "Brunch at The Garden Cafe"
        ]
        
        Enum.each(restaurant_titles, fn title ->
          unless event_exists?(title) do
            event = insert(:realistic_event, %{
              title: title,
              description: "Experience amazing cuisine with fellow food lovers! Limited spots available.",
              tagline: "Culinary Adventure",
              status: :confirmed,
              visibility: :public,
              theme: :celebration,
              is_virtual: false,
              is_ticketed: true,
              start_at: Faker.DateTime.forward(Enum.random(1..30)),
              ends_at: Faker.DateTime.forward(Enum.random(31..32))
            })
            
            # Make foodie_friend the organizer
            insert(:event_user, %{
              event: event,
              user: foodie_user,
              role: "owner"
            })
          end
        end)
      end
    else
      Helpers.warning("foodie_friend@example.com not found")
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
    Repo.exists?(from e in EventasaurusApp.Events.Event, where: e.title == ^title)
  end
end

# Run if called directly
if __MODULE__ == __ENV__.module do
  import Ecto.Query
  DevSeeds.EnsureKeyOrganizers.ensure_key_organizers()
end