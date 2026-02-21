defmodule EventasaurusWeb.Schema.Queries do
  use Absinthe.Schema.Notation

  import_types(EventasaurusWeb.Schema.Queries.ProfileQueries)
  import_types(EventasaurusWeb.Schema.Queries.EventQueries)
  import_types(EventasaurusWeb.Schema.Queries.ParticipationQueries)
end
