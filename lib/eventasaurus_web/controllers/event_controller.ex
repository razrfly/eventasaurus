defmodule EventasaurusWeb.EventController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Venues

  # Internal event view action (for /events/:slug)
  def show(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/dashboard")

      event ->
        # Get the current user (required due to authentication pipeline)
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            # Check if user can manage this event
            if Events.user_can_manage_event?(user, event) do
              # Get registration status for the organizer
              registration_status = Events.get_user_registration_status(event, user)

              # Load venue and organizers for the event
              venue = if event.venue_id, do: Venues.get_venue(event.venue_id), else: nil
              organizers = Events.list_event_organizers(event)

              # Load participants (guests) for the event
              participants = Events.list_event_participants(event)
                            |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})

              # Get polling data if event is in polling state
              {date_options, votes_by_date, votes_breakdown} = if event.status == :polling do
                poll = Events.get_event_date_poll(event)
                if poll do
                  options = Events.list_event_date_options(poll)
                                      votes = Events.list_votes_for_poll(poll)

                  # Group votes by date
                  votes_by_date = Enum.group_by(votes, & &1.event_date_option.date)

                  # Pre-compute vote breakdowns to avoid O(n²) in template
                  votes_breakdown =
                    votes_by_date
                    |> Map.new(fn {date, votes} ->
                      breakdown = Enum.frequencies_by(votes, &to_string(&1.vote_type))
                      total = length(votes)
                      {date, %{
                        total: total,
                        yes: Map.get(breakdown, "yes", 0),
                        if_need_be: Map.get(breakdown, "if_need_be", 0),
                        no: Map.get(breakdown, "no", 0)
                      }}
                    end)

                  {options, votes_by_date, votes_breakdown}
                else
                  {[], %{}, %{}}
                end
              else
                {[], %{}, %{}}
              end

              conn
              |> assign(:venue, venue)
              |> assign(:organizers, organizers)
              |> assign(:participants, participants)
              |> assign(:date_options, date_options)
              |> assign(:votes_by_date, votes_by_date)
              |> assign(:votes_breakdown, votes_breakdown)
              |> assign(:is_manager, true)
              |> assign(:registration_status, registration_status)
              |> render(:show, event: event, user: user)
            else
              conn
              |> put_flash(:error, "You don't have permission to manage this event")
              |> redirect(to: ~p"/dashboard")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "Authentication error")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  # Attendees management (stub for now)
  def attendees(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/")

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              attendees = Events.list_event_participants(event)
              render(conn, :attendees, event: event, attendees: attendees)
            else
              conn
              |> put_flash(:error, "You don't have permission to view attendees")
              |> redirect(to: ~p"/#{event.slug}")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "You must be logged in to view attendees")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  def delete(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/dashboard")

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              case Events.delete_event(event) do
                {:ok, _} ->
                  conn
                  |> put_flash(:info, "Event deleted successfully")
                  |> redirect(to: ~p"/dashboard")

                {:error, _} ->
                  conn
                  |> put_flash(:error, "Unable to delete event")
                  |> redirect(to: ~p"/dashboard")
              end
            else
              conn
              |> put_flash(:error, "You don't have permission to delete this event")
              |> redirect(to: ~p"/dashboard")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "You must be logged in to delete events")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  @doc """
  Cancel an event by setting its status to canceled.
  This is separate from delete to maintain data integrity.
  """
  def cancel(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/dashboard")

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              case Events.transition_event(event, :canceled) do
                {:ok, canceled_event} ->
                  conn
                  |> put_flash(:info, "Event canceled successfully")
                  |> redirect(to: ~p"/#{canceled_event.slug}")

                {:error, _changeset} ->
                  conn
                  |> put_flash(:error, "Unable to cancel event")
                  |> redirect(to: ~p"/#{event.slug}")
              end
            else
              conn
              |> put_flash(:error, "You don't have permission to cancel this event")
              |> redirect(to: ~p"/dashboard")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "You must be logged in to cancel events")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  @doc """
  Auto-correct an event's status based on its current attributes.
  Useful for fixing events that may have gotten out of sync.
  """
  def auto_correct_status(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/dashboard")

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              case Events.auto_correct_event_status(event) do
                {:ok, corrected_event} ->
                  message = if corrected_event.status != event.status do
                    "Event status corrected from #{event.status} to #{corrected_event.status}"
                  else
                    "Event status is already correct"
                  end

                  conn
                  |> put_flash(:info, message)
                  |> redirect(to: ~p"/#{corrected_event.slug}")

                {:error, _changeset} ->
                  conn
                  |> put_flash(:error, "Unable to correct event status")
                  |> redirect(to: ~p"/#{event.slug}")
              end
            else
              conn
              |> put_flash(:error, "You don't have permission to modify this event")
              |> redirect(to: ~p"/dashboard")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "You must be logged in to modify events")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  ## Action-Driven Setup API Actions

  @doc """
  Sets or updates the start date for an event.
  Expects: start_at (ISO8601 datetime), optional: ends_at, timezone
  """
  def pick_date(conn, %{"slug" => slug} = params) do
    with {:ok, event} <- get_event_with_auth(conn, slug),
         {:ok, start_at} <- parse_datetime(params["start_at"]),
         opts <- build_pick_date_opts(params),
         {:ok, updated_event} <- Events.pick_date(event, start_at, opts) do

      conn
      |> put_flash(:info, "Event date updated successfully")
      |> json(%{
        success: true,
        event: %{
          id: updated_event.id,
          slug: updated_event.slug,
          status: updated_event.status,
          computed_phase: updated_event.computed_phase,
          start_at: updated_event.start_at,
          ends_at: updated_event.ends_at,
          timezone: updated_event.timezone
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to modify this event"})

      {:error, :invalid_datetime} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid datetime format. Use ISO8601 format."})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  @doc """
  Enables polling for an event.
  Expects: polling_deadline (ISO8601 datetime)
  """
  def enable_polling(conn, %{"slug" => slug, "polling_deadline" => polling_deadline_str}) do
    with {:ok, event} <- get_event_with_auth(conn, slug),
         {:ok, polling_deadline} <- parse_datetime(polling_deadline_str),
         {:ok, updated_event} <- Events.enable_polling(event, polling_deadline) do

      conn
      |> put_flash(:info, "Polling enabled successfully")
      |> json(%{
        success: true,
        event: %{
          id: updated_event.id,
          slug: updated_event.slug,
          status: updated_event.status,
          computed_phase: updated_event.computed_phase,
          polling_deadline: updated_event.polling_deadline
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to modify this event"})

      {:error, :invalid_datetime} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid datetime format. Use ISO8601 format."})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  def enable_polling(conn, %{"slug" => _slug}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "polling_deadline is required"})
  end

  @doc """
  Sets a threshold count for an event.
  Expects: threshold_count (integer)
  """
  def set_threshold(conn, %{"slug" => slug, "threshold_count" => threshold_count_str}) do
    with {:ok, event} <- get_event_with_auth(conn, slug),
         {threshold_count, ""} <- Integer.parse(threshold_count_str),
         true <- threshold_count > 0,
         {:ok, updated_event} <- Events.set_threshold(event, threshold_count) do

      conn
      |> put_flash(:info, "Threshold set successfully")
      |> json(%{
        success: true,
        event: %{
          id: updated_event.id,
          slug: updated_event.slug,
          status: updated_event.status,
          computed_phase: updated_event.computed_phase,
          threshold_count: updated_event.threshold_count
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to modify this event"})

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "threshold_count must be a positive integer"})

      false ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "threshold_count must be greater than 0"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  def set_threshold(conn, %{"slug" => _slug}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "threshold_count is required"})
  end

  @doc """
  Enables ticketing for an event.
  This is a placeholder for future ticketing system integration.
  """
  def enable_ticketing(conn, %{"slug" => slug} = params) do
    with {:ok, event} <- get_event_with_auth(conn, slug),
         ticketing_options <- Map.get(params, "ticketing_options", %{}),
         {:ok, updated_event} <- Events.enable_ticketing(event, ticketing_options) do

      conn
      |> put_flash(:info, "Ticketing enabled successfully")
      |> json(%{
        success: true,
        event: %{
          id: updated_event.id,
          slug: updated_event.slug,
          status: updated_event.status,
          computed_phase: updated_event.computed_phase
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to modify this event"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  @doc """
  Adds or updates details for an event.
  Expects: Any combination of title, description, tagline, cover_image_url, theme, etc.
  """
  def add_details(conn, %{"slug" => slug} = params) do
    with {:ok, event} <- get_event_with_auth(conn, slug),
         details <- extract_event_details(params),
         {:ok, updated_event} <- Events.add_details(event, details) do

      conn
      |> put_flash(:info, "Event details updated successfully")
      |> json(%{
        success: true,
        event: %{
          id: updated_event.id,
          slug: updated_event.slug,
          status: updated_event.status,
          computed_phase: updated_event.computed_phase,
          title: updated_event.title,
          description: updated_event.description,
          tagline: updated_event.tagline,
          theme: updated_event.theme
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to modify this event"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  @doc """
  Publishes an event by transitioning it to confirmed status.
  """
  def publish(conn, %{"slug" => slug}) do
    with {:ok, event} <- get_event_with_auth(conn, slug),
         {:ok, updated_event} <- Events.publish_event(event) do

      conn
      |> put_flash(:info, "Event published successfully")
      |> json(%{
        success: true,
        event: %{
          id: updated_event.id,
          slug: updated_event.slug,
          status: updated_event.status,
          computed_phase: updated_event.computed_phase,
          visibility: updated_event.visibility
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You don't have permission to modify this event"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_changeset_errors(changeset)})
    end
  end

  ## Helper Functions for Action API

  defp get_event_with_auth(conn, slug) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:error, :not_found}

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              {:ok, event}
            else
              {:error, :unauthorized}
            end

          {:error, _} ->
            {:error, :unauthorized}
        end
    end
  end

  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_datetime}
    end
  end
  defp parse_datetime(_), do: {:error, :invalid_datetime}

  defp build_pick_date_opts(params) do
    opts = []

    opts = case params["ends_at"] do
      ends_at_str when is_binary(ends_at_str) ->
        case parse_datetime(ends_at_str) do
          {:ok, ends_at} -> Keyword.put(opts, :ends_at, ends_at)
          {:error, _} -> opts
        end
      _ -> opts
    end

    opts = case params["timezone"] do
      timezone when is_binary(timezone) -> Keyword.put(opts, :timezone, timezone)
      _ -> opts
    end

    opts
  end

  defp extract_event_details(params) do
    allowed_fields = ["title", "description", "tagline", "cover_image_url", "theme"]

    params
    |> Map.take(allowed_fields)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key = String.to_existing_atom(key)
      Map.put(acc, atom_key, value)
    end)
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
