defmodule EventasaurusWeb.Schema.Queries do
  use Absinthe.Schema.Notation

  import_types(EventasaurusWeb.Schema.Queries.ProfileQueries)
  import_types(EventasaurusWeb.Schema.Queries.EventQueries)
  import_types(EventasaurusWeb.Schema.Queries.ParticipationQueries)
  import_types(EventasaurusWeb.Schema.Queries.PlanQueries)
  import_types(EventasaurusWeb.Schema.Queries.VenueQueries)
  import_types(EventasaurusWeb.Schema.Queries.PollQueries)
  import_types(EventasaurusWeb.Schema.Queries.UserQueries)
end
