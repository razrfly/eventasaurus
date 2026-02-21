defmodule EventasaurusWeb.Schema.Mutations.PlanMutations do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.PlanResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :plan_mutations do
    @desc "Create a Plan with Friends for a public event."
    field :create_plan, non_null(:plan_result) do
      arg(:slug, non_null(:string))
      arg(:emails, non_null(list_of(non_null(:string))))
      arg(:friend_ids, list_of(non_null(:id)))
      arg(:message, :string)
      arg(:occurrence, :occurrence_input)
      middleware(Authenticate)
      resolve(&PlanResolver.create_plan/3)
    end
  end
end
