defmodule EventasaurusWeb.Schema.Queries.EventQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.EventResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate
  alias EventasaurusWeb.Schema.Middleware.AuthorizeOrganizer

  object :event_queries do
    @desc "List events the current user organizes."
    field :my_events, non_null(list_of(non_null(:event))) do
      arg(:limit, :integer)
      middleware(Authenticate)
      resolve(&EventResolver.my_events/3)
    end

    @desc "Get a single event by slug. Must be the organizer."
    field :my_event, :event do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      middleware(AuthorizeOrganizer)
      resolve(&EventResolver.my_event/3)
    end
  end
end
