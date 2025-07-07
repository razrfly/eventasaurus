defmodule EventasaurusWeb.UserSearchController do
  use EventasaurusWeb, :controller

  import EventasaurusWeb.Plugs.AuthPlug

  alias EventasaurusApp.Accounts

  require Logger

  # Enhanced security plugs for user search
  plug :sanitize_and_validate_input
  plug :require_permission, [action: :search_users] when action in [:search]

  @doc """
  Searches for users that can be added as event organizers.

  GET /api/users/search?q=query&page=1&per_page=20&event_id=123

  Query parameters:
  - q (required): Search query string
  - page (optional): Page number for pagination (default: 1)
  - per_page (optional): Results per page (default: 20, max: 50)
  - event_id (optional): Event ID to provide context for filtering (excludes existing organizers)

  Returns JSON with search results and pagination info.
  Only returns users with public profiles unless requester has manage privileges for the event.
  """
  def search(conn, params) do
    current_user = conn.assigns[:user]

    if current_user do
      case validate_search_params(params) do
        {:ok, %{query: query, page: page, per_page: per_page, event_id: event_id}} ->
          process_user_search(conn, current_user, query, page, per_page, event_id)

        {:error, errors} ->
          Logger.warning("Invalid user search parameters",
            errors: errors,
            user_id: current_user.id,
            params: sanitize_params(params)
          )

          conn
          |> put_status(:bad_request)
          |> json(%{
            success: false,
            error: "validation_failed",
            message: "Invalid search parameters",
            details: errors
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to search for users"
      })
    end
  end

  # Private helper functions

  defp validate_search_params(params) do
    query = Map.get(params, "q", "") |> String.trim()
    page = safe_parse_positive_integer(Map.get(params, "page", "1"), 1)
    per_page = safe_parse_positive_integer(Map.get(params, "per_page", "20"), 20)
    event_id = safe_parse_positive_integer(Map.get(params, "event_id"), nil)

    errors = []

    # Validate query
    errors = if String.length(query) < 2 do
      ["Search query must be at least 2 characters long" | errors]
    else
      errors
    end

    # Validate per_page limit
    per_page = min(per_page, 50)  # Cap at 50 for performance

    if Enum.empty?(errors) do
      {:ok, %{query: query, page: page, per_page: per_page, event_id: event_id}}
    else
      {:error, errors}
    end
  end

  defp process_user_search(conn, current_user, query, page, per_page, event_id) do
    # If event_id is provided, verify user has permission to manage that event
    if event_id do
      case validate_event_permissions(current_user, event_id) do
        :ok ->
          perform_search(conn, current_user, query, page, per_page, event_id)
        {:error, reason} ->
          conn
          |> put_status(:forbidden)
          |> json(%{
            success: false,
            error: "forbidden",
            message: reason
          })
      end
    else
      # No event context, perform general search
      perform_search(conn, current_user, query, page, per_page, nil)
    end
  end

  defp perform_search(conn, current_user, query, page, per_page, event_id) do
    offset = (page - 1) * per_page

    search_opts = [
      limit: per_page,
      offset: offset,
      exclude_user_id: current_user.id,
      event_id: event_id,
      requesting_user_id: current_user.id
    ]

    try do
      users = Accounts.search_users_for_organizers(query, search_opts)

      # Format user results for response with context-aware privacy controls
      formatted_users = Enum.map(users, &format_user_search_result_with_context(&1, current_user, event_id))

      # Calculate pagination info
      has_more = length(users) == per_page

      Logger.info("User search completed",
        query: query,
        results_count: length(users),
        user_id: current_user.id,
        event_id: event_id
      )

      conn
      |> json(%{
        success: true,
        data: %{
          users: formatted_users,
          query: query,
          pagination: %{
            page: page,
            per_page: per_page,
            has_more: has_more,
            results_count: length(users)
          },
          context: %{
            event_id: event_id
          }
        }
      })

    rescue
      error ->
        Logger.error("User search failed",
          query: query,
          user_id: current_user.id,
          error: inspect(error)
        )

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "search_failed",
          message: "Unable to complete user search"
        })
    end
  end

  # Helper function to validate event permissions
  defp validate_event_permissions(user, event_id) do
    case EventasaurusApp.Events.get_event(event_id) do
      %EventasaurusApp.Events.Event{} = event ->
        if EventasaurusApp.Events.user_can_manage_event?(user, event) do
          :ok
        else
          {:error, "You don't have permission to manage this event"}
        end
      nil ->
        {:error, "Event not found"}
    end
  end

  # Enhanced format function that conditionally exposes user information
  # based on privacy levels and requester privileges
  defp format_user_search_result_with_context(user, requesting_user, event_id) do
    # Double-check privacy: if profile is private and requester doesn't have access,
    # don't expose any information (this is a safety net as the query should already filter)
    if user.profile_public or can_access_sensitive_info?(requesting_user, event_id) do
      base_info = %{
        id: user.id,
        name: user.name,
        username: user.username,
        profile_public: user.profile_public,
        avatar_url: EventasaurusApp.Avatars.generate_user_avatar(user, size: 40)
      }

      # Only include email if requester has management privileges for the event
      # or if this is a private search context where email is necessary
      if can_access_sensitive_info?(requesting_user, event_id) do
        Map.put(base_info, :email, user.email)
      else
        base_info
      end
    else
      # This should not happen due to query filtering, but safety net
      # In case of private profile without proper access, return minimal info
      %{
        id: user.id,
        name: "Private User",
        username: nil,
        profile_public: false,
        avatar_url: EventasaurusApp.Avatars.generate_user_avatar(%{email: "private@example.com"}, size: 40)
      }
    end
  end

  # Helper to determine if requester can access sensitive information
  defp can_access_sensitive_info?(requesting_user, event_id) do
    case event_id do
      nil ->
        # No event context - only basic info
        false
      _ ->
        # Check if user can manage the event (can add organizers)
        case validate_event_permissions(requesting_user, event_id) do
          :ok -> true
          _ -> false
        end
    end
  end

  defp safe_parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp safe_parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
  defp safe_parse_positive_integer(nil, default), do: default
  defp safe_parse_positive_integer(_, default), do: default

  defp sanitize_params(params) do
    # Remove sensitive information from params for logging
    Map.take(params, ["q", "page", "per_page"])
  end
end
