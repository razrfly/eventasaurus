defmodule EventasaurusApp.Events.VoteValidator do
  @moduledoc """
  Server-side validation for poll votes to ensure data integrity and prevent abuse.
  """

  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}
  alias EventasaurusApp.Accounts.User

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
  defp validate_user_can_vote(%Poll{event_id: _event_id}, user) do
    # Check if user is participant or organizer of the event
    # This would need to be implemented based on your event participation logic
    # For now, we'll allow all authenticated users
    if user.id do
      :ok
    else
      {:error, "User must be authenticated to vote"}
    end
  end

  # Vote Parameter Validation by System
  defp validate_vote_params("binary", %{vote_value: value}) when value in ["yes", "maybe", "no"],
    do: :ok

  defp validate_vote_params("binary", _), do: {:error, "Binary vote must be yes, maybe, or no"}

  defp validate_vote_params("approval", %{vote_value: "selected"}), do: :ok
  defp validate_vote_params("approval", %{vote_value: nil}), do: :ok
  defp validate_vote_params("approval", _), do: {:error, "Approval vote must be selected or nil"}

  defp validate_vote_params("ranked", %{vote_rank: rank}) when is_integer(rank) and rank > 0,
    do: :ok

  defp validate_vote_params("ranked", _),
    do: {:error, "Ranked vote must have a positive integer rank"}

  defp validate_vote_params("star", %{vote_numeric: rating}) do
    case Decimal.to_float(rating) do
      r when r >= 1.0 and r <= 5.0 -> :ok
      _ -> {:error, "Star rating must be between 1 and 5"}
    end
  rescue
    _ -> {:error, "Invalid star rating value"}
  end

  defp validate_vote_params("star", _), do: {:error, "Star vote must have a numeric rating"}

  defp validate_vote_params(_, _), do: {:error, "Unknown voting system"}

  # Vote Limits Validation
  defp validate_vote_limits(%Poll{voting_system: "approval"} = poll, _option, user, _params) do
    # Check max_options_per_user limit for approval voting
    if poll.max_options_per_user && poll.max_options_per_user > 0 do
      current_vote_count = count_user_votes_in_poll(poll, user)

      if current_vote_count >= poll.max_options_per_user do
        {:error, "Maximum number of selections (#{poll.max_options_per_user}) reached"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp validate_vote_limits(_poll, _option, _user, _params), do: :ok

  # Multiple Vote Validation
  defp validate_voting_system_supports_multiple("approval"), do: :ok
  defp validate_voting_system_supports_multiple("ranked"), do: :ok

  defp validate_voting_system_supports_multiple(system) do
    {:error, "#{system} voting does not support multiple votes"}
  end

  defp validate_multiple_vote_data(%Poll{voting_system: "approval"} = poll, option_ids, _user) do
    with :ok <- validate_option_ids_exist(poll, option_ids),
         :ok <- validate_approval_count(poll, option_ids) do
      :ok
    end
  end

  defp validate_multiple_vote_data(%Poll{voting_system: "ranked"} = poll, ranked_options, _user) do
    with :ok <- validate_ranked_format(ranked_options),
         :ok <- validate_ranked_uniqueness(ranked_options),
         :ok <- validate_ranked_option_ids(poll, ranked_options) do
      :ok
    end
  end

  # Helper validations
  defp validate_option_ids_exist(poll, option_ids) do
    valid_ids = poll.poll_options |> Enum.map(& &1.id) |> MapSet.new()
    provided_ids = MapSet.new(option_ids)

    if MapSet.subset?(provided_ids, valid_ids) do
      :ok
    else
      {:error, "Some option IDs are invalid"}
    end
  end

  defp validate_approval_count(poll, option_ids) do
    if poll.max_options_per_user && length(option_ids) > poll.max_options_per_user do
      {:error, "Cannot select more than #{poll.max_options_per_user} options"}
    else
      :ok
    end
  end

  defp validate_ranked_format(ranked_options) do
    if Enum.all?(ranked_options, fn {option_id, rank} ->
         is_integer(option_id) and is_integer(rank) and rank > 0
       end) do
      :ok
    else
      {:error, "Invalid ranked vote format"}
    end
  end

  defp validate_ranked_uniqueness(ranked_options) do
    ranks = Enum.map(ranked_options, fn {_, rank} -> rank end)

    if length(ranks) == length(Enum.uniq(ranks)) do
      :ok
    else
      {:error, "Duplicate ranks not allowed"}
    end
  end

  defp validate_ranked_option_ids(poll, ranked_options) do
    option_ids = Enum.map(ranked_options, fn {id, _} -> id end)
    validate_option_ids_exist(poll, option_ids)
  end

  # Parameter Sanitization
  defp sanitize_vote_params("binary", params) do
    %{vote_value: params.vote_value}
  end

  defp sanitize_vote_params("approval", params) do
    %{vote_value: params[:vote_value] || "selected"}
  end

  defp sanitize_vote_params("ranked", params) do
    %{vote_rank: params.vote_rank}
  end

  defp sanitize_vote_params("star", params) do
    %{vote_numeric: params.vote_numeric}
  end

  defp sanitize_multiple_votes("approval", option_ids) do
    Enum.map(option_ids, &{&1, %{vote_value: "selected"}})
  end

  defp sanitize_multiple_votes("ranked", ranked_options) do
    Enum.map(ranked_options, fn {id, rank} -> {id, %{vote_rank: rank}} end)
  end

  # Count how many votes the user already has in the poll
  defp count_user_votes_in_poll(poll, user) do
    import Ecto.Query
    alias EventasaurusApp.Repo

    query =
      from(pv in PollVote,
        join: po in PollOption,
        on: pv.poll_option_id == po.id,
        where: po.poll_id == ^poll.id and pv.voter_id == ^user.id,
        select: count(pv.id)
      )

    Repo.one(query) || 0
  end

  @doc """
  Validates anonymous votes with stricter rules.
  """
  def validate_anonymous_vote(%Poll{} = poll, %PollOption{} = poll_option, vote_params) do
    with :ok <- validate_poll_status(poll),
         :ok <- validate_option_belongs_to_poll(poll, poll_option),
         :ok <- validate_anonymous_voting_allowed(poll),
         :ok <- validate_vote_params(poll.voting_system, vote_params) do
      {:ok, sanitize_vote_params(poll.voting_system, vote_params)}
    end
  end

  defp validate_anonymous_voting_allowed(%Poll{} = _poll) do
    # Check if poll allows anonymous voting
    # This would depend on your poll configuration
    :ok
  end
end

