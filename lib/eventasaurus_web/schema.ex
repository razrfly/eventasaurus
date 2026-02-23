defmodule EventasaurusWeb.Schema do
  use Absinthe.Schema

  import_types(Absinthe.Type.Custom)
  import_types(Absinthe.Plug.Types)
  import_types(EventasaurusWeb.Schema.Types)
  import_types(EventasaurusWeb.Schema.Queries)
  import_types(EventasaurusWeb.Schema.Mutations)

  query do
    import_fields(:profile_queries)
    import_fields(:event_queries)
    import_fields(:participation_queries)
    import_fields(:plan_queries)
    import_fields(:venue_queries)
    import_fields(:poll_queries)
    import_fields(:user_queries)

    if Mix.env() in [:dev, :test] do
      import_fields(:dev_queries)
    end
  end

  mutation do
    import_fields(:event_mutations)
    import_fields(:participation_mutations)
    import_fields(:plan_mutations)
    import_fields(:upload_mutations)
    import_fields(:venue_mutations)
    import_fields(:poll_mutations)
  end

  def middleware(middleware, _field, %{identifier: :mutation}) do
    middleware ++ [EventasaurusWeb.Schema.Middleware.ChangesetErrors]
  end

  def middleware(middleware, _field, _object), do: middleware
end
