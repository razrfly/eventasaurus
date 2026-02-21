defmodule EventasaurusWeb.Schema.Queries.ProfileQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.ProfileResolver

  object :profile_queries do
    @desc "Returns the currently authenticated user's profile, or null if not logged in."
    field :my_profile, :user do
      resolve(&ProfileResolver.my_profile/3)
    end
  end
end
