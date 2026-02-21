defmodule EventasaurusWeb.Resolvers.PlanResolver do
  @moduledoc """
  Resolvers for Plan with Friends GraphQL queries and mutations.
  """

  require Logger

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventPlans
  alias EventasaurusDiscovery.PublicEvents

  @max_suggestion_limit 50

  @spec participant_suggestions(any(), map(), map()) :: {:ok, list()} | {:error, term()}
  def participant_suggestions(_parent, args, %{context: %{current_user: user}}) do
    limit =
      args
      |> Map.get(:limit, 20)
      |> max(1)
      |> min(@max_suggestion_limit)

    suggestions = Events.get_participant_suggestions(user, limit: limit)
    {:ok, suggestions}
  end

  def my_plan(_parent, %{slug: slug}, %{context: %{current_user: user}}) do
    case PublicEvents.get_by_slug(slug) do
      nil ->
        {:ok, nil}

      public_event ->
        case EventPlans.get_user_plan_for_event(user.id, public_event.id) do
          %{private_event: private_event} = event_plan ->
            invite_count =
              Events.list_event_participants(private_event)
              |> Enum.count(fn p -> p.role == :invitee end)

            {:ok,
             %{
               slug: private_event.slug,
               title: private_event.title,
               invite_count: invite_count,
               created_at: event_plan.inserted_at,
               already_exists: nil
             }}

          nil ->
            {:ok, nil}
        end
    end
  end

  @max_invite_emails 50

  def create_plan(_parent, %{slug: slug} = args, %{
        context: %{current_user: user}
      }) do
    # Resolve friend_ids to emails and merge with provided emails
    emails = Map.get(args, :emails, [])
    friend_emails = resolve_friend_emails(Map.get(args, :friend_ids, []))
    all_emails = Enum.uniq(emails ++ friend_emails)

    cond do
      Enum.empty?(all_emails) ->
        {:ok,
         %{
           plan: nil,
           errors: [%{field: "emails", message: "At least one recipient required"}]
         }}

      length(all_emails) > @max_invite_emails ->
        {:ok,
         %{
           plan: nil,
           errors: [
             %{field: "emails", message: "Maximum #{@max_invite_emails} invitations per plan"}
           ]
         }}

      true ->
        do_create_plan(slug, all_emails, args, user)
    end
  end

  defp do_create_plan(slug, emails, args, user) do
    case PublicEvents.get_by_slug(slug) do
      nil ->
        {:ok, %{plan: nil, errors: [%{field: "slug", message: "Event not found"}]}}

      public_event ->
        plan_attrs = build_plan_attrs(args)

        case EventPlans.create_from_public_event(public_event.id, user.id, plan_attrs) do
          {:ok, {:created, event_plan, private_event}} ->
            invite_count = send_email_invitations(private_event, emails, args[:message], user)

            {:ok,
             %{
               plan: %{
                 slug: private_event.slug,
                 title: private_event.title,
                 invite_count: invite_count,
                 created_at: event_plan.inserted_at,
                 already_exists: false
               },
               errors: []
             }}

          {:ok, {:existing, event_plan, private_event}} ->
            invite_count =
              Events.list_event_participants(private_event)
              |> Enum.count(fn p -> p.role == :invitee end)

            {:ok,
             %{
               plan: %{
                 slug: private_event.slug,
                 title: private_event.title,
                 invite_count: invite_count,
                 created_at: event_plan.inserted_at,
                 already_exists: true
               },
               errors: []
             }}

          {:error, :event_in_past} ->
            {:ok,
             %{
               plan: nil,
               errors: [%{field: "slug", message: "Cannot create plans for past events"}]
             }}

          {:error, reason} ->
            Logger.error("Failed to create plan via GraphQL",
              slug: slug,
              user_id: user.id,
              reason: inspect(reason)
            )

            {:ok, %{plan: nil, errors: [%{field: "base", message: "Could not create plan"}]}}
        end
    end
  end

  defp resolve_friend_emails(nil), do: []
  defp resolve_friend_emails([]), do: []

  defp resolve_friend_emails(friend_ids) do
    friend_ids
    |> Enum.map(fn id ->
      case Accounts.get_user(id) do
        %{email: email} -> email
        nil ->
          Logger.warning("Friend ID #{id} not found, skipping")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_plan_attrs(args) do
    base = %{}

    case args[:occurrence] do
      %{datetime: dt} -> Map.put(base, :occurrence_datetime, dt)
      _ -> base
    end
  end

  defp send_email_invitations(_event, [], _message, _organizer), do: 0

  defp send_email_invitations(event, emails, message, organizer) do
    result =
      Events.process_guest_invitations(
        event,
        organizer,
        manual_emails: emails,
        invitation_message: message || "",
        mode: :invitation
      )

    case result do
      %{successful_invitations: count} ->
        count

      {:error, reason} ->
        Logger.error("Failed to send email invitations",
          event_id: event.id,
          email_count: length(emails),
          reason: inspect(reason)
        )

        0

      other ->
        Logger.warning("Unexpected result from process_guest_invitations",
          event_id: event.id,
          result: inspect(other)
        )

        0
    end
  end
end
