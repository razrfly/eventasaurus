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
  end
end
