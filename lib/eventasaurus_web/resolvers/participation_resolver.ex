defmodule EventasaurusWeb.Resolvers.ParticipationResolver do
  @moduledoc """
  Resolvers for participation-related GraphQL queries and mutations.
  """

  alias EventasaurusApp.Events
  alias EventasaurusWeb.Schema.Helpers.RsvpStatus

  def attending_events(_parent, args, %{context: %{current_user: user}}) do
    opts = [
      upcoming: true,
      order_by: [asc: :start_at]
    ]

    opts =
      case args[:limit] do
        nil -> opts ++ [limit: 50]
        limit -> opts ++ [limit: limit]
      end

    events = Events.list_events_with_participation(user, opts)
    {:ok, events}
  end

  def rsvp(_parent, %{slug: slug, status: graphql_status}, %{context: %{current_user: user}}) do
    db_status = RsvpStatus.to_db(graphql_status)

    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok, %{event: nil, status: nil, errors: [%{field: "slug", message: "Event not found"}]}}

      event ->
        case Events.update_participant_status(event, user, db_status) do
          {:ok, _participant} ->
            # Re-fetch event to get fresh data
            event = Events.get_event_by_slug(slug)
            {:ok, %{event: event, status: graphql_status, errors: []}}

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = format_changeset_errors(changeset)
            {:ok, %{event: nil, status: nil, errors: errors}}

          {:error, reason} ->
            {:ok,
             %{event: nil, status: nil, errors: [%{field: "base", message: inspect(reason)}]}}
        end
    end
  end

  def cancel_rsvp(_parent, %{slug: slug}, %{context: %{current_user: user}}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok, %{success: false, errors: [%{field: "slug", message: "Event not found"}]}}

      event ->
        case Events.remove_participant_status(event, user) do
          {:ok, :removed} ->
            {:ok, %{success: true, errors: []}}

          {:ok, :not_participant} ->
            {:ok, %{success: true, errors: []}}

          {:error, reason} ->
            {:ok, %{success: false, errors: [%{field: "base", message: inspect(reason)}]}}
        end
    end
  end

  def event_participants(_parent, %{slug: slug} = args, %{context: %{current_user: user}}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:error, "Event not found"}

      event ->
        if Events.user_is_organizer?(event, user) do
          opts =
            []
            |> then(fn o -> if args[:limit], do: Keyword.put(o, :limit, args[:limit]), else: o end)
            |> then(fn o ->
              if args[:offset], do: Keyword.put(o, :offset, args[:offset]), else: o
            end)

          participants = Events.list_event_participants(event, opts)

          # Filter by raw status if provided
          participants =
            case args[:status] do
              nil ->
                participants

              status_filter ->
                status_atom = String.to_existing_atom(status_filter)
                Enum.filter(participants, fn p -> p.status == status_atom end)
            end

          {:ok, participants}
        else
          {:error, "NOT_FOUND"}
        end
    end
  end

  def invite_guests(_parent, %{slug: slug, emails: emails} = args, %{
        context: %{current_user: user}
      }) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok, %{invite_count: 0, errors: [%{field: "slug", message: "Event not found"}]}}

      event ->
        # Verify organizer authorization
        if Events.user_is_organizer?(event, user) do
          message = args[:message] || ""

          result =
            Events.process_guest_invitations(
              event,
              user,
              manual_emails: emails,
              invitation_message: message,
              mode: :invitation
            )

          case result do
            %{successful_invitations: count} ->
              {:ok, %{invite_count: count, errors: []}}

            {:error, reason} ->
              {:ok, %{invite_count: 0, errors: [%{field: "base", message: inspect(reason)}]}}
          end
        else
          {:ok, %{invite_count: 0, errors: [%{field: "base", message: "NOT_FOUND"}]}}
        end
    end
  end

  def remove_participant(_parent, %{slug: slug, user_id: user_id}, %{
        context: %{current_user: current_user}
      }) do
    alias EventasaurusApp.Accounts

    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok, %{success: false, errors: [%{field: "slug", message: "Event not found"}]}}

      event ->
        if Events.user_is_organizer?(event, current_user) do
          case Accounts.get_user(user_id) do
            nil ->
              {:ok, %{success: false, errors: [%{field: "user_id", message: "User not found"}]}}

            user ->
              case Events.remove_participant_status(event, user) do
                {:ok, _} ->
                  {:ok, %{success: true, errors: []}}

                {:error, reason} ->
                  {:ok,
                   %{
                     success: false,
                     errors: [%{field: "base", message: inspect(reason)}]
                   }}
              end
          end
        else
          {:ok, %{success: false, errors: [%{field: "base", message: "NOT_FOUND"}]}}
        end
    end
  end

  def resend_invitation(_parent, %{slug: slug, user_id: user_id}, %{
        context: %{current_user: current_user}
      }) do
    alias EventasaurusApp.Accounts

    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok, %{success: false, errors: [%{field: "slug", message: "Event not found"}]}}

      event ->
        if Events.user_is_organizer?(event, current_user) do
          case Accounts.get_user(user_id) do
            nil ->
              {:ok, %{success: false, errors: [%{field: "user_id", message: "User not found"}]}}

            user ->
              result =
                Events.process_guest_invitations(
                  event,
                  current_user,
                  manual_emails: [user.email],
                  mode: :invitation
                )

              case result do
                %{successful_invitations: _count} ->
                  {:ok, %{success: true, errors: []}}

                {:error, reason} ->
                  {:ok,
                   %{
                     success: false,
                     errors: [%{field: "base", message: inspect(reason)}]
                   }}
              end
          end
        else
          {:ok, %{success: false, errors: [%{field: "base", message: "NOT_FOUND"}]}}
        end
    end
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{field: to_string(field), message: message}
      end)
    end)
  end
end
