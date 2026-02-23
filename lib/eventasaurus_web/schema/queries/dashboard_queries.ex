defmodule EventasaurusWeb.Schema.Queries.DashboardQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.DashboardResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :dashboard_queries do
    @desc "List dashboard events with time/ownership filters and filter counts."
    field :dashboard_events, non_null(:dashboard_events_result) do
      arg(:time_filter, :dashboard_time_filter, default_value: :upcoming)
      arg(:ownership_filter, :dashboard_ownership_filter, default_value: :all)
      arg(:limit, :integer, default_value: 50)
      middleware(Authenticate)
      resolve(&DashboardResolver.dashboard_events/3)
    end
  end
end
