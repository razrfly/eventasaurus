defmodule EventasaurusWeb.Schema.Mutations.EventMutations do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.EventResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate
  alias EventasaurusWeb.Schema.Middleware.AuthorizeOrganizer

  object :event_mutations do
    @desc "Create a new event. The current user becomes the organizer."
    field :create_event, non_null(:create_event_result) do
      arg(:input, non_null(:create_event_input))
      middleware(Authenticate)
      resolve(&EventResolver.create_event/3)
    end

    @desc "Update an existing event. Must be the organizer."
    field :update_event, non_null(:update_event_result) do
      arg(:slug, non_null(:string))
      arg(:input, non_null(:update_event_input))
      middleware(Authenticate)
      middleware(AuthorizeOrganizer)
      resolve(&EventResolver.update_event/3)
    end

    @desc "Delete an event. Must be the organizer."
    field :delete_event, non_null(:delete_event_result) do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      middleware(AuthorizeOrganizer)
      resolve(&EventResolver.delete_event/3)
    end

    @desc "Publish an event (set status to confirmed, visibility to public). Must be the organizer."
    field :publish_event, non_null(:update_event_result) do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      middleware(AuthorizeOrganizer)
      resolve(&EventResolver.publish_event/3)
    end

    @desc "Cancel an event. Must be the organizer."
    field :cancel_event, non_null(:update_event_result) do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      middleware(AuthorizeOrganizer)
      resolve(&EventResolver.cancel_event/3)
    end

    @desc "Add a co-organizer to an event by email. Must be an organizer."
    field :add_organizer, non_null(:organizer_result) do
      arg(:slug, non_null(:string))
      arg(:email, non_null(:string))
      middleware(Authenticate)
      middleware(AuthorizeOrganizer)
      resolve(&EventResolver.add_organizer/3)
    end

    @desc "Remove a co-organizer from an event. Must be an organizer."
    field :remove_organizer, non_null(:organizer_result) do
      arg(:slug, non_null(:string))
      arg(:user_id, non_null(:id))
      middleware(Authenticate)
      middleware(AuthorizeOrganizer)
      resolve(&EventResolver.remove_organizer/3)
    end
  end
end
