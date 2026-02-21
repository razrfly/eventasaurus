defmodule EventasaurusWeb.Schema.Types.Event do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Schema.Helpers.RsvpStatus
  import Ecto.Query

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventUser
  alias EventasaurusApp.Repo

  object :event do
    field(:id, non_null(:id))
    field(:title, non_null(:string))
    field(:tagline, :string)
    field(:description, :string)
    field(:slug, non_null(:string))

    field :starts_at, :datetime do
      resolve(fn event, _, _ -> {:ok, event.start_at} end)
    end

    field :ends_at, :datetime do
      resolve(fn event, _, _ -> {:ok, event.ends_at} end)
    end

    field(:timezone, :string)
    field(:status, non_null(:event_status))
    field(:visibility, non_null(:event_visibility))
    field(:cover_image_url, :string)
    field(:theme, :event_theme)
    field(:is_ticketed, non_null(:boolean))
    field(:is_virtual, non_null(:boolean))
    field(:virtual_venue_url, :string)

    field :is_organizer, non_null(:boolean) do
      resolve(fn event, _, %{context: context} ->
        case context[:current_user] do
          nil -> {:ok, false}
          user -> {:ok, Events.user_is_organizer?(event, user)}
        end
      end)
    end

    field :venue, :venue do
      resolve(fn event, _, _ ->
        event = Repo.preload(event, :venue)
        {:ok, event.venue}
      end)
    end

    field :participant_count, non_null(:integer) do
      resolve(fn event, _, _ ->
        accepted = Events.count_participants_by_status(event, :accepted)
        confirmed = Events.count_participants_by_status(event, :confirmed_with_order)
        {:ok, accepted + confirmed}
      end)
    end

    field :my_rsvp_status, :rsvp_status do
      resolve(fn event, _, %{context: context} ->
        case context[:current_user] do
          nil ->
            {:ok, nil}

          user ->
            case Events.get_event_participant_by_event_and_user(event, user) do
              nil -> {:ok, nil}
              participant -> {:ok, RsvpStatus.from_db(participant.status)}
            end
        end
      end)
    end

    field :organizer, :user do
      resolve(fn event, _, _ ->
        organizer =
          from(eu in EventUser,
            where: eu.event_id == ^event.id and eu.role == "organizer" and is_nil(eu.deleted_at),
            join: u in assoc(eu, :user),
            select: u,
            limit: 1
          )
          |> Repo.one()

        {:ok, organizer}
      end)
    end

    field :created_at, non_null(:datetime) do
      resolve(fn event, _, _ ->
        {:ok, to_utc_datetime(event.inserted_at)}
      end)
    end

    field :updated_at, non_null(:datetime) do
      resolve(fn event, _, _ ->
        {:ok, to_utc_datetime(event.updated_at)}
      end)
    end
  end

  # Input types

  input_object :create_event_input do
    field(:title, non_null(:string))
    field(:description, :string)
    field(:tagline, :string)
    field(:starts_at, :datetime)
    field(:ends_at, :datetime)
    field(:timezone, :string)
    field(:visibility, :event_visibility)
    field(:venue_id, :id)
    field(:theme, :event_theme)
    field(:cover_image_url, :string)
    field(:is_ticketed, :boolean)
    field(:is_virtual, :boolean)
    field(:virtual_venue_url, :string)
    field(:group_id, :id)
  end

  input_object :update_event_input do
    field(:title, :string)
    field(:description, :string)
    field(:tagline, :string)
    field(:starts_at, :datetime)
    field(:ends_at, :datetime)
    field(:timezone, :string)
    field(:visibility, :event_visibility)
    field(:venue_id, :id)
    field(:theme, :event_theme)
    field(:cover_image_url, :string)
    field(:is_ticketed, :boolean)
    field(:is_virtual, :boolean)
    field(:virtual_venue_url, :string)
  end

  # Result types

  object :create_event_result do
    field(:event, :event)
    field(:errors, list_of(non_null(:input_error)))
  end

  object :update_event_result do
    field(:event, :event)
    field(:errors, list_of(non_null(:input_error)))
  end

  object :delete_event_result do
    field(:success, non_null(:boolean))
    field(:errors, list_of(non_null(:input_error)))
  end

  # Shared error type

  object :input_error do
    field(:field, non_null(:string))
    field(:message, non_null(:string))
  end

  # Participation result types

  object :rsvp_result do
    field(:event, :event)
    field(:status, :rsvp_status)
    field(:errors, list_of(non_null(:input_error)))
  end

  object :cancel_rsvp_result do
    field(:success, non_null(:boolean))
    field(:errors, list_of(non_null(:input_error)))
  end

  object :invite_guests_result do
    field(:invite_count, non_null(:integer))
    field(:errors, list_of(non_null(:input_error)))
  end

  # Plan result types

  input_object :occurrence_input do
    field(:datetime, non_null(:datetime))
  end

  object :plan_result do
    field(:plan, :plan)
    field(:errors, list_of(non_null(:input_error)))
  end

  # Upload result type

  object :upload_result do
    field(:url, :string)
    field(:errors, list_of(non_null(:input_error)))
  end

  # Convert NaiveDateTime to DateTime (UTC) for Absinthe :datetime serialization
  defp to_utc_datetime(%DateTime{} = dt), do: dt
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_utc_datetime(nil), do: nil
end
