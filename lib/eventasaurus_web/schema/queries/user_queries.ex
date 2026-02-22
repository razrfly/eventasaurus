defmodule EventasaurusWeb.Schema.Queries.UserQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.UserResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :user_queries do
    @desc "Search users for adding as co-organizers. Excludes current user and existing organizers."
    field :search_users_for_organizers, non_null(list_of(non_null(:user_search_result))) do
      arg(:query, non_null(:string))
      arg(:slug, non_null(:string))
      arg(:limit, :integer)
      middleware(Authenticate)
      resolve(&UserResolver.search_users_for_organizers/3)
    end
  end
end
