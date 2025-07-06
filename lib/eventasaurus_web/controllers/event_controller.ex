defmodule EventasaurusWeb.EventController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventParticipant
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
      |> json(%{
        success: true,
        event: serialize_event_for_json(updated_event, :scheduling)
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
      |> json(%{
        success: true,
        event: serialize_event_for_json(updated_event, :polling)
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
      |> json(%{
        success: true,
        event: serialize_event_for_json(updated_event, :threshold)
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
      |> json(%{
        success: true,
        event: serialize_event_for_json(updated_event, [:is_ticketed, :taxation_type])
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
      |> json(%{
        success: true,
        event: serialize_event_for_json(updated_event, :details)
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
      |> json(%{
        success: true,
        event: serialize_event_for_json(updated_event, :publish)
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

  defp serialize_event_for_json(event, fields) do
    base_fields = %{
      id: event.id,
      slug: event.slug,
      status: event.status,
      computed_phase: event.computed_phase
    }

    case fields do
      :default ->
        base_fields

      :full ->
        Map.merge(base_fields, %{
          title: event.title,
          description: event.description,
          tagline: event.tagline,
          theme: event.theme,
          taxation_type: event.taxation_type,
          is_ticketed: event.is_ticketed,
          start_at: event.start_at,
          ends_at: event.ends_at,
          timezone: event.timezone,
          visibility: event.visibility
        })

      :details ->
        Map.merge(base_fields, %{
          title: event.title,
          description: event.description,
          tagline: event.tagline,
          theme: event.theme,
          taxation_type: event.taxation_type,
          is_ticketed: event.is_ticketed
        })

      :scheduling ->
        Map.merge(base_fields, %{
          start_at: event.start_at,
          ends_at: event.ends_at,
          timezone: event.timezone,
          taxation_type: event.taxation_type,
          is_ticketed: event.is_ticketed
        })

      :polling ->
        Map.merge(base_fields, %{
          polling_deadline: event.polling_deadline,
          taxation_type: event.taxation_type,
          is_ticketed: event.is_ticketed
        })

      :threshold ->
        Map.merge(base_fields, %{
          threshold_count: event.threshold_count,
          taxation_type: event.taxation_type,
          is_ticketed: event.is_ticketed
        })

      :publish ->
        Map.merge(base_fields, %{
          visibility: event.visibility,
          taxation_type: event.taxation_type,
          is_ticketed: event.is_ticketed
        })

      custom_fields when is_list(custom_fields) ->
        custom_data = custom_fields
        |> Enum.reduce(%{}, fn field, acc ->
          Map.put(acc, field, Map.get(event, field))
        end)
        Map.merge(base_fields, custom_data)
    end
  end

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
    allowed_fields = ["title", "description", "tagline", "cover_image_url", "theme", "taxation_type"]
    atom_map = %{
      "title" => :title,
      "description" => :description,
      "tagline" => :tagline,
      "cover_image_url" => :cover_image_url,
      "theme" => :theme,
      "taxation_type" => :taxation_type
    }

    params
    |> Map.take(allowed_fields)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key = Map.get(atom_map, key)
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

  ## Generic Participant Status Management API Actions

  @doc """
  Updates the current user's participant status for an event.

  Expects a "status" parameter in the request body with a valid EventParticipant status:
  "pending", "accepted", "declined", "cancelled", "confirmed_with_order", "interested"
  """
  def update_participant_status(conn, %{"slug" => slug} = params) do
    status = params["status"]
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            # Validate status is a valid EventParticipant status
            valid_statuses = ["pending", "accepted", "declined", "cancelled", "confirmed_with_order", "interested"]

            if status in valid_statuses do
              status_atom = String.to_atom(status)

              case Events.update_participant_status(event, user, status_atom) do
                {:ok, participant} ->
                  count = Events.count_participants_by_status(event, status_atom)

                  conn
                  |> put_status(:ok)
                  |> json(%{
                    success: true,
                    data: %{
                      status: status,
                      updated_at: participant.updated_at,
                      event: %{
                        slug: event.slug,
                        participant_count: count
                      }
                    }
                  })

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Unable to update participant status", details: format_changeset_errors(changeset)})
              end
            else
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid status. Valid statuses are: #{Enum.join(valid_statuses, ", ")}"})
            end

          {:error, _} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication required"})
        end
    end
  end

  @doc """
  Removes the current user's participation status from an event.

  Can optionally specify which status to remove via query parameter "status".
  If no status specified, removes any participation record for the user.
  """
  def remove_participant_status(conn, %{"slug" => slug} = params) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            # Optional status filter for removal
            status_filter = case params["status"] do
              status when is_binary(status) -> String.to_atom(status)
              _ -> nil
            end

            case Events.remove_participant_status(event, user, status_filter) do
              {:ok, :removed} ->
                conn
                |> json(%{
                  success: true,
                  data: %{
                    status: "removed",
                    event: %{
                      slug: event.slug
                    }
                  }
                })

              {:ok, :not_participant} ->
                conn
                |> json(%{
                  success: true,
                  data: %{
                    status: "not_participant",
                    event: %{
                      slug: event.slug
                    }
                  }
                })

              {:error, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Unable to remove participant status", details: inspect(reason)})
            end

          {:error, _} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication required"})
        end
    end
  end

  @doc """
  Gets the current user's participant status for an event.
  """
  def get_participant_status(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            case Events.get_event_participant_by_event_and_user(event, user) do
              %EventParticipant{status: status, metadata: metadata, updated_at: updated_at} ->
                conn
                |> json(%{
                  success: true,
                  data: %{
                    status: Atom.to_string(status),
                    updated_at: updated_at,
                    metadata: metadata
                  }
                })

              nil ->
                conn
                |> json(%{
                  success: true,
                  data: %{
                    status: "not_participant",
                    updated_at: nil,
                    metadata: nil
                  }
                })
            end

          {:error, _} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication required"})
        end
    end
  end

  @doc """
  Lists participants by status for an event (organizers only).

  The status is provided as a URL parameter, e.g., /events/my-event/participants/interested
  """
  def list_participants_by_status(conn, %{"slug" => slug, "status" => status} = params) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              # Validate status
              valid_statuses = ["pending", "accepted", "declined", "cancelled", "confirmed_with_order", "interested"]

              if status in valid_statuses do
                status_atom = String.to_atom(status)

                # Parse pagination parameters
                page = params |> Map.get("page", "1") |> String.to_integer()
                per_page = params |> Map.get("per_page", "20") |> String.to_integer() |> min(100)

                # Get participants by status
                participants = Events.list_participants_by_status(event, status_atom)
                total_count = length(participants)

                # Simple pagination
                start_index = (page - 1) * per_page
                paginated_participants = participants
                                      |> Enum.slice(start_index, per_page)
                                      |> Enum.map(fn user ->
                                        participant = Events.get_event_participant_by_event_and_user(event, user)
                                        %{
                                          id: user.id,
                                          name: user.name,
                                          email: user.email,
                                          status: status,
                                          updated_at: participant.updated_at,
                                          metadata: participant.metadata
                                        }
                                      end)

                total_pages = ceil(total_count / per_page)

                conn
                |> json(%{
                  success: true,
                  data: %{
                    participants: paginated_participants,
                    status: status,
                    pagination: %{
                      current_page: page,
                      total_pages: total_pages,
                      total_count: total_count,
                      per_page: per_page
                    }
                  }
                })
              else
                conn
                |> put_status(:bad_request)
                |> json(%{error: "Invalid status. Valid statuses are: #{Enum.join(valid_statuses, ", ")}"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "You don't have permission to view this event's data"})
            end

          {:error, _} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication required"})
        end
    end
  end

  @doc """
  Gets participant analytics for an event (organizers only).

  Returns statistics for all participant statuses.
  """
  def participant_analytics(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Event not found"})

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              analytics = Events.get_participant_analytics(event)

              conn
              |> json(%{
                success: true,
                data: %{
                  analytics: analytics,
                  trends: %{
                    daily_changes: [] # Placeholder - can be enhanced with actual daily tracking
                  }
                }
              })
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "You don't have permission to view this event's data"})
            end

          {:error, _} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication required"})
        end
    end
  end
end
