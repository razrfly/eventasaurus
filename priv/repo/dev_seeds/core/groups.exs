defmodule DevSeeds.Groups do
  @moduledoc """
  Group seeding module for development environment.
  Creates groups with varying sizes and activity levels.
  """
  
  alias DevSeeds.Helpers
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Groups
  
  # Removed manual slug generation functions - now using production APIs
  
  @doc """
  Seeds groups with members.
  
  Options:
    - count: Number of groups to create (default: 15)
    - users: List of users to assign as members
  """
  def seed(opts \\ []) do
    count = Keyword.get(opts, :count, 15)
    users = Keyword.get(opts, :users, [])
    
    if length(users) < 10 do
      Helpers.error("Need at least 10 users to create realistic groups")
      []
    else
      Helpers.section("Creating #{count} Groups")
      
      groups = create_diverse_groups(count, users)
      
      Helpers.success("Created #{length(groups)} groups")
      groups
    end
  end
  
  defp create_diverse_groups(count, users) do
    # Create different types of groups
    group_types = [
      # Small intimate groups (2-5 members)
      %{
        size_range: 2..5,
        count: round(count * 0.3),
        type: "intimate",
        names: ["Close Friends", "Family", "Inner Circle", "Best Buds", "The Squad"]
      },
      # Medium groups (6-15 members)
      %{
        size_range: 6..15,
        count: round(count * 0.4),
        type: "medium",
        names: ["Movie Club", "Book Club", "Gaming Group", "Dinner Club", "Wine Tasting Society"]
      },
      # Large groups (16-30 members)
      %{
        size_range: 16..30,
        count: round(count * 0.2),
        type: "large",
        names: ["Community Meetup", "Sports League", "Professional Network", "Alumni Association"]
      },
      # Inactive/archived groups
      %{
        size_range: 3..10,
        count: round(count * 0.1),
        type: "inactive",
        names: ["Archived Group", "Old Team", "Former Club", "Disbanded Society"]
      }
    ]
    
    groups = Enum.flat_map(group_types, fn group_type ->
      Enum.map(1..group_type.count, fn i ->
        create_group_with_members(group_type, users, i)
      end)
    end)
    
    # Ensure we have exactly the requested count
    groups |> Enum.take(count)
  end
  
  defp create_group_with_members(group_type, users, index) do
    # Select random users for this group
    member_count = Enum.random(group_type.size_range)
    selected_users = Enum.take_random(users, member_count)
    
    # First user is the owner
    [owner | members] = selected_users
    
    # Create the group using production API (handles slug generation automatically)
    group_name = generate_group_name(group_type, index)
    
    {:ok, group} = Groups.create_group_with_creator(%{
      "name" => group_name,
      "description" => generate_group_description(group_type.type),
      "avatar_url" => "https://picsum.photos/200/200?random=#{System.unique_integer([:positive])}",
      "cover_image_url" => "https://picsum.photos/800/400?random=#{System.unique_integer([:positive])}",
      "venue_city" => maybe_city(),
      "venue_state" => maybe_state(),
      "venue_country" => maybe_country()
    }, owner)
    
    # Owner was already added by create_group_with_creator
    
    # Add other members with varying roles using production API
    Enum.each(members, fn user ->
      role = if Enum.random(1..10) <= 2, do: "admin", else: "member"
      
      # Use production API for adding group members
      Groups.add_user_to_group(group, user, role, owner)
    end)
    
    # Mark some groups as inactive
    if group_type.type == "inactive" do
      group
      |> Ecto.Changeset.change(%{
        deleted_at: Faker.DateTime.backward(Enum.random(30..180))
      })
      |> Repo.update!()
    end
    
    Helpers.log("Created group: #{group.name} with #{member_count} members")
    group
  end

  defp generate_group_name(group_type, index) do
    base_names = group_type.names
    base_name = Enum.random(base_names)
    
    variations = [
      "#{base_name}",
      "The #{base_name}",
      "#{Faker.Address.city()} #{base_name}",
      "#{base_name} #{Faker.Company.suffix()}",
      "#{Faker.Team.name()} #{base_name}",
      "#{base_name} ##{index}"
    ]
    
    Enum.random(variations)
  end
  
  defp generate_group_description(type) do
    case type do
      "intimate" ->
        Enum.random([
          "A close-knit group of friends who love spending time together.",
          "Our inner circle for planning special events and gatherings.",
          "Just a few good friends making memories.",
          Faker.Lorem.paragraph(2)
        ])
        
      "medium" ->
        Enum.random([
          "#{Faker.Company.catch_phrase()} Join us for regular meetups and events!",
          "A community of enthusiasts sharing common interests.",
          "Weekly gatherings for #{Faker.Beer.name()} and good conversation.",
          Faker.Lorem.paragraph(3)
        ])
        
      "large" ->
        Enum.random([
          "A large community bringing people together for amazing events.",
          "#{Faker.Company.bs()} Open to all who share our passion!",
          "Professional networking and social events for our industry.",
          Faker.Lorem.paragraph(4)
        ])
        
      "inactive" ->
        Enum.random([
          "This group is no longer active.",
          "Archived for historical purposes.",
          "Group disbanded on #{Faker.Date.backward(100)}",
          nil
        ])
        
      _ ->
        Faker.Lorem.paragraph(2)
    end
  end
  
  defp maybe_city do
    if Enum.random([true, true, false]) do
      Faker.Address.city()
    else
      nil
    end
  end
  
  defp maybe_state do
    if Enum.random([true, false]) do
      Faker.Address.state_abbr()
    else
      nil
    end
  end
  
  defp maybe_country do
    if Enum.random([true, false, false]) do
      Faker.Address.country()
    else
      nil
    end
  end
  
  @doc """
  Creates themed groups for specific testing scenarios
  """
  def create_themed_groups(users) do
    themes = [
      %{
        name: "Movie Nights Club",
        description: "Weekly movie screenings and discussions",
        focus: :movies
      },
      %{
        name: "Foodies United",
        description: "Exploring the best restaurants in town",
        focus: :dining
      },
      %{
        name: "Board Game Cafe",
        description: "Strategic games and casual fun",
        focus: :games
      },
      %{
        name: "Outdoor Adventures",
        description: "Hiking, camping, and exploring nature",
        focus: :outdoors
      },
      %{
        name: "Tech Talks",
        description: "Technology discussions and hackathons",
        focus: :tech
      }
    ]
    
    Enum.map(themes, fn theme ->
      # Select 8-15 users for each themed group
      member_count = Enum.random(8..15)
      selected_users = Enum.take_random(users, member_count)
      [owner | members] = selected_users
      
      # Use production API that handles slug generation automatically
      {:ok, group} = Groups.create_group_with_creator(%{
        "name" => theme.name,
        "description" => theme.description
      }, owner)
      
      # Add members using production API (owner already added by create_group_with_creator)
      Enum.each(members, fn user ->
        role = Enum.random(["member", "member", "member", "admin"])
        Groups.add_user_to_group(group, user, role, owner)
      end)
      
      group
    end)
  end
end