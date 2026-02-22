defmodule EventasaurusWeb.Schema.Mutations.ParticipationMutations do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.ParticipationResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :participation_mutations do
    @desc "RSVP to an event."
    field :rsvp, non_null(:rsvp_result) do
      arg(:slug, non_null(:string))
      arg(:status, non_null(:rsvp_status))
      middleware(Authenticate)
      resolve(&ParticipationResolver.rsvp/3)
    end

    @desc "Cancel RSVP for an event."
    field :cancel_rsvp, non_null(:cancel_rsvp_result) do
      arg(:slug, non_null(:string))
      middleware(Authenticate)
      resolve(&ParticipationResolver.cancel_rsvp/3)
    end

    @desc "Invite guests to an event by email. Must be the organizer."
    field :invite_guests, non_null(:invite_guests_result) do
      arg(:slug, non_null(:string))
      arg(:emails, non_null(list_of(non_null(:string))))
      arg(:friend_ids, list_of(non_null(:id)))
      arg(:message, :string)
      middleware(Authenticate)
      resolve(&ParticipationResolver.invite_guests/3)
    end

    @desc "Remove a participant from an event. Must be the organizer."
    field :remove_participant, non_null(:participant_action_result) do
      arg(:slug, non_null(:string))
      arg(:user_id, non_null(:id))
      middleware(Authenticate)
      resolve(&ParticipationResolver.remove_participant/3)
    end

    @desc "Resend an invitation email to a participant. Must be the organizer."
    field :resend_invitation, non_null(:participant_action_result) do
      arg(:slug, non_null(:string))
      arg(:user_id, non_null(:id))
      middleware(Authenticate)
      resolve(&ParticipationResolver.resend_invitation/3)
    end

    @desc "Update a participant's RSVP status. Must be the organizer."
    field :update_participant_status, non_null(:participant_action_result) do
      arg(:slug, non_null(:string))
      arg(:user_id, non_null(:id))
      arg(:status, non_null(:rsvp_status))
      middleware(Authenticate)
      resolve(&ParticipationResolver.update_participant_status/3)
    end
  end
end
