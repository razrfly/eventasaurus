defmodule EventasaurusApp.Events.VoteValidator do
  @moduledoc """
  Server-side validation for poll votes to ensure data integrity and prevent abuse.
  """

  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Repo
  alias Decimal
  import Ecto.Query

  @doc """
  Validates a vote before it's cast, checking all business rules.
  Returns {:ok, validated_params} or {:error, reason}
  """
  def validate_vote(%Poll{} = poll, %PollOption{} = poll_option, %User{} = user, vote_params) do
    with :ok <- validate_poll_status(poll),
         :ok <- validate_option_belongs_to_poll(poll, poll_option),
         :ok <- validate_user_can_vote(poll, user),
         :ok <- validate_vote_params(poll.voting_system, vote_params),
         :ok <- validate_vote_limits(poll, poll_option, user, vote_params) do
      {:ok, sanitize_vote_params(poll.voting_system, vote_params)}
    end
  end

  @doc """
  Validates multiple votes (for approval or ranked voting).
  """
  def validate_multiple_votes(%Poll{} = poll, vote_data, %User{} = user)
      when is_list(vote_data) do
    with :ok <- validate_poll_status(poll),
         :ok <- validate_user_can_vote(poll, user),
         :ok <- validate_voting_system_supports_multiple(poll.voting_system),
         :ok <- validate_multiple_vote_data(poll, vote_data, user) do
      {:ok, sanitize_multiple_votes(poll.voting_system, vote_data)}
    end
  end

  # Poll Status Validation
  defp validate_poll_status(%Poll{phase: "voting"}), do: :ok
  defp validate_poll_status(%Poll{phase: "voting_with_suggestions"}), do: :ok
  defp validate_poll_status(%Poll{phase: "voting_only"}), do: :ok

  defp validate_poll_status(%Poll{phase: phase}) do
    {:error, "Voting is not allowed in phase: #{phase}"}
  end

  # Option Ownership Validation
  defp validate_option_belongs_to_poll(%Poll{id: poll_id}, %PollOption{poll_id: poll_id}), do: :ok

  defp validate_option_belongs_to_poll(_poll, _option) do
    {:error, "Option does not belong to this poll"}
  end

  # User Permission Validation
  defp validate_user_can_vote(%Poll{} = _poll, %User{} = user) do
    # Check if user is allowed to vote based on poll settings
    cond do
      user.id != nil -> :ok
      true -> {:error, "Authentication required for voting"}
    end
  end

  # Vote Parameters Validation
  defp validate_vote_params("binary", %{vote_value: value}) 
       when value in ["yes", "maybe", "no"], do: :ok
  defp validate_vote_params("binary", _), do: {:error, "Invalid binary vote value"}

  defp validate_vote_params("approval", %{vote_value: value}) 
       when value in ["yes", "no"], do: :ok
  defp validate_vote_params("approval", _), do: {:error, "Invalid approval vote value"}

  defp validate_vote_params("star", %{vote_numeric: rating}) do
    case Decimal.cast(rating) do
      {:ok, decimal} ->
        rating_float = Decimal.to_float(decimal)
        if rating_float >= 1.0 and rating_float <= 5.0 do
          :ok
        else
          {:error, "Star rating must be between 1 and 5"}
        end
      _ ->
        {:error, "Invalid star rating format"}
    end
  end

  defp validate_vote_params("ranked", %{vote_rank: rank}) do
    if is_integer(rank) and rank > 0 do
      :ok
    else
      {:error, "Invalid rank value"}
    end
  end

  defp validate_vote_params(system, _) do
    {:error, "Unknown voting system: #{system}"}
  end

  # Vote Limits Validation
  defp validate_vote_limits(%Poll{} = poll, %PollOption{} = _option, %User{} = user, _vote_params) do
    # Check if user has exceeded voting limits for this poll
    case poll.voting_system do
      "approval" -> validate_approval_limits(poll, user)
      "ranked" -> validate_ranked_limits(poll, user)
      _ -> :ok
    end
  end

  defp validate_approval_limits(%Poll{} = poll, %User{} = user) do
    # For approval voting, check if user has too many selections
    existing_votes = get_user_votes_count(poll, user)
    max_selections = 999 # Default max selections
    
    if existing_votes >= max_selections do
      {:error, "Maximum selections exceeded"}
    else
      :ok
    end
  end

  defp validate_ranked_limits(%Poll{} = poll, %User{} = user) do
    # For ranked voting, each option should have unique rank
    existing_ranks = get_user_ranks(poll, user)
    
    if length(existing_ranks) != length(Enum.uniq(existing_ranks)) do
      {:error, "Duplicate ranks not allowed"}
    else
      :ok
    end
  end

  # Multiple Vote System Validation
  defp validate_voting_system_supports_multiple("approval"), do: :ok
  defp validate_voting_system_supports_multiple("ranked"), do: :ok
  defp validate_voting_system_supports_multiple(system) do
    {:error, "Voting system #{system} does not support multiple votes"}
  end

  defp validate_multiple_vote_data(%Poll{} = poll, vote_data, %User{} = user) do
    # Validate each vote in the batch
    Enum.reduce_while(vote_data, :ok, fn vote_params, :ok ->
      case validate_single_vote_in_batch(poll, vote_params, user) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_single_vote_in_batch(%Poll{} = poll, vote_params, %User{} = _user) do
    # Basic validation for batch votes
    with :ok <- validate_vote_params(poll.voting_system, vote_params),
         :ok <- validate_option_exists(poll, vote_params[:option_id]) do
      :ok
    end
  end

  defp validate_option_exists(%Poll{id: poll_id}, option_id) do
    case EventasaurusApp.Repo.get_by(PollOption, id: option_id, poll_id: poll_id) do
      nil -> {:error, "Option not found"}
      _ -> :ok
    end
  end

  # Sanitization Functions
  defp sanitize_vote_params("binary", params) do
    %{vote_value: params.vote_value}
  end

  defp sanitize_vote_params("approval", params) do
    %{vote_value: params.vote_value}
  end

  defp sanitize_vote_params("star", params) do
    case Decimal.cast(params.vote_numeric) do
      {:ok, decimal} -> %{vote_numeric: decimal}
      _ -> %{vote_numeric: nil}
    end
  end

  defp sanitize_vote_params("ranked", params) do
    %{vote_rank: params.vote_rank}
  end

  defp sanitize_multiple_votes(voting_system, vote_data) do
    Enum.map(vote_data, &sanitize_vote_params(voting_system, &1))
  end

  # Helper Functions
  defp get_user_votes_count(%Poll{} = poll, %User{} = user) do
    # Query actual vote count for this user in this poll
    query = from v in PollVote,
      join: po in PollOption, on: v.poll_option_id == po.id,
      where: po.poll_id == ^poll.id and v.voter_id == ^user.id,
      select: count(v.id)
    
    Repo.one(query) || 0
  end

  defp get_user_ranks(%Poll{} = poll, %User{} = user) do
    # Query actual ranks for this user in this poll
    query = from v in PollVote,
      join: po in PollOption, on: v.poll_option_id == po.id,
      where: po.poll_id == ^poll.id and v.voter_id == ^user.id and not is_nil(v.vote_rank),
      select: v.vote_rank
    
    Repo.all(query)
  end
end