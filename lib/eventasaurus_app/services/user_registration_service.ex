defmodule EventasaurusApp.Services.UserRegistrationService do
  @moduledoc """
  Unified service for all user registration flows across the application.
  
  This service handles user creation, Supabase synchronization, and context-specific 
  registration for different entry points (event registration, voting, ticket purchase, interest).
  
  ## Registration Contexts
  
  - `:event_registration` - Direct event registration
  - `:ticket_purchase` - Registration via ticket purchase
  - `:voting` - Registration via poll voting
  - `:interest` - Registration of interest in an event
  
  ## Examples
  
      iex> UserRegistrationService.register_user("john@example.com", "John Doe", :event_registration, event_id: 123)
      {:ok, %{user: %User{}, participant: %EventParticipant{}}}
      
      iex> UserRegistrationService.register_user("jane@example.com", "Jane Doe", :voting, poll_id: 456, votes: %{})
      {:ok, %{user: %User{}, votes_saved: true}}
  """
  
  alias EventasaurusApp.{Repo, Accounts, Events}
  alias EventasaurusApp.Auth.SupabaseSync
  
  require Logger
  
  @doc """
  Register a user for any context (event, voting, ticket purchase, interest).
  
  ## Options
  
  - `:event_id` - Required for event_registration, ticket_purchase, and interest contexts
  - `:poll_id` - Required for voting context
  - `:votes` - Required for voting context
  - `:participant_status` - Override default participant status (optional)
  - `:source` - Override default source tracking (optional)
  - `:intended_status` - For registration context (:accepted or :interested)
  
  ## Returns
  
  - `{:ok, result_map}` - Success with context-specific result
  - `{:error, reason}` - Registration failed
  """
  def register_user(email, name, context, opts \\ []) do
    Logger.info("Starting unified user registration", %{
      context: context,
      email_domain: email |> String.split("@") |> List.last()
    })
    
    Repo.transaction(fn ->
      with {:ok, user} <- find_or_create_user(email, name, opts),
           {:ok, result} <- handle_context_registration(user, context, opts) do
        Logger.info("Successfully completed registration", %{
          context: context,
          user_id: user.id
        })
        result
      else
        {:error, reason} ->
          Logger.error("Registration failed", %{
            context: context,
            reason: inspect(reason)
          })
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Find or create a user via Supabase OTP.
  
  This function checks for an existing user first, then attempts to create
  one via Supabase if not found. It handles email confirmation requirements
  gracefully by creating temporary user records when needed.
  
  ## Returns
  
  - `{:ok, %User{}}` - User found or created successfully
  - `{:error, reason}` - Failed to find or create user
  """
  def find_or_create_user(email, name, opts \\ []) do
    # Check if user exists in our local database first
    case Accounts.get_user_by_email(email) do
      nil ->
        Logger.info("User not found locally, attempting Supabase user creation/lookup")
        create_user_via_supabase(email, name, opts)
        
      existing_user ->
        Logger.debug("Existing user found in local database", %{user_id: existing_user.id})
        {:ok, existing_user}
    end
  end
  
  @doc """
  Handle email confirmation requirements consistently across all contexts.
  
  Creates a temporary user record that will be updated when the user
  confirms their email address via the magic link.
  """
  def handle_confirmation_required(email, name, _context) do
    Logger.info("User created via OTP but email confirmation required, creating temporary local user record")
    
    temp_supabase_id = "pending_confirmation_#{Ecto.UUID.generate()}"
    
    case Accounts.create_user(%{
      email: email,
      name: name,
      supabase_id: temp_supabase_id  # Temporary ID - will be updated when user confirms email
    }) do
      {:ok, user} ->
        Logger.info("Successfully created temporary local user", %{
          user_id: user.id,
          temp_supabase_id: temp_supabase_id
        })
        {:ok, user}
        
      {:error, reason} ->
        Logger.error("Failed to create temporary local user", %{reason: inspect(reason)})
        {:error, reason}
    end
  end
  
  @doc """
  Create appropriate participant record based on context.
  
  Different contexts create participants with different statuses:
  - `:event_registration` - Creates participant with `:pending` status
  - `:ticket_purchase` - Creates participant with `:confirmed_with_order` status
  - `:voting` - Creates participant with `:pending` status
  - `:interest` - Creates participant with `:interested` status
  """
  def create_participant_for_context(user, context, opts) do
    event_id = Keyword.get(opts, :event_id)
    
    if event_id do
      status = determine_participant_status(context, opts)
      source = determine_participant_source(context, opts)
      
      Events.create_or_upgrade_participant_for_order(%{
        event_id: event_id,
        user_id: user.id,
        status: status,
        source: source
      })
    else
      # Some contexts don't require participant creation (e.g., pure voting without event)
      {:ok, nil}
    end
  end
  
  # Private helper functions
  
  defp create_user_via_supabase(email, name, _opts) do
    case Events.create_or_find_supabase_user(email, name) do
      {:ok, supabase_user} ->
        Logger.info("Successfully created/found user in Supabase")
        sync_supabase_user(supabase_user)
        
      {:error, :user_confirmation_required} ->
        handle_confirmation_required(email, name, nil)
        
      {:error, :invalid_user_data} ->
        Logger.error("Invalid user data from Supabase after OTP creation")
        {:error, :invalid_user_data}
        
      {:error, reason} ->
        Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
        {:error, reason}
    end
  end
  
  defp sync_supabase_user(supabase_user) do
    case SupabaseSync.sync_user(supabase_user) do
      {:ok, user} ->
        Logger.info("Successfully synced user to local database", %{user_id: user.id})
        {:ok, user}
        
      {:error, reason} ->
        Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
        {:error, reason}
    end
  end
  
  defp handle_context_registration(user, :event_registration, opts) do
    event_id = Keyword.fetch!(opts, :event_id)
    
    # Check if already registered using the proper function
    event = Events.get_event!(event_id)
    case Events.get_event_participant_by_event_and_user(event, user) do
      nil ->
        # Create new participant
        case create_participant_for_context(user, :event_registration, opts) do
          {:ok, participant} ->
            {:ok, %{user: user, participant: participant, registration_type: :new_registration}}
          {:error, reason} ->
            {:error, reason}
        end
        
      existing_participant ->
        # The existing participant is already found - just return it
        # The function already filters out soft-deleted records
        {:ok, %{user: user, participant: existing_participant, registration_type: :already_registered}}
    end
  end
  
  defp handle_context_registration(user, :ticket_purchase, opts) do
    _event_id = Keyword.fetch!(opts, :event_id)
    
    case create_participant_for_context(user, :ticket_purchase, opts) do
      {:ok, participant} ->
        {:ok, %{user: user, participant: participant}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp handle_context_registration(user, :voting, opts) do
    poll_id = Keyword.get(opts, :poll_id)
    votes = Keyword.get(opts, :votes, %{})
    event_id = Keyword.get(opts, :event_id)
    
    # Save votes if provided
    votes_result = if poll_id && map_size(votes) > 0 do
      case save_votes_for_user(user, poll_id, votes, opts) do
        {:ok, _} -> true
        _ -> false
      end
    else
      false
    end
    
    # Create participant if event_id provided
    participant_result = if event_id do
      case create_participant_for_context(user, :voting, opts) do
        {:ok, participant} -> participant
        {:error, _} -> nil
      end
    else
      nil
    end
    
    {:ok, %{
      user: user,
      votes_saved: votes_result,
      participant: participant_result
    }}
  end
  
  defp handle_context_registration(user, :interest, opts) do
    _event_id = Keyword.fetch!(opts, :event_id)
    
    case create_participant_for_context(user, :interest, opts) do
      {:ok, participant} ->
        {:ok, %{user: user, participant: participant}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp determine_participant_status(:event_registration, opts) do
    intended_status = Keyword.get(opts, :intended_status, :accepted)
    case intended_status do
      :interested -> :interested
      _ -> :pending
    end
  end
  
  defp determine_participant_status(:ticket_purchase, opts) do
    Keyword.get(opts, :participant_status, :confirmed_with_order)
  end
  
  defp determine_participant_status(:voting, opts) do
    Keyword.get(opts, :participant_status, :pending)
  end
  
  defp determine_participant_status(:interest, opts) do
    Keyword.get(opts, :participant_status, :interested)
  end
  
  defp determine_participant_source(:event_registration, opts) do
    Keyword.get(opts, :source, "public_registration")
  end
  
  defp determine_participant_source(:ticket_purchase, opts) do
    Keyword.get(opts, :source, "ticket_purchase")
  end
  
  defp determine_participant_source(:voting, opts) do
    bulk = Keyword.get(opts, :bulk_voting, false)
    if bulk do
      "bulk_voting_registration"
    else
      Keyword.get(opts, :source, "voting_registration")
    end
  end
  
  defp determine_participant_source(:interest, opts) do
    Keyword.get(opts, :source, "interest_registration")
  end
  
  defp save_votes_for_user(user, poll_id, votes, _opts) do
    # This would need to be implemented based on your voting system
    # For now, returning a placeholder
    Logger.info("Saving votes for user", %{
      user_id: user.id,
      poll_id: poll_id,
      vote_count: map_size(votes)
    })
    
    # TODO: Implement actual vote saving logic
    # This would likely call Events.save_poll_votes/3 or similar
    {:ok, :votes_saved}
  end
end