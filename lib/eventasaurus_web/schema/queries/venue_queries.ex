defmodule EventasaurusWeb.Schema.Queries.VenueQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.VenueResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :venue_queries do
    @desc "Search venues by name."
    field :search_venues, non_null(list_of(non_null(:venue))) do
      arg(:query, non_null(:string))
      arg(:limit, :integer)
      middleware(Authenticate)
      resolve(&VenueResolver.search_venues/3)
    end

    @desc "Get the current user's recently used venues."
    field :my_recent_venues, non_null(list_of(non_null(:recent_venue))) do
      arg(:limit, :integer)
      middleware(Authenticate)
      resolve(&VenueResolver.my_recent_venues/3)
    end
  end
end
