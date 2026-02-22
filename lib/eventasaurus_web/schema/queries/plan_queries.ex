defmodule EventasaurusWeb.Schema.Queries.PlanQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.PlanResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :plan_queries do
    @desc "Returns scored friend suggestions based on past event co-attendance. Limit is clamped to max 50."
    field :participant_suggestions, non_null(list_of(non_null(:participant_suggestion))) do
      arg(:limit, :integer)
      middleware(Authenticate)
      resolve(&PlanResolver.participant_suggestions/3)
    end
  end
end
