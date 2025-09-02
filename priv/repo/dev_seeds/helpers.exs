defmodule DevSeeds.Helpers do
  @moduledoc """
  Helper functions for development seeding.
  """

  import EventasaurusApp.Factory
  alias EventasaurusApp.Auth.{Client, ServiceRoleHelper, SeedUserManager}
  
  @doc """
  Print a colorful status message
  """
  def log(message, color \\ :cyan) do
    IO.puts(IO.ANSI.format([color, "→ ", :reset, message]))
  end

  @doc """
  Print a success message
  """
  def success(message) do
    IO.puts(IO.ANSI.format([:green, "✓ ", :reset, message]))
  end

  @doc """
  Print an error message
  """
  def error(message) do
    IO.puts(IO.ANSI.format([:red, "✗ ", :reset, message]))
  end

  @doc """
  Print a section header
  """
  def section(title) do
    IO.puts("")
    IO.puts(IO.ANSI.format([:bright, :blue, "═══ ", title, " ═══", :reset]))
    IO.puts("")
  end

  @doc """
  Get or create a user with specific attributes and optional Supabase auth
  """
  def get_or_create_user(attrs) do
    case SeedUserManager.get_or_create_user(attrs) do
      {:ok, user} ->
        log("✅ User ready: #{user.name} (#{user.email})")
        user
      {:error, reason} ->
        error("Failed to create user #{Map.get(attrs, :email)}: #{inspect(reason)}")
        # Return a basic user for factory compatibility
        insert(:user, Map.delete(attrs, :password))
    end
  end
  
  @doc """
  Create a Supabase auth user if service role key is available
  """
  def maybe_create_auth_user(attrs) do
    if ServiceRoleHelper.service_role_key_available?() && Mix.env() == :dev do
      email = Map.get(attrs, :email)
      password = Map.get(attrs, :password, "testpass123")
      name = Map.get(attrs, :name, "Test User")
      
      case Client.admin_create_user(email, password, %{name: name}, true) do
        {:ok, auth_user} ->
          # Update attrs with real Supabase ID and remove password
          attrs
          |> Map.put(:supabase_id, auth_user["id"])
          |> Map.delete(:password)
        
        {:error, %{message: message}} ->
          if String.contains?(message, "already been registered") do
            log("Auth user already exists for #{email}", :yellow)
          else
            log("Could not create auth for #{email}: #{message}", :red)
          end
          Map.delete(attrs, :password)
          
        {:error, error} ->
          log("Auth creation failed for #{email}: #{inspect(error)}", :red)
          Map.delete(attrs, :password)
      end
    else
      # No service role key or not in dev, skip auth creation
      attrs
      |> Map.put(:supabase_id, Ecto.UUID.generate())  # Use a proper UUID instead of fake prefix
      |> Map.delete(:password)
    end
  end

  @doc """
  Create multiple users with progress tracking and optional Supabase auth
  """
  def create_users(count, attrs_fn \\ fn _ -> %{} end) do
    section("Creating Users")
    
    if ServiceRoleHelper.service_role_key_available?() && Mix.env() == :dev do
      log("🔐 Creating users with Supabase authentication...")
    else
      log("⚠️  No service role key found - creating users without auth")
      ServiceRoleHelper.ensure_available()
    end
    
    # Prepare all user attributes
    users_attrs = Enum.map(1..count, fn i ->
      attrs = attrs_fn.(i)
      
      # Ensure password is set for test accounts
      case Map.get(attrs, :email) do
        "admin@example.com" -> Map.put_new(attrs, :password, "testpass123")
        "demo@example.com" -> Map.put_new(attrs, :password, "testpass123")
        _ -> Map.put_new(attrs, :password, "testpass123")  # Default password for all dev users
      end
    end)
    
    # Batch create all users
    {successful_users, failed_users} = SeedUserManager.batch_create_users(users_attrs)
    
    # Log special accounts
    Enum.each(successful_users, fn user ->
      case user.email do
        "admin@example.com" ->
          log("📧 Test account created: admin@example.com / testpass123", :green)
        "demo@example.com" ->
          log("📧 Test account created: demo@example.com / testpass123", :green)
        _ -> nil
      end
    end)
    
    if length(failed_users) > 0 do
      error("Failed to create #{length(failed_users)} users")
      Enum.each(failed_users, fn {attrs, reason} ->
        error("  - #{Map.get(attrs, :email)}: #{inspect(reason)}")
      end)
    end
    
    success("Created #{length(successful_users)} users successfully")
    successful_users
  end

  @doc """
  Create events with various states
  """
  def create_events_with_states(users, counts) do
    section("Creating Events")
    
    all_events = []
    
    # Past events
    all_events = if counts[:past] > 0 do
      past_events = create_events(counts[:past], users, fn _i ->
        %{
          start_at: Faker.DateTime.backward(30),
          ends_at: Faker.DateTime.backward(29),
          status: Enum.random([:confirmed, :canceled])
        }
      end)
      log("Created #{counts[:past]} past events")
      all_events ++ past_events
    else
      all_events
    end
    
    # Current/upcoming events
    all_events = if counts[:upcoming] > 0 do
      upcoming_events = create_events(counts[:upcoming], users, fn _i ->
        %{
          start_at: Faker.DateTime.forward(Enum.random(1..30)),
          status: Enum.random([:polling, :confirmed])
        }
      end)
      log("Created #{counts[:upcoming]} upcoming events")
      all_events ++ upcoming_events
    else
      all_events
    end
    
    # Far future events
    all_events = if counts[:future] > 0 do
      future_events = create_events(counts[:future], users, fn _i ->
        %{
          start_at: Faker.DateTime.forward(Enum.random(60..180)),
          status: :draft
        }
      end)
      log("Created #{counts[:future]} far future events")
      all_events ++ future_events
    else
      all_events
    end
    
    success("Created #{Enum.sum(Map.values(counts))} events total")
    all_events
  end

  defp create_events(count, users, attrs_fn) do
    Enum.map(1..count, fn i ->
      organizer = Enum.random(users)
      attrs = attrs_fn.(i)
      
      event = insert(:realistic_event, attrs)
      
      # Add organizer
      insert(:event_user, %{
        event: event,
        user: organizer,
        role: "owner"
      })
      
      event
    end)
  end

  @doc """
  Add participants to events
  """
  def add_participants_to_events(events, users, participation_rate \\ 0.3) do
    section("Adding Event Participants")
    
    total_count = events
    |> Enum.map(fn event ->
      # Randomly select participants (excluding organizer)
      num_participants = round(length(users) * participation_rate * :rand.uniform())
      participants = Enum.take_random(users, num_participants)
      
      Enum.each(participants, fn user ->
        insert(:event_participant, %{
          event: event,
          user: user,
          status: Enum.random([:pending, :accepted, :declined, :cancelled])
        })
      end)
      
      num_participants
    end)
    |> Enum.sum()
    
    success("Added #{total_count} participants to events")
  end

  @doc """
  Create polls for events
  """
  def create_polls_for_events(events, users) do
    section("Creating Polls")
    
    polls = events
    |> Enum.filter(fn event -> 
      event.status in [:polling, :confirmed]
    end)
    |> Enum.flat_map(fn event ->
      # Create 1-3 polls per eligible event
      num_polls = Enum.random(1..3)
      
      Enum.map(1..num_polls, fn _ ->
        poll = insert(:poll, %{
          event: event,
          created_by: Enum.random(users)
        })
        
        # Add poll options
        num_options = Enum.random(3..8)
        options = Enum.map(1..num_options, fn i ->
          insert(:poll_option, %{
            poll: poll,
            suggested_by: Enum.random(users),
            order_index: i
          })
        end)
        
        # Add votes if poll is in voting or closed phase
        if poll.phase in ["voting", "closed"] do
          add_votes_to_poll(poll, options, users)
        end
        
        poll
      end)
    end)
    
    success("Created #{length(polls)} polls")
    polls
  end

  defp add_votes_to_poll(poll, options, users) do
    # 30-70% of users vote
    voting_users = Enum.take_random(users, round(length(users) * (0.3 + :rand.uniform() * 0.4)))
    
    Enum.each(voting_users, fn user ->
      # Vote for 1-3 options depending on poll settings
      num_votes = min(3, length(options))
      voted_options = Enum.take_random(options, Enum.random(1..num_votes))
      
      Enum.with_index(voted_options, fn option, index ->
        insert(:poll_vote, %{
          poll_option: option,
          poll: poll,
          voter: user,
          vote_value: "yes",  # Default vote value
          vote_rank: if(poll.voting_system == "ranked", do: index + 1, else: nil),
          voted_at: DateTime.utc_now()
        })
      end)
    end)
  end

  @doc """
  Create activities for past events
  """
  def create_activities_for_events(events, users) do
    section("Creating Event Activities")
    
    activities = events
    |> Enum.filter(fn event -> event.status == :confirmed end)
    |> Enum.flat_map(fn event ->
      # Create 1-5 activities per completed event
      num_activities = Enum.random(1..5)
      
      Enum.map(1..num_activities, fn _ ->
        insert(:event_activity, %{
          event: event,
          created_by: Enum.random(users),
          occurred_at: event.start_at
        })
      end)
    end)
    
    success("Created #{length(activities)} activities")
    activities
  end

  @doc """
  Create groups with members
  """
  def create_groups_with_members(users, count) do
    section("Creating Groups")
    
    groups = Enum.map(1..count, fn i ->
      group = insert(:group)
      
      # Add members (5-20 per group)
      num_members = Enum.random(5..20)
      members = Enum.take_random(users, num_members)
      
      # First member is owner
      insert(:group_user, %{
        group: group,
        user: hd(members),
        role: "owner"
      })
      
      # Rest are members/admins
      tl(members)
      |> Enum.each(fn user ->
        insert(:group_user, %{
          group: group,
          user: user,
          role: Enum.random(["member", "member", "member", "admin"])
        })
      end)
      
      if rem(i, 5) == 0 do
        log("Created #{i}/#{count} groups...")
      end
      
      group
    end)
    
    success("Created #{count} groups")
    groups
  end

end