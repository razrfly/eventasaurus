defmodule EventasaurusWeb.Schema.Types.Participant do
  use Absinthe.Schema.Notation

  alias EventasaurusApp.Events.EventParticipant
  alias EventasaurusWeb.Schema.Helpers.RsvpStatus

  object :participant do
    field(:id, non_null(:id))
    field(:role, :string)
    field(:invitation_message, :string)

    field :status, non_null(:rsvp_status) do
      resolve(fn participant, _, _ ->
        {:ok, RsvpStatus.from_db(participant.status)}
      end)
    end

    @desc "Raw database status atom as string (pending, accepted, interested, etc.)"
    field :raw_status, :string do
      resolve(fn participant, _, _ ->
        {:ok, to_string(participant.status)}
      end)
    end

    @desc "Email delivery status from invitation metadata"
    field :email_status, :string do
      resolve(fn participant, _, _ ->
        {:ok, EventParticipant.get_email_status(participant).status}
      end)
    end

    @desc "Email address from the preloaded user association"
    field :email, :string do
      resolve(fn participant, _, _ ->
        participant = EventasaurusApp.Repo.preload(participant, :user)

        case participant.user do
          nil -> {:ok, nil}
          user -> {:ok, user.email}
        end
      end)
    end

    field :invited_at, :datetime do
      resolve(fn participant, _, _ ->
        {:ok, to_utc_datetime(participant.invited_at)}
      end)
    end

    field :created_at, non_null(:datetime) do
      resolve(fn participant, _, _ ->
        {:ok, to_utc_datetime(participant.inserted_at)}
      end)
    end

    field :user, :user do
      resolve(fn participant, _, _ ->
        participant = EventasaurusApp.Repo.preload(participant, :user)
        {:ok, participant.user}
      end)
    end
  end

  defp to_utc_datetime(nil), do: nil
  defp to_utc_datetime(%DateTime{} = dt), do: dt
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  object :participant_action_result do
    field(:success, non_null(:boolean))
    field(:errors, list_of(:input_error))
  end
end
