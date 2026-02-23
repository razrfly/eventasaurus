defmodule EventasaurusWeb.Schema.Queries.DevQueries do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.DevResolver

  object :dev_queries do
    @desc "Get categorized dev users for quick login (dev mode only)."
    field :dev_quick_login_users, :dev_quick_login_users do
      resolve(&DevResolver.quick_login_users/3)
    end
  end
end
