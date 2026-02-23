defmodule EventasaurusWeb.Schema.Queries.PollQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.PollResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :poll_queries do
    @desc "Get polls for an event."
    field :event_polls, non_null(list_of(non_null(:poll))) do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      resolve(&PollResolver.event_polls/3)
    end

    @desc "Get detailed voting statistics for a poll."
    field :poll_voting_stats, :poll_voting_stats do
      arg(:poll_id, non_null(:id))
      middleware(Authenticate)
      resolve(&PollResolver.poll_voting_stats/3)
    end
  end
end
