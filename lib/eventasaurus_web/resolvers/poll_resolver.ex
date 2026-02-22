defmodule EventasaurusWeb.Resolvers.PollResolver do
  require Logger

  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Resolvers.Helpers

  @spec event_polls(any(), %{slug: String.t()}, map()) :: {:ok, [map()]} | {:error, String.t()}
  def event_polls(_parent, %{slug: slug}, %{context: %{current_user: _user}}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:error, "Event not found"}

      event ->
        polls = Events.list_polls(event)
        {:ok, polls}
    end
  end

  @spec vote_on_poll(any(), map(), map()) :: {:ok, map()}
  def vote_on_poll(_parent, %{poll_id: poll_id, option_id: option_id} = args, %{
        context: %{current_user: user}
      }) do
    with poll when not is_nil(poll) <- Events.get_poll(poll_id),
         poll = Repo.preload(poll, :poll_options),
         option when not is_nil(option) <-
           Enum.find(poll.poll_options, &(to_string(&1.id) == to_string(option_id))),
         {:ok, vote_data} <- build_vote_data(poll.voting_system, args) do
      case Events.create_poll_vote(option, user, vote_data, poll.voting_system) do
        {:ok, _vote} ->
          {:ok, %{success: true, errors: []}}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:ok, %{success: false, errors: Helpers.format_changeset_errors(changeset)}}

        {:error, reason} when is_binary(reason) ->
          {:ok, %{success: false, errors: [%{field: "base", message: reason}]}}

        {:error, _} ->
          {:ok, %{success: false, errors: [%{field: "base", message: "Could not cast vote"}]}}
      end
    else
      nil ->
        # Determine which lookup failed based on what exists
        poll = Events.get_poll(poll_id)

        if is_nil(poll) do
          {:ok, %{success: false, errors: [%{field: "pollId", message: "Poll not found"}]}}
        else
          {:ok, %{success: false, errors: [%{field: "optionId", message: "Option not found"}]}}
        end

      {:error, reason} when is_binary(reason) ->
        {:ok, %{success: false, errors: [%{field: "base", message: reason}]}}
    end
  end

  defp build_vote_data("binary", _args) do
    {:ok, %{vote_value: "yes", voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("approval", _args) do
    {:ok, %{vote_value: "selected", voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("star", %{score: score}) when is_integer(score) and score >= 1 and score <= 5 do
    {:ok, %{vote_value: "star", vote_numeric: Decimal.new(score), voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("star", _args) do
    {:error, "Star voting requires a score between 1 and 5"}
  end

  defp build_vote_data("ranked", %{score: rank}) when is_integer(rank) and rank >= 1 do
    {:ok, %{vote_value: "ranked", vote_rank: rank, voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("ranked", _args) do
    {:error, "Ranked voting requires a score as a positive integer"}
  end

  defp build_vote_data(system, _args) do
    Logger.warning("Unknown voting system #{inspect(system)}")
    {:error, "Unsupported voting system"}
  end
end
