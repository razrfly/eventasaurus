defmodule EventasaurusWeb.Api.V1.Mobile.PlanController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventPlans
  alias EventasaurusDiscovery.PublicEvents

  require Logger

  @doc """
  POST /api/v1/mobile/events/:slug/plan-with-friends

  Creates a Quick Plan (private event) linked to a public event and sends email invitations.
  """
  def create(conn, %{"slug" => slug} = params) do
    user = conn.assigns.user

    case PublicEvents.get_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Event not found"})

      public_event ->
        emails = params["emails"] || []
        message = params["message"]

        # Build attrs for EventPlans.create_from_public_event
        plan_attrs = build_plan_attrs(params)

        case EventPlans.create_from_public_event(public_event.id, user.id, plan_attrs) do
          {:ok, {:created, _event_plan, private_event}} ->
            # Send email invitations
            invite_count = send_email_invitations(private_event, emails, message, user)

            json(conn, %{
              plan: %{
                slug: private_event.slug,
                title: private_event.title,
                invite_count: invite_count,
                created_at: private_event.inserted_at
              }
            })

          {:ok, {:existing, _event_plan, private_event}} ->
            json(conn, %{
              plan: %{
                slug: private_event.slug,
                title: private_event.title,
                invite_count: 0,
                created_at: private_event.inserted_at
              },
              already_exists: true
            })

          {:error, :event_in_past} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "event_in_past", message: "Cannot create plans for past events"})

          {:error, reason} ->
            Logger.error("Failed to create plan",
              slug: slug,
              user_id: user.id,
              reason: inspect(reason)
            )

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "create_failed", message: "Could not create plan"})
        end
    end
  end

  @doc """
  GET /api/v1/mobile/events/:slug/plan-with-friends

  Returns the current user's existing Quick Plan for this event, if any.
  """
  def show(conn, %{"slug" => slug}) do
    user = conn.assigns.user

    case PublicEvents.get_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Event not found"})

      public_event ->
        case EventPlans.get_user_plan_for_event(user.id, public_event.id) do
          %{private_event: private_event} = event_plan ->
            invite_count =
              Events.list_event_participants(private_event)
              |> Enum.count(fn p -> p.role == :invitee end)

            json(conn, %{
              plan: %{
                slug: private_event.slug,
                title: private_event.title,
                created_at: event_plan.inserted_at,
                invite_count: invite_count
              }
            })

          nil ->
            json(conn, %{plan: nil})
        end
    end
  end

  # --- Private helpers ---

  defp build_plan_attrs(params) do
    base = %{}

    case params["occurrence"] do
      %{"datetime" => datetime_str} when is_binary(datetime_str) ->
        case DateTime.from_iso8601(datetime_str) do
          {:ok, dt, _offset} -> Map.put(base, :occurrence_datetime, dt)
          _ -> base
        end

      _ ->
        base
    end
  end

  defp send_email_invitations(_event, [], _message, _organizer), do: 0

  defp send_email_invitations(event, emails, message, organizer) do
    Events.process_guest_invitations(
      event,
      organizer,
      manual_emails: emails,
      invitation_message: message || "",
      mode: :invitation
    )

    length(emails)
  end
end
