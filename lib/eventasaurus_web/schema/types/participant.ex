defmodule EventasaurusWeb.Schema.Types.Participant do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Schema.Helpers.RsvpStatus

  object :participant do
    field(:id, non_null(:id))
    field(:role, :string)

    field :status, non_null(:rsvp_status) do
      resolve(fn participant, _, _ ->
        {:ok, RsvpStatus.from_db(participant.status)}
      end)
    end

    field :invited_at, :datetime do
      resolve(fn participant, _, _ ->
        {:ok, participant.invited_at}
      end)
    end

    field :created_at, non_null(:datetime) do
      resolve(fn participant, _, _ ->
        {:ok, participant.inserted_at}
      end)
    end

    field :user, :user do
      resolve(fn participant, _, _ ->
        participant = EventasaurusApp.Repo.preload(participant, :user)
        {:ok, participant.user}
      end)
    end
  end
end
