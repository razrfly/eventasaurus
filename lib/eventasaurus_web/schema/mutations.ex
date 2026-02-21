defmodule EventasaurusWeb.Schema.Mutations do
  use Absinthe.Schema.Notation

  import_types(EventasaurusWeb.Schema.Mutations.EventMutations)
  import_types(EventasaurusWeb.Schema.Mutations.ParticipationMutations)
  import_types(EventasaurusWeb.Schema.Mutations.PlanMutations)
  import_types(EventasaurusWeb.Schema.Mutations.UploadMutations)
end
