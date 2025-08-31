defmodule DevSeeds.Users do
  @moduledoc """
  User seeding module for development environment.
  Creates diverse user profiles with realistic data.
  """
  
  import EventasaurusApp.Factory
  alias DevSeeds.Helpers
  alias EventasaurusApp.Auth.SeedUserManager
  
  @doc """
  Seeds users with various profiles and characteristics.
  
  Options:
    - count: Number of users to create (default: 50)
    - with_auth: Create with Supabase authentication (default: true)
  """
  def seed(opts \\ []) do
    count = Keyword.get(opts, :count, 50)
    with_auth = Keyword.get(opts, :with_auth, true)
    
    Helpers.section("Creating #{count} Users")
    
    # Create specific test accounts first
    test_accounts = create_test_accounts(with_auth)
    
    # Create random users to fill the rest
    remaining_count = max(0, count - length(test_accounts))
    random_users = create_random_users(remaining_count, with_auth)
    
    all_users = test_accounts ++ random_users
    
    # Add some variety to user profiles
    all_users = Enum.map(all_users, &add_profile_variety/1)
    
    Helpers.success("Created #{length(all_users)} users")
    all_users
  end
  
  defp create_test_accounts(with_auth) do
    Helpers.log("Creating test accounts...")
    
    test_accounts = [
      %{
        name: "Admin User",
        email: "admin@example.com",
        username: "admin",
        password: "testpass123",
        bio: "System administrator account for testing admin features",
        profile_public: true,
        website_url: "https://example.com/admin",
        timezone: "America/New_York"
      },
      %{
        name: "Demo User",
        email: "demo@example.com",
        username: "demo",
        password: "testpass123",
        bio: "Demo account for showcasing features",
        profile_public: true,
        instagram_handle: "demo_user",
        x_handle: "demo_user",
        timezone: "America/Los_Angeles"
      },
      %{
        name: "John Organizer",
        email: "organizer@example.com",
        username: "john_organizer",
        password: "testpass123",
        bio: "Professional event organizer with 5+ years experience",
        profile_public: true,
        linkedin_handle: "john-organizer",
        timezone: "America/Chicago"
      },
      %{
        name: "Sarah Participant",
        email: "participant@example.com",
        username: "sarah_p",
        password: "testpass123",
        bio: "Active event participant and community member",
        profile_public: true,
        instagram_handle: "sarah_participant",
        timezone: "America/Denver"
      },
      %{
        name: "Private User",
        email: "private@example.com",
        username: "private_user",
        password: "testpass123",
        bio: "This profile is private",
        profile_public: false,
        timezone: "Europe/London"
      },
      %{
        name: "Inactive User",
        email: "inactive@example.com",
        username: "inactive",
        password: "testpass123",
        bio: "Account for testing inactive user scenarios",
        profile_public: true,
        timezone: "Asia/Tokyo"
      }
    ]
    
    if with_auth do
      {successful, _failed} = SeedUserManager.batch_create_users(test_accounts)
      successful
    else
      Enum.map(test_accounts, fn attrs ->
        insert(:user, Map.delete(attrs, :password))
      end)
    end
  end
  
  defp create_random_users(count, with_auth) when count > 0 do
    Helpers.log("Creating #{count} random users...")
    
    users_attrs = Enum.map(1..count, fn i ->
      # Create diverse user profiles
      %{
        name: Faker.Person.name(),
        email: "user#{i}@#{Faker.Internet.domain_name()}",
        username: "#{Faker.Internet.user_name()}#{i}",
        password: "testpass123",
        bio: random_bio(),
        profile_public: Enum.random([true, true, true, false]), # 75% public
        website_url: maybe_website(),
        instagram_handle: maybe_social_handle("instagram"),
        x_handle: maybe_social_handle("x"),
        youtube_handle: maybe_social_handle("youtube"),
        tiktok_handle: maybe_social_handle("tiktok"),
        linkedin_handle: maybe_social_handle("linkedin"),
        timezone: Faker.Address.time_zone(),
        default_currency: Enum.random(["USD", "EUR", "GBP", "CAD", "AUD", "JPY"])
      }
    end)
    
    if with_auth do
      {successful, _failed} = SeedUserManager.batch_create_users(users_attrs)
      successful
    else
      Enum.map(users_attrs, fn attrs ->
        insert(:user, Map.delete(attrs, :password))
      end)
    end
  end
  
  defp create_random_users(_, _), do: []
  
  defp random_bio do
    Enum.random([
      Faker.Lorem.paragraph(2),
      "Works at #{Faker.Company.name()}. #{Faker.Company.catch_phrase()}",
      "Love exploring new places and trying new things. #{Faker.Lorem.sentence()}",
      "#{Faker.Superhero.descriptor()} event enthusiast and community organizer.",
      "Passionate about events and bringing people together. #{Faker.Lorem.sentence()}",
      nil # Some users don't have bios
    ])
  end
  
  defp maybe_website do
    if Enum.random([true, false, false]) do # 33% chance
      Faker.Internet.url()
    else
      nil
    end
  end
  
  defp maybe_social_handle(platform) do
    # Different platforms have different adoption rates
    chance = case platform do
      "instagram" -> [true, true, false] # 66%
      "x" -> [true, false, false] # 33%
      "linkedin" -> [true, false, false, false] # 25%
      "youtube" -> [true, false, false, false, false] # 20%
      "tiktok" -> [true, false, false, false, false] # 20%
      _ -> [false]
    end
    
    if Enum.random(chance) do
      Faker.Internet.user_name()
    else
      nil
    end
  end
  
  defp add_profile_variety(user) do
    # Add some variety to user profiles
    # This simulates different user engagement levels
    engagement_level = Enum.random([:highly_active, :active, :moderate, :low, :inactive])
    
    case engagement_level do
      :highly_active ->
        # These users are very engaged
        user
        
      :inactive ->
        # These users signed up but never use the platform
        Map.merge(user, %{
          bio: nil,
          website_url: nil,
          instagram_handle: nil,
          x_handle: nil,
          profile_public: false
        })
        
      _ ->
        user
    end
  end
  
  @doc """
  Creates specific user personas for testing
  """
  def create_personas do
    personas = [
      %{name: "Movie Buff", bio: "Cinema enthusiast. Watches 3+ movies per week."},
      %{name: "Foodie Friend", bio: "Always looking for the next great restaurant."},
      %{name: "Game Master", bio: "Board game collector and D&D dungeon master."},
      %{name: "Sports Fan", bio: "Never miss a game. Season ticket holder."},
      %{name: "Concert Goer", bio: "Live music is life. 50+ shows per year."},
      %{name: "Book Clubber", bio: "Avid reader and book club organizer."},
      %{name: "Outdoor Explorer", bio: "Hiking, camping, and adventure seeker."},
      %{name: "Tech Meetup Host", bio: "Organizing tech talks and hackathons."},
      %{name: "Wine Enthusiast", bio: "Sommelier in training. Love wine tastings."},
      %{name: "Fitness Buddy", bio: "Group fitness and running clubs."}
    ]
    
    Enum.map(personas, fn persona ->
      attrs = Map.merge(persona, %{
        email: "#{String.downcase(String.replace(persona.name, " ", "_"))}@example.com",
        username: String.downcase(String.replace(persona.name, " ", "_")),
        password: "testpass123",
        profile_public: true
      })
      
      case SeedUserManager.get_or_create_user(attrs) do
        {:ok, user} -> user
        {:error, _} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end
end