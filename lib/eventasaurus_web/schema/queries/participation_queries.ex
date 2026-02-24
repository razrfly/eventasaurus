defmodule EventasaurusWeb.Schema.Queries.ParticipationQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.ParticipationResolver
  alias EventasaurusWeb.Resolvers.PlanResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :participation_queries do
    @desc "Get a single event by slug as a participant (no organizer requirement)."
    field :event_as_participant, :event do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      resolve(&ParticipationResolver.event_as_participant/3)
    end

    @desc "List events the current user is attending (upcoming)."
    field :attending_events, non_null(list_of(non_null(:event))) do
      arg(:limit, :integer)
      middleware(Authenticate)
      resolve(&ParticipationResolver.attending_events/3)
    end

    @desc "Get the current user's plan for a public event."
    field :my_plan, :plan do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      resolve(&PlanResolver.my_plan/3)
    end

    @desc "List participants for an event. Must be the organizer."
    field :event_participants, non_null(list_of(non_null(:participant))) do
      arg(:slug, non_null(:string))
      arg(:status, :string)
      arg(:limit, :integer)
      arg(:offset, :integer)
      middleware(Authenticate)
      resolve(&ParticipationResolver.event_participants/3)
    end
  end
end
