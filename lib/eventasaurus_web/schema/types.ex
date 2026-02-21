defmodule EventasaurusWeb.Schema.Types do
  use Absinthe.Schema.Notation

  import_types(EventasaurusWeb.Schema.Types.Enums)
  import_types(EventasaurusWeb.Schema.Types.User)
  import_types(EventasaurusWeb.Schema.Types.Event)
  import_types(EventasaurusWeb.Schema.Types.Venue)
  import_types(EventasaurusWeb.Schema.Types.Participant)
  import_types(EventasaurusWeb.Schema.Types.Plan)
  import_types(EventasaurusWeb.Schema.Types.ParticipantSuggestion)
end
