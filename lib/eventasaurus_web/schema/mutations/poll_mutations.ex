defmodule EventasaurusWeb.Schema.Mutations.PollMutations do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.PollResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :poll_mutations do
    @desc "Vote on a poll option."
    field :vote_on_poll, non_null(:vote_result) do
      arg(:poll_id, non_null(:id))
      arg(:option_id, non_null(:id))
      arg(:score, :integer)
      arg(:vote_value, :string)
      middleware(Authenticate)
      resolve(&PollResolver.vote_on_poll/3)
    end

    @desc "Clear all of the current user's votes on a poll (for re-voting)."
    field :clear_my_poll_votes, :poll do
      arg(:poll_id, non_null(:id))
      middleware(Authenticate)
      resolve(&PollResolver.clear_my_votes/3)
    end

    @desc "Create a new option on a poll (user suggestion)."
    field :create_poll_option, :poll do
      arg(:poll_id, non_null(:id))
      arg(:title, non_null(:string))
      arg(:description, :string)
      middleware(Authenticate)
      resolve(&PollResolver.create_poll_option/3)
    end

    @desc "Create a new poll for an event."
    field :create_poll, :poll do
      arg(:event_id, non_null(:id))
      arg(:title, non_null(:string))
      arg(:description, :string)
      arg(:voting_system, non_null(:string))
      arg(:voting_deadline, :datetime)
      middleware(Authenticate)
      resolve(&PollResolver.create_poll/3)
    end

    @desc "Update a poll's details."
    field :update_poll, :poll do
      arg(:poll_id, non_null(:id))
      arg(:title, :string)
      arg(:description, :string)
      arg(:voting_deadline, :datetime)
      middleware(Authenticate)
      resolve(&PollResolver.update_poll/3)
    end

    @desc "Delete a poll."
    field :delete_poll, non_null(:vote_result) do
      arg(:poll_id, non_null(:id))
      middleware(Authenticate)
      resolve(&PollResolver.delete_poll/3)
    end

    @desc "Transition a poll to a new phase."
    field :transition_poll_phase, :poll do
      arg(:poll_id, non_null(:id))
      arg(:phase, non_null(:string))
      middleware(Authenticate)
      resolve(&PollResolver.transition_poll_phase/3)
    end

    @desc "Delete a poll option."
    field :delete_poll_option, non_null(:vote_result) do
      arg(:option_id, non_null(:id))
      middleware(Authenticate)
      resolve(&PollResolver.delete_poll_option/3)
    end
  end
end
