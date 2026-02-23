defmodule EventasaurusWeb.Schema.Mutations.PollMutations do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.PollResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :poll_mutations do
    @desc "Vote on a poll option."
    field :vote_on_poll, non_null(:vote_result) do
      arg(:poll_id, non_null(:id))
      arg(:option_id, non_null(:id))
      arg(:score, :integer)
      arg(:vote_value, :string)
      middleware(Authenticate)
      resolve(&PollResolver.vote_on_poll/3)
    end
  end
end
