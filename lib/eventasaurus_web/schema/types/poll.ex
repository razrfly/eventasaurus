defmodule EventasaurusWeb.Schema.Types.Poll do
  use Absinthe.Schema.Notation

  object :poll do
    field(:id, non_null(:id))
    field(:title, non_null(:string))
    field(:description, :string)
    field(:poll_type, non_null(:string))
    field(:voting_system, non_null(:string))
    field(:phase, non_null(:string))

    field :voting_deadline, :datetime do
      resolve(fn poll, _, _ ->
        {:ok, poll.voting_deadline}
      end)
    end

    field :options, non_null(list_of(non_null(:poll_option))) do
      resolve(fn poll, _, _ ->
        options =
          (poll.poll_options || [])
          |> Enum.filter(&(&1.status == "active"))
          |> Enum.map(fn option ->
            votes = option.votes || []
            vote_count = length(votes)

            avg_score =
              case votes do
                [] ->
                  nil

                votes ->
                  scores = Enum.map(votes, &EventasaurusApp.Events.PollVote.vote_score/1)
                  Enum.sum(scores) / length(scores)
              end

            %{
              id: option.id,
              title: option.title,
              description: option.description,
              vote_count: vote_count,
              average_score: avg_score
            }
          end)

        {:ok, options}
      end)
    end

    field :my_votes, list_of(non_null(:poll_vote)) do
      resolve(fn poll, _, %{context: context} ->
        case context[:current_user] do
          nil ->
            {:ok, []}

          user ->
            votes = EventasaurusApp.Events.list_user_poll_votes(poll, user)

            result =
              Enum.map(votes, fn vote ->
                %{
                  id: vote.id,
                  option_id: vote.poll_option_id,
                  score: vote.vote_numeric && Decimal.to_integer(vote.vote_numeric),
                  vote_value: vote.vote_value,
                  vote_rank: vote.vote_rank
                }
              end)

            {:ok, result}
        end
      end)
    end
  end

  object :poll_option do
    field(:id, non_null(:id))
    field(:title, non_null(:string))
    field(:description, :string)
    field(:vote_count, non_null(:integer))
    field(:average_score, :float)
  end

  object :poll_vote do
    field(:id, non_null(:id))
    field(:option_id, non_null(:id))
    field(:score, :integer)
    field(:vote_value, :string)
    field(:vote_rank, :integer)
  end

  object :vote_result do
    field(:success, non_null(:boolean))
    field(:errors, list_of(non_null(:input_error)))
  end
end
