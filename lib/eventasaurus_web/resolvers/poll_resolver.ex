defmodule EventasaurusWeb.Resolvers.PollResolver do
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo

  def event_polls(_parent, %{slug: slug}, %{context: %{current_user: _user}}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:error, "Event not found"}

      event ->
        polls = Events.list_polls(event)
        {:ok, polls}
    end
  end

  def vote_on_poll(_parent, %{poll_id: poll_id, option_id: option_id} = args, %{
        context: %{current_user: user}
      }) do
    poll = Events.get_poll(poll_id)

    if is_nil(poll) do
      {:ok, %{success: false, errors: [%{field: "pollId", message: "Poll not found"}]}}
    else
      poll = Repo.preload(poll, :poll_options)

      option = Enum.find(poll.poll_options, &(to_string(&1.id) == to_string(option_id)))

      if is_nil(option) do
        {:ok, %{success: false, errors: [%{field: "optionId", message: "Option not found"}]}}
      else
        vote_data = build_vote_data(poll.voting_system, args)

        case Events.create_poll_vote(option, user, vote_data, poll.voting_system) do
          {:ok, _vote} ->
            {:ok, %{success: true, errors: []}}

          {:error, %Ecto.Changeset{} = changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
              |> Enum.flat_map(fn {field, messages} ->
                Enum.map(messages, &%{field: to_string(field), message: &1})
              end)

            {:ok, %{success: false, errors: errors}}

          {:error, reason} when is_binary(reason) ->
            {:ok, %{success: false, errors: [%{field: "base", message: reason}]}}

          {:error, _} ->
            {:ok,
             %{success: false, errors: [%{field: "base", message: "Could not cast vote"}]}}
        end
      end
    end
  end

  defp build_vote_data("binary", _args) do
    %{vote_value: "yes", voted_at: DateTime.utc_now()}
  end

  defp build_vote_data("approval", _args) do
    %{vote_value: "selected", voted_at: DateTime.utc_now()}
  end

  defp build_vote_data("star", %{score: score}) when is_integer(score) do
    %{vote_value: "star", vote_numeric: Decimal.new(score), voted_at: DateTime.utc_now()}
  end

  defp build_vote_data("ranked", %{score: rank}) when is_integer(rank) do
    %{vote_value: "ranked", vote_rank: rank, voted_at: DateTime.utc_now()}
  end

  defp build_vote_data(_system, _args) do
    %{vote_value: "yes", voted_at: DateTime.utc_now()}
  end
end
