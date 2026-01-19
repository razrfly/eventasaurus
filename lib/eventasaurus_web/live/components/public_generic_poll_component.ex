defmodule EventasaurusWeb.PublicGenericPollComponent do
  @moduledoc """
  Simple public interface for generic polling (non-movie polls).

  Shows existing poll options and allows users to add their own suggestions
  during the list_building phase, or vote during the voting phase.
  """

  use EventasaurusWeb, :live_component

  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Poll
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Utils.TimeUtils
  alias EventasaurusWeb.Utils.PollPhaseUtils

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.VoterCountDisplay

  import EventasaurusWeb.PollOptionHelpers,
    only: [get_import_info: 1, format_import_attribution: 1]

  @impl true
  def update(assigns, socket) do
    event = assigns.event
    user = assigns.current_user
    poll = assigns.poll

    if poll do
      # Load poll options with suggested_by user
      poll_options =
        Events.list_poll_options(poll)
        |> Repo.preload(:suggested_by)

      # Load poll statistics for voter count display
      poll_stats =
        try do
          Events.get_poll_voting_stats(poll)
        rescue
          _ -> %{options: [], total_unique_voters: 0}
        end

      # Load user votes for this poll
      user_votes =
        if user do
          Events.list_user_poll_votes(poll, user)
        else
          []
        end

      # Get temp votes from assigns or default to empty
      temp_votes = Map.get(assigns, :temp_votes, %{})

      # Handle mode prop for consistent rendering approach
      # mode: :full (default) - Component renders with header
      # mode: :content - Component renders content only, parent handles header
      mode = Map.get(assigns, :mode, :full)

      {:ok,
       socket
       |> assign(:event, event)
       |> assign(:current_user, user)
       |> assign(:poll, poll)
       |> assign(:poll_options, poll_options)
       |> assign(:poll_stats, poll_stats)
       |> assign(:user_votes, user_votes)
       |> assign(:temp_votes, temp_votes)
       |> assign(:mode, mode)
       |> assign(:showing_add_form, false)
       |> assign(:option_title, "")
       |> assign(:adding_option, false)
       |> assign(:selected_place, nil)
       |> assign(:show_place_search, false)}
    else
      {:ok, assign(socket, :poll, nil)}
    end
  end

  @impl true
  def handle_event("show_add_form", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, assign(socket, :showing_add_form, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hide_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_add_form, false)
     |> assign(:option_title, "")}
  end

  def handle_event("update_option_field", %{"field" => "title", "value" => value}, socket) do
    {:noreply, assign(socket, :option_title, value)}
  end

  # Handle the select element's event structure (for time selector)
  def handle_event(
        "update_option_field",
        %{"_target" => ["time_selector"], "time_selector" => value},
        socket
      ) do
    {:noreply, assign(socket, :option_title, value)}
  end

  # Handle the case where the select element event structure is different (fallback)
  def handle_event("update_option_field", %{"_target" => ["undefined"]}, socket) do
    # This happens when the select element doesn't have a proper name attribute
    # Just return the socket without changes
    {:noreply, socket}
  end

  # Handle form changes (for the new input name structure)
  def handle_event("validate", %{"poll_option" => %{"title" => title}}, socket) do
    {:noreply, assign(socket, :option_title, title)}
  end

  def handle_event("toggle_place_search", _params, socket) do
    {:noreply, assign(socket, :show_place_search, !socket.assigns.show_place_search)}
  end

  def handle_event("clear_place", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_place, nil)
     |> assign(:show_place_search, true)
     |> assign(:option_title, "")}
  end

  def handle_event("add_option", %{"poll_option" => poll_option_params} = _params, socket) do
    if socket.assigns.adding_option do
      {:noreply, socket}
    else
      user = socket.assigns.current_user

      # Check if user is authenticated
      if is_nil(user) do
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to add suggestions.")
         |> assign(:adding_option, false)}
      else
        # Extract title from poll_option_params (from form) or fallback to assigns
        title = String.trim(poll_option_params["title"] || socket.assigns.option_title || "")

        if title == "" do
          {:noreply,
           socket
           |> put_flash(:error, "Title is required.")
           |> assign(:adding_option, false)}
        else
          # Set adding_option to true to prevent multiple requests
          socket = assign(socket, :adding_option, true)

          # Process poll option data using the SAME logic as manager area
          option_params = prepare_option_params(socket, poll_option_params, title, user)

          case Events.create_poll_option(option_params) do
            {:ok, _option} ->
              # Reload poll options to show the new option immediately
              updated_poll_options =
                Events.list_poll_options(socket.assigns.poll)
                |> Repo.preload(:suggested_by)

              # Notify the parent LiveView to reload polls for all users
              send(self(), {:poll_stats_updated, socket.assigns.poll.id, %{}})

              {:noreply,
               socket
               |> put_flash(:info, "Option added successfully!")
               |> assign(:adding_option, false)
               |> assign(:showing_add_form, false)
               |> assign(:option_title, "")
               |> assign(:selected_place, nil)
               |> assign(:poll_options, updated_poll_options)}

            {:error, changeset} ->
              require Logger
              Logger.error("Failed to create poll option: #{inspect(changeset)}")

              {:noreply,
               socket
               |> put_flash(:error, "Failed to add option. Please try again.")
               |> assign(:adding_option, false)}
          end
        end
      end
    end
  end

  # Handle the case where params don't match the expected structure (fallback)
  def handle_event("add_option", params, socket) do
    # Convert to the expected format and retry
    poll_option_params = %{
      "title" => socket.assigns.option_title,
      "external_id" => params["external_id"],
      "external_data" => params["external_data"],
      "image_url" => params["image_url"]
    }

    handle_event("add_option", %{"poll_option" => poll_option_params}, socket)
  end

  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    with {option_id_int, _} <- Integer.parse(option_id),
         option when not is_nil(option) <- Events.get_poll_option(option_id_int),
         user when not is_nil(user) <- socket.assigns.current_user,
         true <- Events.can_delete_option_based_on_poll_settings?(option, user) do
      case Events.delete_poll_option(option) do
        {:ok, _} ->
          # Reload poll options
          updated_poll_options =
            Events.list_poll_options(socket.assigns.poll)
            |> Repo.preload(:suggested_by)

          # Notify parent to reload
          send(self(), {:poll_stats_updated, socket.assigns.poll.id, %{}})

          {:noreply,
           socket
           |> put_flash(:info, "Option removed successfully.")
           |> assign(:poll_options, updated_poll_options)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove option.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "You are not authorized to remove this option.")}
    end
  end

  # Process poll option parameters using the SAME logic as manager area (OptionSuggestionComponent)
  defp prepare_option_params(socket, poll_option_params, title, user) do
    require Logger
    alias EventasaurusWeb.Services.PlacesDataService

    # Start with base parameters
    option_params =
      Map.merge(poll_option_params, %{
        "title" => title,
        "poll_id" => socket.assigns.poll.id,
        "suggested_by_id" => user.id,
        "status" => "active"
      })

    # Check if we have a selected place from native Google autocomplete
    cond do
      socket.assigns.poll.poll_type == "places" && socket.assigns[:selected_place] ->
        place_data = socket.assigns.selected_place

        # Use the rich data from the selected place
        option_params
        |> Map.put("title", Map.get(place_data, :title, title))
        |> Map.put("description", Map.get(place_data, :description, ""))
        |> Map.put("external_data", Map.get(place_data, :metadata, %{}))
        |> Map.put("image_url", Map.get(place_data, :image_url))

      # Apply the EXACT SAME processing as the manager area for places (fallback for JavaScript hook)
      socket.assigns.poll.poll_type == "places" &&
        Map.has_key?(option_params, "external_data") &&
          not is_nil(option_params["external_data"]) ->
        Logger.debug("Processing places option with PlacesDataService (public interface)")

        # Parse external_data if it's a JSON string (SAME AS MANAGER)
        external_data =
          case option_params["external_data"] do
            data when is_binary(data) ->
              case Jason.decode(data) do
                {:ok, decoded} -> decoded
                {:error, _} -> option_params["external_data"]
              end

            data ->
              data
          end

        if external_data && is_map(external_data) do
          # Use PlacesDataService to prepare data (SAME AS MANAGER)
          prepared_data = PlacesDataService.prepare_place_option_data(external_data)

          # Preserve any user-provided custom title/description over generated ones (SAME AS MANAGER)
          final_data =
            prepared_data
            |> maybe_preserve_user_input("title", option_params["title"])
            |> maybe_preserve_user_input("description", option_params["description"])

          # CRITICAL: Ensure required fields are preserved after PlacesDataService processing
          final_data =
            Map.merge(final_data, %{
              "poll_id" => option_params["poll_id"],
              "suggested_by_id" => option_params["suggested_by_id"],
              "status" => option_params["status"]
            })

          Logger.debug(
            "PlacesDataService applied successfully for place: #{final_data["title"]} (public interface)"
          )

          Logger.debug(
            "Final data poll_id: #{final_data["poll_id"]}, suggested_by_id: #{final_data["suggested_by_id"]}"
          )

          final_data
        else
          Logger.debug("PlacesDataService skipped - invalid external_data (public interface)")
          option_params
        end

      true ->
        # Non-places options or manual entry
        option_params
    end
  end

  # Helper to preserve user input over generated content (SAME AS MANAGER)
  defp maybe_preserve_user_input(prepared_data, key, user_value)
       when is_binary(user_value) and user_value != "" do
    Map.put(prepared_data, key, user_value)
  end

  defp maybe_preserve_user_input(prepared_data, _key, _user_value), do: prepared_data

  # Note: Native Google autocomplete sends place_selected events directly to this component
  # The parent needs to handle {:place_selected, data} and forward it to this component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-generic-poll">
      <%= if @poll do %>
        <div class="mb-6">
          <%= if @mode == :full do %>
            <div class="mb-4">
              <h3 class="text-lg font-semibold text-gray-900">
                <%= poll_emoji(@poll.poll_type) %>
                <%= get_poll_title_base(@poll) %>
                <%= if search_location = EventasaurusWeb.Utils.PollPhaseUtils.get_poll_search_location(@poll) do %>
                  <span class="text-sm text-gray-500 font-normal">(<%= search_location %>)</span>
                <% end %>
              </h3>
              <p class="text-sm text-gray-600">
                <%= PollPhaseUtils.get_phase_description(@poll.phase, @poll.poll_type) %>
              </p>
              <.voter_count poll_stats={@poll_stats} poll_phase={@poll.phase} class="mt-1" />
            </div>
          <% end %>

          <!-- Poll Options List with Voting -->
          <%= if length(@poll_options) > 0 do %>
            <%= if PollPhaseUtils.voting_allowed?(@poll.phase) do %>
              <!-- Voting Interface -->
              <div class="mb-6">
                <.live_component
                  module={EventasaurusWeb.VotingInterfaceComponent}
                  id={"voting-interface-#{@poll.id}"}
                  poll={@poll}
                  user={@current_user}
                  user_votes={@user_votes}
                  loading={false}
                  temp_votes={@temp_votes}
                  anonymous_mode={is_nil(@current_user)}
                  mode={@mode}
                />
              </div>
            <% else %>
              <!-- List Building Phase - Show Options Without Voting -->
              <div class="space-y-3">
                <%= for option <- sort_options_by_time(@poll_options, @poll.poll_type) do %>
                <div class="bg-white border border-gray-200 rounded-lg p-3 sm:p-4 hover:border-gray-300 transition-colors">
                  <div class="flex flex-col sm:flex-row">
                    <!-- Option Image (same as manager area) -->
                    <%= if option.image_url do %>
                      <img
                        src={option.image_url}
                        alt={"#{option.title} image"}
                        class="w-full sm:w-16 h-32 sm:h-24 object-cover rounded-md shadow-sm mb-3 sm:mb-0 sm:mr-4 flex-shrink-0"
                        loading="lazy"
                      />
                    <% end %>

                    <div class="flex-1 min-w-0">
                      <h4 class="font-medium text-gray-900 mb-1 break-words">
                        <%= if @poll.poll_type == "time" do %>
                          <%= format_time_for_display(option.title) %>
                        <% else %>
                          <%= option.title %>
                        <% end %>
                      </h4>

                      <%= if option.description && String.length(option.description) > 0 do %>
                        <p class="text-sm text-gray-600 line-clamp-3 mb-2 break-words"><%= option.description %></p>
                      <% end %>

                      <!-- Show who suggested this option and import attribution -->
                      <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@poll) do %>
                        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                          <div class="text-xs text-gray-500 space-y-1">
                            <%= if option.suggested_by do %>
                              <p>
                                Suggested by <%= display_suggester_name(option.suggested_by) %>
                              </p>
                            <% end %>

                            <%= if import_info = get_import_info(option) do %>
                              <p class="flex items-center gap-1 text-blue-600">
                                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
                                </svg>
                                <%= format_import_attribution(import_info) %>
                              </p>
                            <% end %>
                          </div>

                          <!-- Delete button for own suggestions within 5 minutes -->
                          <%= if @current_user && Events.can_delete_option_based_on_poll_settings?(option, @current_user) do %>
                            <div class="flex items-center space-x-2">
                              <button
                                type="button"
                                phx-click="delete_option"
                                phx-value-option-id={option.id}
                                phx-target={@myself}
                                data-confirm="Are you sure you want to remove this option? This action cannot be undone."
                                class="text-red-600 hover:text-red-900 text-xs sm:text-sm font-medium touch-target"
                              >
                                Remove
                              </button>
                              <% time_remaining = get_deletion_time_remaining(option.inserted_at) %>
                              <%= if time_remaining > 0 do %>
                                <span class="text-xs text-gray-500">
                                  (<%= format_deletion_time_remaining(time_remaining) %> left)
                                </span>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>

                      <!-- Voting buttons removed - handled by VotingInterfaceComponent in public_event_live.ex -->
                    </div>
                  </div>
                </div>
              <% end %>
              </div>
            <% end %>
          <% else %>
            <div class="text-center py-8 text-gray-500">
              <svg class="w-12 h-12 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M9 5H7a2 2 0 00-2 2v6a2 2 0 002 2h6a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
              </svg>
              <% {title, subtitle} = PollPhaseUtils.get_empty_state_message(@poll.poll_type) %>
              <p class="font-medium"><%= title %></p>
              <p class="text-sm"><%= subtitle %></p>
            </div>
          <% end %>

          <!-- Add Option Button/Form -->
          <%= if PollPhaseUtils.suggestions_allowed?(@poll.phase) do %>
            <%= if @current_user do %>
              <%= if @showing_add_form do %>
                <!-- Inline Add Option Form -->
                <div class="mt-4 p-4 border-2 border-dashed border-gray-300 rounded-lg bg-gray-50"
                     data-event-venue-lat={@event && @event.venue && @event.venue.latitude}
                     data-event-venue-lng={@event && @event.venue && @event.venue.longitude}
                     data-event-venue-name={@event && @event.venue && @event.venue.name}
                     data-poll-options-data={Jason.encode!(extract_poll_options_coordinates(@poll_options))}>
                  <div class="mb-4">
                    <h4 class="text-base sm:text-md font-medium text-gray-900 mb-2">Add <%= get_suggestion_title(@poll) %></h4>
                    <p class="text-sm text-gray-600">Share your suggestion with the group</p>
                  </div>

                  <!-- Location Context Indicator -->
                  <div class="location-context-indicator hidden mb-3 text-xs text-gray-600 bg-blue-50 px-3 py-1 rounded-full flex items-center">
                    <span class="location-icon mr-1">🌍</span>
                    <span>Searching globally</span>
                  </div>

                  <form phx-submit="add_option" phx-change="validate" phx-target={@myself}>
                    <div class="space-y-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 mb-1">
                          <%= get_title_label(@poll) %> <span class="text-red-500">*</span>
                        </label>
                        <%= if @poll.poll_type == "time" do %>
                          <!-- Use a hidden input for form submission along with the time selector -->
                          <input
                            type="hidden"
                            name="poll_option[title]"
                            value={@option_title}
                          />
                          <select
                            id={"time-selector-#{@poll.id}"}
                            name="time_selector"
                            phx-change="update_option_field"
                            phx-value-field="title"
                            phx-target={@myself}
                            class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                            required
                          >
                            <option value="" disabled selected={@option_title == ""}>Select a time...</option>
                            <%= for time_option <- time_options() do %>
                              <option value={time_option.value} selected={@option_title == time_option.value}>
                                <%= time_option.display %>
                              </option>
                            <% end %>
                          </select>
                        <% else %>
                          <%= if @poll.poll_type == "places" do %>
                            <%= if @selected_place do %>
                              <!-- Show selected place -->
                              <div class="bg-gray-50 rounded-lg border border-gray-200 p-3">
                                <div class="flex items-center justify-between">
                                  <div class="flex-1">
                                    <h4 class="font-medium text-gray-900"><%= @selected_place.title %></h4>
                                    <%= if @selected_place.description do %>
                                      <p class="text-sm text-gray-600 mt-1"><%= @selected_place.description %></p>
                                    <% end %>
                                  </div>
                                  <button
                                    type="button"
                                    phx-click="clear_place"
                                    phx-target={@myself}
                                    class="ml-3 text-gray-400 hover:text-gray-600"
                                  >
                                    <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                                    </svg>
                                  </button>
                                </div>
                              </div>
                              <!-- Hidden input for the title -->
                              <input type="hidden" name="poll_option[title]" value={@selected_place.title} />
                            <% else %>
                              <!-- Native Google Places Autocomplete -->
                              <input
                                type="text"
                                id={"place-search-#{@poll.id}"}
                                name="poll_option[title]"
                                placeholder={get_title_placeholder(@poll)}
                                phx-hook="PlacesSuggestionSearch"
                                data-location-scope={get_location_scope(@poll)}
                                data-search-location={get_search_location_json(@poll)}
                                autocomplete="off"
                                class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                                required
                              />
                            <% end %>
                          <% else %>
                            <input
                              type="text"
                              id={"input-#{@poll.id}"}
                              name="poll_option[title]"
                              placeholder={get_title_placeholder(@poll)}
                              value={@option_title}
                              phx-keyup="update_option_field"
                              phx-value-field="title"
                              phx-target={@myself}
                              class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                              required
                            />
                          <% end %>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-3 mt-4">
                      <button
                        type="button"
                        phx-click="hide_add_form"
                        phx-target={@myself}
                        class="w-full sm:w-auto px-4 py-3 sm:py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 touch-target"
                      >
                        Cancel
                      </button>
                      <button
                        type="submit"
                        disabled={@adding_option || String.trim(@option_title) == ""}
                        class="w-full sm:w-auto px-4 py-3 sm:py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed touch-target"
                      >
                        <%= if @adding_option do %>
                          <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 714 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                          Adding...
                        <% else %>
                          Add Suggestion
                        <% end %>
                      </button>
                    </div>
                  </form>
                </div>
              <% else %>
                <!-- Add Option Button -->
                <div class="mt-4">
                  <button
                    phx-click="show_add_form"
                    phx-target={@myself}
                    class="w-full flex items-center justify-center px-4 py-4 sm:py-3 border border-gray-300 border-dashed rounded-lg text-sm font-medium text-gray-600 hover:text-gray-900 hover:border-gray-400 transition-colors touch-target"
                  >
                    <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    <%= PollPhaseUtils.get_add_button_text(@poll.poll_type) %>
                  </button>
                </div>
              <% end %>
            <% else %>
              <!-- Show login prompt for anonymous users -->
              <div class="mt-4">
                <p class="text-sm text-gray-500 text-center py-4 bg-gray-50 rounded-lg">
                  Please <.link href="/login" class="text-blue-600 hover:underline">log in</.link> to suggest options.
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>No poll found for this event.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions for poll type customization

  defp get_poll_title_base(%{poll_type: poll_type} = poll) do
    case poll_type do
      "places" ->
        # Get the location scope for places polls
        scope_display = PollPhaseUtils.format_poll_type(poll)
        "#{scope_display} Suggestions"

      "time" ->
        "Time Suggestions"

      "date_selection" ->
        "DateTime Selection"

      "custom" ->
        "General Options"

      _ ->
        "Suggestions"
    end
  end

  defp get_poll_title_base(poll_type) when is_binary(poll_type) do
    case poll_type do
      "places" -> "Place Suggestions"
      "time" -> "Time Suggestions"
      "date_selection" -> "DateTime Selection"
      "custom" -> "General Options"
      _ -> "Suggestions"
    end
  end

  defp get_suggestion_title(%{poll_type: poll_type} = poll) do
    case poll_type do
      "places" ->
        scope_display = PollPhaseUtils.format_poll_type(poll)
        "#{scope_display} Suggestion"

      "time" ->
        "Time"

      "date_selection" ->
        "DateTime"

      "custom" ->
        "Option"

      _ ->
        "Suggestion"
    end
  end

  defp get_suggestion_title(poll_type) when is_binary(poll_type) do
    case poll_type do
      "places" -> "Place Suggestion"
      "time" -> "Time"
      "date_selection" -> "DateTime"
      "custom" -> "Option"
      _ -> "Suggestion"
    end
  end

  defp get_title_label(%{poll_type: poll_type} = poll) do
    case poll_type do
      "places" ->
        scope_display = PollPhaseUtils.format_poll_type(poll)
        "#{scope_display} Name"

      "time" ->
        "Time"

      "date_selection" ->
        "DateTime"

      "custom" ->
        "Option Title"

      _ ->
        "Title"
    end
  end

  defp get_title_label(poll_type) when is_binary(poll_type) do
    case poll_type do
      "places" -> "Place Name"
      "time" -> "Time"
      "date_selection" -> "DateTime"
      "custom" -> "Option Title"
      _ -> "Title"
    end
  end

  defp get_title_placeholder(%{poll_type: poll_type} = poll) do
    case poll_type do
      "places" ->
        scope_display = PollPhaseUtils.format_poll_type(poll)
        "Enter #{String.downcase(scope_display)} name..."

      "time" ->
        "Select a time..."

      "date_selection" ->
        "Select a DateTime..."

      "custom" ->
        "Enter your option..."

      _ ->
        "Enter title..."
    end
  end

  defp get_title_placeholder(poll_type) when is_binary(poll_type) do
    case poll_type do
      "places" -> "Enter place name..."
      "time" -> "Select a time..."
      "date_selection" -> "Select a DateTime..."
      "custom" -> "Enter your option..."
      _ -> "Enter title..."
    end
  end

  defp extract_poll_options_coordinates(poll_options) when is_list(poll_options) do
    poll_options
    |> Enum.map(fn option ->
      case option.external_data do
        %{"latitude" => lat, "longitude" => lng} when is_number(lat) and is_number(lng) ->
          %{latitude: lat, longitude: lng}

        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp extract_poll_options_coordinates(_), do: []

  defp time_options() do
    # Start at 10:00 AM (10:00) and go through 11:30 PM (23:30)
    # 30-minute increments
    10..23
    |> Enum.flat_map(fn hour ->
      [
        %{
          value: TimeUtils.format_time_value(hour, 0),
          display: TimeUtils.format_time_display(hour, 0)
        },
        %{
          value: TimeUtils.format_time_value(hour, 30),
          display: TimeUtils.format_time_display(hour, 30)
        }
      ]
    end)
  end

  defp format_time_for_display(time_value) do
    # This function is used to display the time value in a user-friendly format.
    # It expects a string like "HH:MM" or "HH:MM:SS" and converts it to 24-hour format.
    # For example, "10:00" stays "10:00", "14:30" stays "14:30".
    case TimeUtils.parse_time_string(time_value) do
      {:ok, {hour, minute}} ->
        TimeUtils.format_time_display(hour, minute)

      {:error, _} ->
        # Return original if parsing fails
        time_value
    end
  end

  defp sort_options_by_time(options, poll_type) do
    if poll_type == "time" do
      # For time polls, sort by the time value (e.g., "10:00", "10:30", "11:00")
      Enum.sort_by(options, fn option ->
        TimeUtils.parse_time_for_sort(option.title)
      end)
    else
      # For non-time polls, sort by title (alphabetically)
      Enum.sort_by(options, fn option -> option.title end)
    end
  end

  # Calculate remaining seconds for deletion window
  defp get_deletion_time_remaining(inserted_at) when is_nil(inserted_at), do: 0

  defp get_deletion_time_remaining(inserted_at) do
    elapsed_seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second)
    # 300 seconds = 5 minutes
    max(0, 300 - elapsed_seconds)
  end

  # Format remaining time for display
  defp format_deletion_time_remaining(seconds) when seconds <= 0, do: ""

  defp format_deletion_time_remaining(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 -> "#{minutes}:#{String.pad_leading(to_string(remaining_seconds), 2, "0")}"
      true -> "#{remaining_seconds}s"
    end
  end

  # Helper function to display suggester name with proper blank value handling
  defp display_suggester_name(suggested_by) when is_nil(suggested_by), do: "Anonymous"
  defp display_suggester_name(%Ecto.Association.NotLoaded{}), do: "Anonymous"

  defp display_suggester_name(suggested_by) do
    name = Map.get(suggested_by, :name)
    username = Map.get(suggested_by, :username)
    email = Map.get(suggested_by, :email)

    cond do
      is_binary(name) and String.trim(name) != "" -> String.trim(name)
      is_binary(username) and String.trim(username) != "" -> String.trim(username)
      is_binary(email) and String.trim(email) != "" -> String.trim(email)
      true -> "Anonymous"
    end
  end

  # Helper function to get location scope from poll settings
  defp get_location_scope(poll) do
    Poll.get_location_scope(poll)
  end

  # Helper function to get search location data as JSON for JavaScript
  defp get_search_location_json(poll) do
    if poll && poll.settings do
      case Map.get(poll.settings, "search_location_data") do
        data when is_map(data) -> Jason.encode!(data)
        data when is_binary(data) -> data
        _ -> ""
      end
    else
      ""
    end
  end
end
