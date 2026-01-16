defmodule EventasaurusWeb.Helpers.PlanWithFriendsHelpers do
  @moduledoc """
  Shared helpers for Plan with Friends functionality across LiveViews.

  Extracts common logic for flexible planning submission and date range parsing
  to avoid duplication between public_event_show_live.ex and public_movie_screenings_live.ex.
  """

  require Logger
  use Gettext, backend: EventasaurusWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias EventasaurusApp.Planning.OccurrencePlanningWorkflow
  alias Phoenix.LiveView.Socket

  @doc """
  Executes flexible planning workflow for a movie.

  Creates a private event with a poll containing occurrence options based on filter criteria.

  ## Parameters

  - `socket` - The LiveView socket with assigns:
    - `:selected_users` - List of selected user structs with `:id` field
    - `:selected_emails` - List of email strings for manual invitations
    - `:filter_criteria` - Map with `:date_from`, `:date_to`, `:time_preferences`, `:limit`
  - `movie` - The movie struct with `:id` and `:title` fields
  - `user` - The authenticated user creating the plan
  - `opts` - Optional keyword list:
    - `:default_limit` - Default limit for occurrences (default: 20)

  ## Returns

  `{:noreply, socket}` tuple with appropriate flash message and redirect/assign updates.
  """
  @spec execute_flexible_plan(Socket.t(), map(), map(), keyword()) :: {:noreply, Socket.t()}
  def execute_flexible_plan(socket, movie, user, opts \\ []) do
    default_limit = Keyword.get(opts, :default_limit, 20)

    # Get friend IDs from selected users
    friend_ids = Enum.map(socket.assigns.selected_users, & &1.id)

    # Convert filter criteria to workflow format
    # CRITICAL: Include city_ids to constrain results to the current city only
    # Without this, "all venues" would return venues from ALL cities globally
    # See: https://github.com/razrfly/eventasaurus/issues/3252
    city_ids = get_city_ids_from_socket(socket)

    filter_criteria = %{
      date_range: parse_date_range(socket.assigns.filter_criteria),
      time_preferences: socket.assigns.filter_criteria[:time_preferences] || [],
      city_ids: city_ids,
      limit: socket.assigns.filter_criteria[:limit] || default_limit
    }

    # Create flexible planning with poll
    case OccurrencePlanningWorkflow.start_flexible_planning(
           "movie",
           movie.id,
           user.id,
           filter_criteria,
           friend_ids,
           event_title: "#{movie.title} - Group Planning",
           poll_title: gettext("Which showtime works best?"),
           manual_emails: socket.assigns.selected_emails
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Poll created! Your friends can now vote on their preferred showtime.")
         )
         |> redirect(to: "/events/#{result.private_event.slug}")}

      {:error, :no_occurrences_found} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("No showtimes found matching your filters. Please try different criteria.")
         )}

      {:error, reason} ->
        Logger.error("Flexible planning failed: #{inspect(reason)}")

        # Show detailed error in development only
        error_message =
          if Application.get_env(:eventasaurus, :env) == :dev do
            "Error creating poll: #{inspect(reason)}"
          else
            gettext("Sorry, there was an error creating your poll. Please try again.")
          end

        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, false)
         |> put_flash(:error, error_message)}
    end
  end

  @doc """
  Parses date range from filter criteria into workflow format.

  Handles both ISO8601 string format and nil/missing values with appropriate fallbacks.

  ## Parameters

  - `filter_criteria` - Map that may contain `:date_from` and `:date_to` as ISO8601 strings

  ## Returns

  Map with `:start` and `:end` Date values. Falls back to today + 7 days if parsing fails.

  ## Examples

      iex> parse_date_range(%{date_from: "2024-01-15", date_to: "2024-01-22"})
      %{start: ~D[2024-01-15], end: ~D[2024-01-22]}

      iex> parse_date_range(%{})
      %{start: ~D[2024-01-15], end: ~D[2024-01-22]}  # Today + 7 days
  """
  @spec parse_date_range(map()) :: %{start: Date.t(), end: Date.t()}
  def parse_date_range(%{date_from: date_from_str, date_to: date_to_str})
      when is_binary(date_from_str) and is_binary(date_to_str) do
    with {:ok, date_from} <- Date.from_iso8601(date_from_str),
         {:ok, date_to} <- Date.from_iso8601(date_to_str) do
      %{start: date_from, end: date_to}
    else
      _ ->
        # Fallback to default date range (today + 7 days)
        default_date_range()
    end
  end

  def parse_date_range(_filter_criteria) do
    # Fallback for missing or invalid date range
    default_date_range()
  end

  # Private helper for default date range
  defp default_date_range do
    today = Date.utc_today()
    %{start: today, end: Date.add(today, 7)}
  end

  # Private helper to extract city_ids from socket assigns
  # Used to constrain occurrence searches to the current city only
  defp get_city_ids_from_socket(socket) do
    case socket.assigns[:city] do
      %{id: city_id} when not is_nil(city_id) -> [city_id]
      _ -> []
    end
  end
end
